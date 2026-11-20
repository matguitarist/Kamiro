import Foundation
import UniformTypeIdentifiers

/// The kinds a default app is set for (S-036): one per distinct content type in the selection.
public enum DefaultApps {
    public static func types(of urls: [URL]) -> [UTType] {
        var seen = Set<UTType>()
        return urls.compactMap { url in
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
                ?? UTType(filenameExtension: url.pathExtension)
            guard let type, type != .folder, type != .directory, seen.insert(type).inserted else { return nil }
            return type
        }
    }
}
