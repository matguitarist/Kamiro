import AppKit

/// Files on the pasteboard as file URLs, so the Finder and other apps can paste them.
public enum FilePasteboard {
    public static func write(_ urls: [URL], to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
    }

    public static func read(from pasteboard: NSPasteboard = .general) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return (urls ?? []).map(\.canonical)
    }

    public static func hasFiles(_ pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }
}
