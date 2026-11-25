import CoreServices
import FileKit
import Foundation

/// A folder's size as the disk counts it (S-023), from FileKit: allocated size, hard links
/// counted once, hidden files included, other apps' data left out. Stops as soon as its task is
/// cancelled.
public enum FolderSize {
    /// Other apps' data: reading it asks people for permission, so it's left out.
    static let skipped: Set<String> = Set(FileKit.FolderSize.otherAppsData.map(\.canonical.path))

    /// Throws FolderError.denied when the folder itself can't be read: its size isn't known,
    /// which is not the same as zero.
    public static func measure(_ folder: URL) throws -> Int64 {
        try summary(folder).bytes
    }

    /// Size on disk and how many items are inside, at every depth, hidden ones included (Properties).
    public static func summary(_ folder: URL) throws -> (bytes: Int64, items: Int) {
        do {
            let found = try FileKit.FolderSize.summary(of: folder, options: .init(skipping: FileKit.FolderSize.otherAppsData))
            return (found.allocated, found.items)
        } catch FileKit.FolderSize.Failure.unreadable {
            throw FolderError.denied
        }
    }

    /// How long to wait before measuring a folder again after a change inside it: ten times what
    /// the last measure took, at least 2 s. A folder that changes all the time and takes minutes to
    /// walk (~/Library) is measured now and then instead of without end.
    public static func recheckDelay(after took: Duration) -> Duration {
        max(.seconds(2), took * 10)
    }
}

/// Calls `changed` with the paths that changed anywhere under a folder, from FSEvents,
/// so folder sizes stay up to date.
public final class TreeWatcher {
    private final class Box: Sendable {
        let changed: @Sendable ([String]) -> Void
        init(changed: @escaping @Sendable ([String]) -> Void) { self.changed = changed }
    }

    private var stream: FSEventStreamRef?
    private let box: Box
    /// The real path FSEvents reports: /private/tmp, not /tmp.
    public let root: String

    public init(folder: URL, latency: TimeInterval = 0.5, changed: @escaping @Sendable ([String]) -> Void) {
        root = folder.resolvingSymlinksInPath().canonical.path
        box = Box(changed: changed)
        // The stream keeps the box alive until it's released (see FolderWatcher).
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(box).toOpaque(),
                                           retain: { info in
                                               guard let info else { return nil }
                                               _ = Unmanaged<Box>.fromOpaque(info).retain()
                                               return info
                                           },
                                           release: { info in
                                               guard let info else { return }
                                               Unmanaged<Box>.fromOpaque(info).release()
                                           }, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
            box.changed(unsafeBitCast(paths, to: NSArray.self) as? [String] ?? [])
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        stream = FSEventStreamCreate(nil, callback, &context, [root] as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "Kamiro.TreeWatcher"))
            FSEventStreamStart(stream)
        }
    }

    /// The item directly inside the watched folder that holds `path`, by name.
    public func child(holding path: String) -> String? {
        let clean = URL(filePath: path).canonical.path
        guard clean.hasPrefix(root + "/") else { return nil }
        return clean.dropFirst(root.count + 1).split(separator: "/").first.map(String.init)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
