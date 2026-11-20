import Foundation
import LogKitUI
import Observation

/// What every window shares: the Settings tab, the language, updates, and the log.
@Observable
final class AppModel {
    var settingsTab: SettingsTab = .general
    var language = AppLanguage.current {
        didSet { language.apply() }
    }
    var checksForUpdates = Updater.shared.automaticallyChecks {
        didSet { Updater.shared.automaticallyChecks = checksForUpdates }
    }

    let log: LogStore
    let logViewer: LogViewerModel

    init(log: LogStore) {
        self.log = log
        logViewer = LogViewerModel(store: log)
        logViewer.newestFirst = true
        SeedData.addIfRequested(log: log)
    }
}

/// Seed mode for snapshots: a few log lines so the Log window shows something.
enum SeedData {
    static func addIfRequested(log: LogStore) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1", Store.isOverridden else { return }
        log.post(.info, "Opened ~/Documents", source: "Browse")
        log.post(.info, "Copied 3 items to ~/Desktop", source: "Transfer", date: .now, detail: "report.pdf\nphoto.heic\nnotes.md")
        log.post(.warning, "Kamiro can't open ~/Desktop: access was denied", source: "Access")
        log.post(.error, "Couldn't move budget.xlsx: the disk is full", source: "Transfer")
    }
}
