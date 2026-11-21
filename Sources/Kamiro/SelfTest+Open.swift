import AppKit
import KamiroKit

/// S-039: the kamiro command, and folders and files sent by other apps.
extension SelfTest {
    static func externalOpen(browser: BrowserModel, seed: URL) async {
        func pause(_ seconds: Double = 0.3) async { try? await Task.sleep(for: .seconds(seconds)) }

        // Settings › General › Command Line installs into /tmp/Kamiro-bin on a test run.
        let command = CommandLineStore.shared
        try? FileManager.default.removeItem(at: command.folder)
        command.refresh()
        check("with no kamiro command, Command Line offers Install", command.status == .missing)
        command.install()
        let executable = FileManager.default.isExecutableFile(atPath: command.path)
        check("Install writes an executable kamiro", command.status == .installed && executable, "\(command.status)")
        let script = (try? String(contentsOfFile: command.path, encoding: .utf8)) ?? ""
        check("…that opens this app", script.contains("open -b \(ExternalOpen.bundleID)"))
        command.remove()
        check("Remove takes it away", command.status == .missing && !FileManager.default.fileExists(atPath: command.path))
        try? "#!/bin/sh\necho mine\n".write(toFile: command.path, atomically: true, encoding: .utf8)
        command.refresh()
        command.install()
        let kept = (try? String(contentsOfFile: command.path, encoding: .utf8)) == "#!/bin/sh\necho mine\n"
        check("another kamiro is left alone", command.status == .foreign && kept)
        try? FileManager.default.removeItem(at: command.folder)

        // What open(1) sends: an Open Documents event, here sent to this app by itself.
        browser.go(to: seed)
        await browser.waitUntilLoaded()
        let file = seed.appending(path: "Projects/notes.md").canonical
        let windows = NSApp.windows.filter { Tabs.isBrowser($0) && $0.isVisible }.count
        send([file])
        var opened: BrowserModel?
        for _ in 0..<40 {
            await pause(0.1)
            if let front = MenuState.shared.browser, front !== browser, front.state == .ready { opened = front; break }
        }
        check("kamiro on a file opens its folder in a new window", opened?.folder == file.deletingLastPathComponent().canonical,
              opened?.folder.path ?? "no window")
        check("…with the file selected", opened?.selection == [file], "\(opened?.selection.map(\.lastPathComponent) ?? [])")
        let visible = NSApp.windows.filter { Tabs.isBrowser($0) && $0.isVisible }.count
        check("…in front", opened != nil && MenuState.shared.browser === opened && visible == windows + 1, "\(visible) windows, was \(windows)")
        NSApp.keyWindow?.close()
        await pause()
        browser.details?.table?.window?.makeKeyAndOrderFront(nil)
        await pause()
    }

    /// Sends this app an Open Documents event for `urls`, as open(1) would. Sent to itself, the
    /// event is handled during the send, which then reports a timeout (-1712): the windows
    /// checked after it are what count.
    private static func send(_ urls: [URL]) {
        let list = NSAppleEventDescriptor.list()
        for (index, url) in urls.enumerated() { list.insert(NSAppleEventDescriptor(fileURL: url), at: index + 1) }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenDocuments),
                                           targetDescriptor: NSAppleEventDescriptor(processIdentifier: getpid()),
                                           returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(list, forKeyword: keyDirectObject)
        _ = try? event.sendEvent(options: [.noReply], timeout: 1)
    }
}
