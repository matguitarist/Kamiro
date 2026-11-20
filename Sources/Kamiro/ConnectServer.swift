import AppKit
import KamiroKit
import NetFS
import SwiftUI

// MARK: - Connect to Server (⌘K, S-037)

/// Mounts a server share with NetFS. macOS asks for the name and password itself, and keeps
/// them in the keychain when people choose to.
enum ServerMount {
    enum Failure: Error, LocalizedError {
        case cancelled, failed(Int32)

        var errorDescription: String? {
            switch self {
            case .cancelled: String(localized: "Connecting was cancelled.")
            case .failed(let code):
                String(localized: "The server can’t be reached, or the share doesn’t exist (error \(Int(code))).")
            }
        }
    }

    /// Mounts `url` under /Volumes and returns where. `asking` false never shows a dialog:
    /// it works with the keychain's password or not at all.
    static func mount(_ url: URL, asking: Bool = true) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let options = NSMutableDictionary()
            options[kNAUIOptionKey] = asking ? kNAUIOptionAllowUI : kNAUIOptionNoUI
            var request: AsyncRequestID?
            let started = NetFSMountURLAsync(url as CFURL, nil, nil, nil, options, nil, &request, .main) { status, _, points in
                let paths = (points as? [String]) ?? []
                if status == 0, let first = paths.first {
                    continuation.resume(returning: URL(filePath: first).canonical)
                } else if status == ECANCELED || status == Int32(userCanceledErr) {
                    continuation.resume(throwing: Failure.cancelled)
                } else {
                    continuation.resume(throwing: Failure.failed(status))
                }
            }
            if started != 0 { continuation.resume(throwing: Failure.failed(started)) }
        }
    }
}

/// The servers connected to lately, in the settings.
enum ServerHistory {
    static var recent: RecentServers {
        get { RecentServers(Prefs.defaults.stringArray(forKey: Prefs.recentServers) ?? []) }
        set { Prefs.defaults.set(newValue.addresses, forKey: Prefs.recentServers) }
    }
}

extension BrowserModel {
    /// Go › Connect to Server… (⌘K).
    func showConnectToServer() { connectShown = true }

    /// Mounts the server, remembers it, and opens it in this window.
    func connect(to url: URL) async throws {
        let mounted = try await ServerMount.mount(url)
        ServerHistory.recent.add(url)
        Store.log.post(.info, "Connected to \(url.absoluteString) at \(mounted.path)", source: "Servers")
        go(to: mounted)
    }
}

/// The Connect to Server sheet: an address, the recent servers, Connect.
struct ConnectServerSheet: View {
    let browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var address = "smb://"
    @State private var recent = ServerHistory.recent
    @State private var connecting = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Connect to Server")
                .font(.headline)
            TextField("Server Address", text: $address, prompt: Text(verbatim: "smb://server/share"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(connect)
                .disabled(connecting)
            // Verbatim: as a text key, Markdown would eat one of the two leading backslashes; a
            // word joiner keeps them on one line.
            Text(verbatim: String(localized: "A name alone connects with SMB; afp://, nfs://, https:// (WebDAV) and \\\\server\\share work too.")
                .replacingOccurrences(of: "\\\\", with: "\\\u{2060}\\"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !recent.addresses.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Recent Servers")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    List(recent.addresses, id: \.self, selection: selectedRecent) { entry in
                        Label(entry, systemImage: "network")
                            .contextMenu {
                                Button("Remove from Recent Servers", systemImage: "minus.circle") {
                                    recent.remove(entry)
                                    ServerHistory.recent = recent
                                }
                            }
                    }
                    .listStyle(.bordered)
                    .frame(height: 120)
                }
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Space.sm) {
                if connecting {
                    ProgressView().controlSize(.small)
                    Text("Connecting…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Connect", action: connect)
                    .keyboardShortcut(.defaultAction)
                    .disabled(connecting || ServerAddress.parse(address) == nil)
            }
        }
        .padding(Space.xl)
        .frame(width: 440)
    }

    /// Picking a recent server puts it in the field; Return connects.
    private var selectedRecent: Binding<String?> {
        Binding { recent.addresses.first { $0 == address } } set: { if let entry = $0 { address = entry } }
    }

    private func connect() {
        guard !connecting, let url = ServerAddress.parse(address) else { return }
        connecting = true
        problem = nil
        Task {
            do {
                try await browser.connect(to: url)
                dismiss()
            } catch ServerMount.Failure.cancelled {
                connecting = false
            } catch {
                Store.log.post(.error, "Couldn't connect to \(url.absoluteString): \(error.localizedDescription)", source: "Servers")
                problem = error.localizedDescription
                connecting = false
            }
        }
    }
}
