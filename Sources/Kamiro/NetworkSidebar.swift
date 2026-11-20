import KamiroKit
import Network
import Observation
import SwiftUI

// MARK: - The sidebar's Network section

/// File servers on the local network (SMB and AFP), found with Bonjour while a window is open.
/// macOS asks once before Kamiro may look; test runs never look.
@MainActor @Observable
final class NetworkServers {
    static let shared = NetworkServers()
    private(set) var servers: [NetworkServer] = []
    @ObservationIgnored private var browsers: [NWBrowser] = []
    @ObservationIgnored private var names: [NetworkServer.Kind: [String]] = [:]

    func start() {
        guard browsers.isEmpty, !Store.isOverridden else { return }
        for (kind, type) in [(NetworkServer.Kind.smb, "_smb._tcp"), (.afp, "_afpovertcp._tcp")] {
            let browser = NWBrowser(for: .bonjour(type: type, domain: "local."), using: .tcp)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                let found = results.compactMap { result -> String? in
                    if case .service(let name, _, _, _) = result.endpoint { return name }
                    return nil
                }
                Task { @MainActor in self?.update(kind, found) }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }
    }

    private func update(_ kind: NetworkServer.Kind, _ found: [String]) {
        names[kind] = found
        servers = NetworkServer.merged(smb: names[.smb] ?? [], afp: names[.afp] ?? [])
    }
}

/// Mounted servers, servers found nearby, and Connect to Server….
struct NetworkSection: View {
    let browser: BrowserModel
    let volumes: [Volume]
    @Binding var renaming: Volume?
    private var found: NetworkServers { .shared }

    /// Rows that act instead of going somewhere; the sidebar's selection hands them here.
    static let connectRow = URL(string: "kamiro:connect-to-server")!

    var body: some View {
        Section("Network") {
            ForEach(volumes) { volume in
                VolumeRow(volume: volume, browser: browser, renaming: $renaming)
            }
            ForEach(found.servers) { server in
                if let url = server.url {
                    Label { Text(verbatim: server.name) } icon: { Image(systemName: "server.rack") }
                        .tag(url)
                        .help(String(localized: "Connect to “\(server.name)”"))
                }
            }
            Label("Connect to Server…", systemImage: "plus.circle")
                .tag(Self.connectRow)
        }
        .onAppear { found.start() }
    }

    /// A server row or Connect to Server… was clicked.
    static func act(on url: URL, browser: BrowserModel) -> Bool {
        if url == connectRow {
            browser.showConnectToServer()
            return true
        }
        guard let scheme = url.scheme, ["smb", "afp"].contains(scheme) else { return false }
        Task {
            do {
                try await browser.connect(to: url)
            } catch ServerMount.Failure.cancelled {
            } catch {
                Store.log.post(.error, "Couldn't connect to \(url.absoluteString): \(error.localizedDescription)", source: "Servers")
                NSSound.beep()
            }
        }
        return true
    }
}

/// A disk or server in the sidebar, with ⏏ when it can go.
struct VolumeRow: View {
    let volume: Volume
    let browser: BrowserModel
    @Binding var renaming: Volume?

    var body: some View {
        HStack(spacing: Space.xs) {
            Label(volume.name, systemImage: volume.symbol)
            Spacer(minLength: 0)
            // Disks that can go show ⏏ at the end of their row, like the Finder.
            if volume.actions.contains(.eject) {
                Button("Eject", systemImage: "eject") { ItemActions.eject(volume, from: browser) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(String(localized: "Eject “\(volume.name)”"))
            }
        }
        .tag(volume.url)
        .dropDestination(for: URL.self) { urls, _ in browser.drop(urls, into: volume.url) }
        .contextMenu { VolumeMenu(volume: volume, model: browser, renaming: $renaming) }
    }
}
