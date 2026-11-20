import AppKit
import KamiroKit
import LogKitUI

/// Self-test for agents: drives the app model on a /tmp store, prints PASS or
/// FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/Kamiro-self.json ~/Applications/Kamiro.app/Contents/MacOS/Kamiro --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden, Store.url.path.hasPrefix("/tmp/") || Store.url.path.hasPrefix("/private/tmp/") else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }
        Task {
            check("the store's folder exists", FileManager.default.fileExists(atPath: Store.url.deletingLastPathComponent().path))
            check("the log lives next to the store", Store.logURL.deletingLastPathComponent() == Store.url.deletingLastPathComponent())

            model.log.post(.info, "Self-test line", source: "SelfTest")
            try? await Task.sleep(for: .seconds(0.3))
            check("the app writes a log line", model.log.entries.contains { $0.message == "Self-test line" })
            model.log.flushFile()
            let text = (try? String(contentsOf: Store.logURL, encoding: .utf8)) ?? ""
            check("the log line reaches the log file", text.contains("Self-test line"))

            check("the address bar splits a path into crumbs",
                  Location(URL(fileURLWithPath: "/Users")).crumbs.map(\.path) == ["/", "/Users"])

            for item in SidebarItem.allCases {
                model.sidebar = item
                try? await Task.sleep(for: .seconds(0.2))
                check("the \(item.rawValue) page opens", model.sidebar == item)
            }

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
