import Foundation

/// The toolbar filter (S-028): an item matches when its name holds every word typed, ignoring
/// case and accents, in any order. "inv 2" finds "Invoice 2.pdf" and "Invoice 12.pdf".
public enum NameFilter {
    public static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    public static func matches(_ name: String, _ text: String) -> Bool {
        words(text).allSatisfy { name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    public static func apply(_ items: [FileItem], _ text: String) -> [FileItem] {
        guard !words(text).isEmpty else { return items }
        return items.filter { matches($0.name, text) }
    }
}
