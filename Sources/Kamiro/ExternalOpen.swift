import AppKit
import KamiroKit
import SwiftUI

/// Folders and files other apps send Kamiro: "Show in Finder" once Kamiro shows files (S-038),
/// the kamiro command (S-039), Open With, a drop on the Dock icon. Each folder opens in a
/// window; each file shows selected in its folder. Launched to open something, Kamiro opens
/// it in its first window rather than beside it.
@MainActor
enum ExternalOpen {
    private static var pending: [OpenRequest] = []
    private static var openWindow: OpenWindowAction?
    /// The window Kamiro opened at launch, until it's used or a few seconds have passed.
    private static weak var launchBrowser: BrowserModel?
    static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.mathieuares.kamiro" }

    /// From the Open Documents event (application(_:open:)), or the Reveal event when `reveal`.
    static func open(_ urls: [URL], reveal: Bool = false) {
        let requests = urls.compactMap { OpenRequest($0, reveal: reveal) }
        let paths = urls.map(\.path).joined(separator: ", ")
        Store.log.post(.info, "\(reveal ? "Show" : "Open") \(paths)", source: "Open")
        guard !requests.isEmpty else { return }
        pending += requests
        deliver()
        NSApp.activate()
    }

    /// Every browser window calls this as it appears; the first one gives the way to open windows.
    static func windowAppeared(_ browser: BrowserModel, openWindow: OpenWindowAction) {
        if Self.openWindow == nil {
            Self.openWindow = openWindow
            launchBrowser = browser
            Task {
                try? await Task.sleep(for: .seconds(3))
                launchBrowser = nil
            }
        }
        deliver()
    }

    private static func deliver() {
        guard let openWindow, !pending.isEmpty else { return }
        // Taken first: a window that opens calls back here before openWindow returns.
        var requests = pending
        pending = []
        if let browser = launchBrowser {
            launchBrowser = nil
            let first = requests.removeFirst()
            browser.go(to: first.folder, select: Set([first.select].compactMap { $0 }))
        }
        for request in requests {
            openWindow(id: KamiroApp.browserID, value: WindowStart(url: request.folder, select: request.select))
        }
    }
}

/// Settings › General › Command Line (S-039): installs and removes the kamiro command.
/// /usr/local/bin needs an administrator's password on most Macs; macOS asks for it.
/// Test runs use /tmp/Kamiro-bin.
@MainActor @Observable
final class CommandLineStore {
    static let shared = CommandLineStore()

    private(set) var status: CommandLineTool.Status = .missing
    private(set) var failure: String?

    let folder = Store.isOverridden ? URL(filePath: "/tmp/Kamiro-bin") : CommandLineTool.standardFolder
    var path: String { folder.appending(path: CommandLineTool.name).path }

    private init() { refresh() }

    func refresh() {
        status = CommandLineTool.status(in: folder, bundleID: ExternalOpen.bundleID)
    }

    func install() {
        guard status != .foreign else { return }
        let script = CommandLineTool.script(bundleID: ExternalOpen.bundleID)
        let target = folder.appending(path: CommandLineTool.name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: target)
            try Data(script.utf8).write(to: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
            done("Installed \(target.path)")
        } catch {
            // Not ours to write: ask macOS for an administrator's password.
            let staged = FileManager.default.temporaryDirectory.appending(path: "kamiro-\(UUID().uuidString)")
            do { try Data(script.utf8).write(to: staged) } catch { return fail(error.localizedDescription) }
            defer { try? FileManager.default.removeItem(at: staged) }
            asAdministrator("mkdir -p \(Self.quoted(folder.path)) && install -m 755 \(Self.quoted(staged.path)) \(Self.quoted(target.path))",
                            success: "Installed \(target.path)")
        }
    }

    func remove() {
        guard status == .installed || status == .outdated else { return }
        let target = folder.appending(path: CommandLineTool.name)
        do {
            try FileManager.default.removeItem(at: target)
            done("Removed \(target.path)")
        } catch {
            asAdministrator("rm -f \(Self.quoted(target.path))", success: "Removed \(target.path)")
        }
    }

    private func asAdministrator(_ command: String, success: String) {
        let source = "do shell script \"\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        var info: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&info)
        if let info {
            // -128: Cancel in the password dialog; nothing to report.
            if info[NSAppleScript.errorNumber] as? Int == -128 { return refresh() }
            return fail(info[NSAppleScript.errorMessage] as? String ?? String(localized: "macOS refused the change."))
        }
        done(success)
    }

    private func done(_ message: String) {
        failure = nil
        refresh()
        Store.log.post(.info, message, source: "Command Line")
    }

    private func fail(_ message: String) {
        failure = message
        refresh()
        Store.log.post(.error, "kamiro command: \(message)", source: "Command Line")
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
