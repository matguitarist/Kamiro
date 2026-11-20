import Foundation
import LogKitUI
import Observation

/// The app's state: which page shows, the Settings tab, and the log.
@Observable
final class AppModel {
    var sidebar: SidebarItem? = .overview
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
    }
}

/// The sidebar's pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case overview, log

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .log: String(localized: "Log")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "folder"
        case .log: "list.bullet.rectangle"
        }
    }
}
