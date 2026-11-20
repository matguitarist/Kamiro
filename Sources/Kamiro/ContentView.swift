import LogKitUI
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            page(model.sidebar ?? .overview)
        }
        .task {
            SeedData.addIfRequested(model: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings, openWindow: openWindow)
        }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(selection: $model.sidebar) {
            ForEach(SidebarItem.allCases) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
    }

    @ViewBuilder
    private func page(_ item: SidebarItem) -> some View {
        switch item {
        case .overview:
            ContentUnavailableView {
                Label("Kamiro", systemImage: "folder")
            } description: {
                Text("Your files, the Finder way, with the habits of Windows File Explorer: cut and paste, a path you can type, details columns, and folder sizes. Browsing comes next.")
            }
            .navigationTitle("Overview")
        case .log:
            LogViewer(model: model.logViewer)
                .navigationTitle("Log")
        }
    }
}

/// Seed mode for snapshots: a few log lines so the Log page shows something.
enum SeedData {
    static func addIfRequested(model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1", Store.isOverridden else { return }
        model.log.post(.info, "Opened ~/Documents", source: "Browse")
        model.log.post(.info, "Copied 3 items to ~/Desktop", source: "Transfer", date: .now, detail: "report.pdf\nphoto.heic\nnotes.md")
        model.log.post(.warning, "Kamiro can't open ~/Desktop: access was denied", source: "Access")
        model.log.post(.error, "Couldn't move budget.xlsx: the disk is full", source: "Transfer")
    }
}
