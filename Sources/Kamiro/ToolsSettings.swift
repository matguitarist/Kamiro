import AppKit
import KamiroKit
import SwiftUI

/// The optional command-line tools found on this Mac (S-049). Looked for at launch and each
/// time Settings › Tools opens. Test runs look in an empty folder in /tmp, as if none were there.
@MainActor @Observable
final class ToolStore {
    static let shared = ToolStore()

    private(set) var installed: [String: InstalledTool] = [:]
    private(set) var isChecking = false

    var folders: [URL] {
        Store.isOverridden ? [URL(filePath: "/tmp/Kamiro-tools")] : ToolFinder.standardFolders
    }

    /// The ids of the tools found, for what Convert offers.
    var installedIDs: Set<String> { Set(installed.keys) }

    func refresh() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        installed = await ToolFinder.findAll(in: folders)
    }

    /// Test runs copy to their own pasteboard.
    let pasteboard: NSPasteboard = Store.isOverridden
        ? NSPasteboard(name: NSPasteboard.Name("com.mathieuares.kamiro.test")) : .general

    func copy(_ line: String) {
        pasteboard.clearContents()
        pasteboard.setString(line, forType: .string)
    }
}

extension CommandTool {
    /// What the tool adds to Kamiro.
    var purpose: String {
        switch command {
        case "cwebp": String(localized: "Converts pictures to WebP.")
        case "ffmpeg": String(localized: "Converts WebM, MKV, AVI and other videos macOS can't open.")
        default: String(localized: "Converts SVG, EPS and other pictures macOS can't open.")
        }
    }
}

/// Settings › Tools: each tool, installed with its version, or the Homebrew line to copy.
struct ToolsSettings: View {
    @State private var store = ToolStore.shared

    var body: some View {
        Section {
            ForEach(CommandTool.all) { tool in
                LabeledContent {
                    if let found = store.installed[tool.id] {
                        Label(found.version, systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.secondary)
                            .help(found.url.path)
                    } else {
                        Button("Copy") { store.copy(tool.brewLine) }
                            .help(String(localized: "Copy the line to paste in Terminal"))
                    }
                } label: {
                    Text(verbatim: tool.name)
                    Text(tool.purpose)
                    if store.installed[tool.id] == nil {
                        Text(verbatim: tool.brewLine)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        } header: {
            Text("Command-Line Tools")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Optional. Kamiro does everything else with macOS itself, and never downloads a tool: install one with Homebrew, then check again.")
                    .foregroundStyle(.secondary)
                Link("About Homebrew", destination: URL(string: "https://brew.sh")!)
            }
            .font(.callout)
        }
        Section {
            HStack {
                Spacer()
                if store.isChecking { ProgressView().controlSize(.small) }
                Button("Check Again") { Task { await store.refresh() } }
                    .disabled(store.isChecking)
            }
        }
        .task { await store.refresh() }
    }
}
