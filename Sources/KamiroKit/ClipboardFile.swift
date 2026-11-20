import AppKit

/// New File from Clipboard (S-044): the clipboard as a file whose type follows what it holds,
/// like PowerClick (docs/research/context-menu.md). Files on the clipboard are Paste's, not this.
public enum ClipboardFile: Equatable, Sendable {
    case text(String)
    case json(String)
    /// Already turned into CSV.
    case table(String)
    case link(URL)
    /// PNG data.
    case image(Data)

    public var ext: String {
        switch self {
        case .text: "txt"
        case .json: "json"
        case .table: "csv"
        case .link: "webloc"
        case .image: "png"
        }
    }

    public var data: Data {
        switch self {
        case .text(let s), .json(let s), .table(let s): Data(s.utf8)
        case .link(let url):
            (try? PropertyListSerialization.data(fromPropertyList: ["URL": url.absoluteString], format: .xml, options: 0)) ?? Data()
        case .image(let png): png
        }
    }

    private static let tabbed = NSPasteboard.PasteboardType("public.utf8-tab-separated-values-text")
    private static let images: [NSPasteboard.PasteboardType] = [.png, .tiff]

    /// Whether the clipboard holds something to make a file from; looks at types only, so it's cheap.
    public static func available(in pasteboard: NSPasteboard) -> Bool {
        guard !FilePasteboard.hasFiles(pasteboard), let types = pasteboard.types else { return false }
        return types.contains { [.string, .URL, tabbed, .png, .tiff].contains($0) }
    }

    /// What the clipboard would make, or nil when it is empty or holds files.
    /// A table copied from Numbers or Excel also carries a picture of itself: the table wins.
    public static func read(from pasteboard: NSPasteboard) -> ClipboardFile? {
        guard available(in: pasteboard) else { return nil }
        if let tsv = pasteboard.string(forType: tabbed), !tsv.isEmpty { return .table(csv(fromTabbed: tsv)) }
        if pasteboard.availableType(from: images) != nil,
           let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            if pasteboard.types?.contains(.png) == true { return .image(data) }
            if let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) { return .image(png) }
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty { return classify(text) }
        if let string = pasteboard.string(forType: .URL), let url = URL(string: string), !url.isFileURL { return .link(url) }
        return nil
    }

    /// Plain text: one web link, JSON, a tab-separated table, or text.
    public static func classify(_ text: String) -> ClipboardFile {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host() != nil {
            return .link(url)
        }
        if let first = trimmed.first, first == "{" || first == "[",
           (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil {
            return .json(text)
        }
        let lines = trimmed.split(whereSeparator: \.isNewline).filter { !$0.isEmpty }
        let tabs = Set(lines.map { $0.filter { $0 == "\t" }.count })
        if lines.count >= 2, tabs.count == 1, let count = tabs.first, count > 0 { return .table(csv(fromTabbed: trimmed)) }
        return .text(text)
    }

    /// Tab-separated rows as CSV: fields with a comma, quote or line break are quoted.
    public static func csv(fromTabbed tsv: String) -> String {
        tsv.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { line in
                line.split(separator: "\t", omittingEmptySubsequences: false).map { field in
                    let f = String(field)
                    return f.contains(where: { ",\"\n\r".contains($0) }) ? "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : f
                }.joined(separator: ",")
            }
            .joined(separator: "\n")
    }

    /// Writes "untitled.<ext>" (or the next free name) in `folder`.
    public func make(in folder: URL, base: String) throws -> URL {
        let url = folder.appending(path: Naming.untitled(base, ext: ext, in: folder)).canonical
        try data.write(to: url, options: .withoutOverwriting)
        return url
    }
}
