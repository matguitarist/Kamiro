import Foundation

/// What the Copy Info submenu puts on the pasteboard (S-034), one line per item.
public enum CopyInfo: CaseIterable, Sendable {
    case name, nameWithoutExtension, fileExtension, parentPath

    /// The text for `urls`, one line each; items with no extension are skipped for the
    /// extension-only choices.
    public func text(for urls: [URL]) -> String {
        urls.compactMap(line).joined(separator: "\n")
    }

    /// Whether the choice says something for `urls`: the extension ones need an item with one.
    public func applies(to urls: [URL]) -> Bool {
        switch self {
        case .name, .parentPath: !urls.isEmpty
        case .nameWithoutExtension, .fileExtension: urls.contains { !$0.pathExtension.isEmpty }
        }
    }

    private func line(_ url: URL) -> String? {
        switch self {
        case .name: url.lastPathComponent
        case .nameWithoutExtension: url.pathExtension.isEmpty ? nil : url.deletingPathExtension().lastPathComponent
        case .fileExtension: url.pathExtension.isEmpty ? nil : url.pathExtension
        case .parentPath: url.deletingLastPathComponent().canonical.path
        }
    }
}
