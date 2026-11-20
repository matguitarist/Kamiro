import CoreServices
import Foundation

/// Calls `changed` when something is added, removed, or renamed in one folder, from FSEvents.
/// Bursts arrive as one call (latency), and changes inside subfolders are ignored.
public final class FolderWatcher {
    private final class Box: Sendable {
        let path: String
        let changed: @Sendable () -> Void
        init(path: String, changed: @escaping @Sendable () -> Void) {
            self.path = path
            self.changed = changed
        }
    }

    private var stream: FSEventStreamRef?
    private let box: Box

    public init(folder: URL, latency: TimeInterval = 0.15, changed: @escaping @Sendable () -> Void) {
        // FSEvents reports real paths: /private/tmp, not /tmp.
        box = Box(path: folder.resolvingSymlinksInPath().canonical.path, changed: changed)
        // The stream keeps the box alive until it's released, so a callback already under way
        // never reaches a freed box after this watcher is gone.
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
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            for index in 0..<count {
                let path = URL(filePath: index < list.count ? list[index] : "").canonical.path
                let flag = flags[index]
                let rescan = flag & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged) != 0
                if path == box.path || rescan {
                    box.changed()
                    return
                }
            }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
        stream = FSEventStreamCreate(nil, callback, &context, [box.path] as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "Kamiro.FolderWatcher"))
            FSEventStreamStart(stream)
        }
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

/// A mounted disk in the sidebar's Locations.
public struct Volume: Hashable, Sendable, Identifiable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let isRoot: Bool
    public let isNetwork: Bool
    public let isEjectable: Bool
}

public enum Volumes {
    public static func mounted() -> [Volume] {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeIsRootFileSystemKey, .volumeIsLocalKey,
                                      .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.volumeIsBrowsable != false else { return nil }
            return Volume(url: url.canonical, name: values.volumeLocalizedName ?? url.lastPathComponent,
                          isRoot: values.volumeIsRootFileSystem ?? false, isNetwork: values.volumeIsLocal == false,
                          isEjectable: values.volumeIsEjectable == true || values.volumeIsRemovable == true)
        }
        .sorted { $0.isRoot != $1.isRoot ? $0.isRoot : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Free and total space, for the Home page's volumes (S-031).
    public static func space(at url: URL) -> (available: Int64, total: Int64)? {
        guard let total = (try? url.resourceValues(forKeys: [.volumeTotalCapacityKey]))?.volumeTotalCapacity,
              let available = availableSpace(at: url) else { return nil }
        return (available, Int64(total))
    }

    /// Free space for the status bar, as the Finder counts it (purgeable space included).
    /// Some external and network volumes report 0 for "important usage": then the plain free space counts.
    public static func availableSpace(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let important = values?.volumeAvailableCapacityForImportantUsage
        let plain = values?.volumeAvailableCapacity.map(Int64.init)
        guard let important, important > 0 else { return plain ?? important }
        return max(important, plain ?? 0)
    }
}
