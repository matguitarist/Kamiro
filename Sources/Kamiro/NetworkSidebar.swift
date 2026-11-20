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

extension BrowserModel {
    /// The window shows a server's shares.
    var isServerPage: Bool { if case .server = place { true } else { false } }

    /// Opens a share: at once when it's mounted, else mounted first (macOS asks for a password
    /// when the keychain has none).
    func openShare(_ url: URL) {
        if let volume = Volumes.mounted().first(where: { volume in
            volume.remoteURL.map { ServerHost.same($0, url) && ServerHost.share(of: $0)?.lowercased() == ServerHost.share(of: url)?.lowercased() } ?? false
        }) {
            go(to: volume.url)
            return
        }
        Task {
            do {
                try await connect(to: url)
            } catch ServerMount.Failure.cancelled {
            } catch {
                Store.log.post(.error, "Couldn't open \(url.absoluteString): \(error.localizedDescription)", source: "Servers")
                NSSound.beep()
            }
        }
    }

    /// Connect As…: macOS's own name, password and share dialogs, for a server that didn't list
    /// its shares as guest. The shares list again once a share is mounted.
    func connectAs(_ server: URL) {
        Task {
            do {
                _ = try await ServerMount.mount(server)
                refresh()
            } catch ServerMount.Failure.cancelled {
            } catch {
                Store.log.post(.error, "Couldn't connect to \(server.absoluteString): \(error.localizedDescription)", source: "Servers")
                NSSound.beep()
            }
        }
    }
}

/// One server in the sidebar: found nearby, connected, or both.
struct ServerEntry: Identifiable, Hashable {
    let url: URL
    let name: String
    var id: String { ServerHost.key(url.host(percentEncoded: false) ?? name) }

    /// Servers found nearby, then the servers of mounted shares that weren't found (an IP, a VPN).
    static func all(found: [NetworkServer], mounted: [Volume]) -> [ServerEntry] {
        var list = found.compactMap { server in server.url.map { ServerEntry(url: $0, name: server.name) } }
        for volume in mounted {
            guard let remote = volume.remoteURL, let server = ServerHost.server(of: remote),
                  !list.contains(where: { ServerHost.same($0.url, server) }) else { continue }
            list.append(ServerEntry(url: server, name: ServerHost.displayName(server)))
        }
        return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Mounted servers, servers found nearby, and Connect to Server….
struct NetworkSection: View {
    let browser: BrowserModel
    let volumes: [Volume]
    @Binding var renaming: Volume?
    @AppStorage(Prefs.showConnectedShares, store: Prefs.defaults) private var showShares = false
    private var found: NetworkServers { .shared }

    /// Rows that act instead of going somewhere; the sidebar's selection hands them here.
    static let connectRow = URL(string: "kamiro:connect-to-server")!

    var body: some View {
        Section("Network") {
            ForEach(ServerEntry.all(found: found.servers, mounted: volumes)) { server in
                let shares = volumes.filter { $0.remoteURL.map { ServerHost.same($0, server.url) } ?? false }
                HStack(spacing: Space.xs) {
                    Label { Text(verbatim: server.name) } icon: { Image(systemName: "server.rack") }
                    Spacer(minLength: 0)
                    // Connected: ⏏ disconnects every share of the server.
                    if !shares.isEmpty {
                        Button("Eject", systemImage: "eject") { shares.forEach { ItemActions.eject($0, from: browser) } }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help(String(localized: "Disconnect from “\(server.name)”"))
                    }
                }
                .tag(VirtualPlace.server(server.url).url)
                // Settings › General › Show in Sidebar › Connected Shares lists them under it.
                if showShares {
                    ForEach(shares) { volume in
                        VolumeRow(volume: volume, browser: browser, renaming: $renaming)
                            .padding(.leading, Space.lg)
                    }
                }
            }
            Label("Connect to Server…", systemImage: "plus.circle")
                .tag(Self.connectRow)
        }
        .onAppear { found.start() }
    }

    /// Connect to Server… was clicked: it opens the sheet instead of going somewhere.
    static func act(on url: URL, browser: BrowserModel) -> Bool {
        guard url == connectRow else { return false }
        browser.showConnectToServer()
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
