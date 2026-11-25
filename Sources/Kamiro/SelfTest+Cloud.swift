import AppKit
import AppTestKit
import KamiroKit

/// S-057 and S-058: iCloud Drive, sync folders and cloud status, on the test home in /tmp
/// (tools/seed-tree.sh), where each item's status comes from an attribute.
extension SelfTest {
    static func cloud(browser: BrowserModel, seed: URL) async {
        let drive = Cloud.drive
        check("iCloud Drive and the sync folder are found", Cloud.places().map(\.name) == ["iCloud Drive", "Google Drive"],
              Cloud.places().map(\.name).joined(separator: ", "))
        let items = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items) ?? []
        check("Go › iCloud Drive is ⇧⌘I", items.contains { $0.title == "iCloud Drive" && $0.keyEquivalent == "i"
              && $0.keyEquivalentModifierMask == [.command, .shift] })

        // S-057: iCloud Drive and the apps' folders.
        browser.go(to: drive)
        await browser.waitUntilLoaded()
        check("iCloud Drive is named so", browser.title == "iCloud Drive")
        let names = browser.items.map(\.name)
        check("iCloud Drive lists its own items and the apps' folders that hold documents",
              ["Numbers", "Obsidian", "Projects", "Shopping.txt"].allSatisfy(names.contains) && !names.contains("Mail"),
              names.joined(separator: ", "))
        check("iCloud Drive is the top of its path", !browser.canGoUp && Location(drive).crumbs == [drive])
        guard let numbers = browser.items.first(where: { $0.name == "Numbers" })?.url else { return }
        browser.selection = [numbers]
        let appMenu = browser.contextMenu(onItems: true).items.map(\.title)
        check("an app's folder can't be cut, renamed or trashed",
              ![String(localized: "Cut"), String(localized: "Rename"), String(localized: "Move to Trash")].contains { appMenu.contains($0) })
        browser.trashSelection()
        check("…even with the menu bar's Move to Trash", FileManager.default.fileExists(atPath: numbers.path))
        browser.open([numbers])
        await browser.waitUntilLoaded()
        check("an app's folder opens, inside iCloud Drive", browser.folder == numbers && Location(numbers).crumbs == [drive, numbers]
              && browser.title == "Numbers")
        browser.goUp()
        await browser.waitUntilLoaded()
        check("Up from an app's folder goes to iCloud Drive", browser.folder == drive && browser.selection == [numbers])

        // S-058: cloud status.
        await browser.waitForCloud()
        let scan = drive.appending(path: "Scan.pdf").canonical
        let slides = drive.appending(path: "Slides.key").canonical
        check("a file only in the cloud shows Not Downloaded", browser.cloud[scan] == .notDownloaded)
        check("a file going up shows Uploading", browser.cloud[slides] == .uploading)
        check("a downloaded file shows no icon", browser.cloud[drive.appending(path: "Shopping.txt").canonical] == .downloaded
              && CloudStatus.downloaded.symbol == nil)
        check("a cloud folder shows the Cloud Status column after Name", browser.columns.prefix(2) == [.name, .cloud])
        // The list redraws the column on SwiftUI's next update.
        var cell: NSTableCellView?
        for _ in 0..<40 {
            let column = browser.details?.table?.column(withIdentifier: ListColumn.cloud.identifier) ?? -1
            let row = browser.details?.rowOf[scan] ?? -1
            cell = column >= 0 && row >= 0
                ? browser.details?.table?.view(atColumn: column, row: row, makeIfNecessary: true) as? NSTableCellView : nil
            if cell?.imageView?.image != nil { break }
            try? await Task.sleep(for: .seconds(0.05))
        }
        check("the column shows the cloud icon", cell?.imageView?.image != nil && cell?.toolTip == String(localized: "Not Downloaded"),
              "image \(cell?.imageView?.image != nil), tip \(cell?.toolTip ?? "none"), status \(String(describing: browser.cloud[scan])), "
              + "versions \(browser.cloudVersion)/\(browser.details?.cloudVersion ?? -9), window \(browser.details?.table?.window != nil), "
              + "renaming \(browser.details?.renaming != nil), mode \(browser.mode)")
        browser.selection = [scan]
        var titles = browser.contextMenu(onItems: true).items.map(\.title)
        check("a file in the cloud offers Download Now, not Remove Download",
              titles.contains(String(localized: "Download Now")) && !titles.contains(String(localized: "Remove Download")))
        browser.downloadSelection()
        for _ in 0..<40 where browser.cloud[scan] != .downloaded { try? await Task.sleep(for: .seconds(0.05)) }
        check("Download Now downloads it", browser.cloud[scan] == .downloaded)
        titles = browser.contextMenu(onItems: true).items.map(\.title)
        check("…then Remove Download is offered", titles.contains(String(localized: "Remove Download"))
              && !titles.contains(String(localized: "Download Now")))
        browser.removeDownloadOfSelection()
        for _ in 0..<40 where browser.cloud[scan] != .notDownloaded { try? await Task.sleep(for: .seconds(0.05)) }
        check("Remove Download puts it back in the cloud only", browser.cloud[scan] == .notDownloaded)

        // A sync app's folder.
        if let google = Cloud.places().last?.url {
            browser.go(to: google)
            await browser.waitUntilLoaded()
            check("a sync folder is a top, named after its app", browser.title == "Google Drive" && !browser.canGoUp)
            let notes = google.appending(path: "My Drive/Notes.txt").canonical
            browser.go(to: notes.deletingLastPathComponent())
            await browser.waitUntilLoaded()
            await browser.waitForCloud()
            check("files in a sync folder show their cloud status too", browser.cloud[notes] == .notDownloaded)
        }

        // Outside the cloud nothing is read.
        browser.go(to: seed)
        await browser.waitUntilLoaded()
        await browser.waitForCloud()
        check("folders outside the cloud read no status and show no Cloud Status column",
              browser.cloud.isEmpty && !browser.columns.contains(.cloud))
    }
}
