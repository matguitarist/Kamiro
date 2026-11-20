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
    /// The disk lets its name change (APFS, HFS+, most USB formats; not a DMG's read-only image).
    public let canRename: Bool
    /// A server share's address (smb://HomeServer._smb._tcp.local/isos), nil for a disk.
    public let remoteURL: URL?
    /// The file system's short name (apfs, smbfs, webdav, macfuse…), for its automatic icon.
    public let fileSystem: String?
    public let uuid: String?

    public init(url: URL, name: String, isRoot: Bool = false, isNetwork: Bool = false,
                isEjectable: Bool = false, canRename: Bool = false, remoteURL: URL? = nil,
                fileSystem: String? = nil, uuid: String? = nil) {
        self.remoteURL = remoteURL
        self.fileSystem = fileSystem
        self.uuid = uuid
        self.url = url
        self.name = name
        self.isRoot = isRoot
        self.isNetwork = isNetwork
        self.isEjectable = isEjectable
        self.canRename = canRename
    }

    /// What its right-click menu offers (S-033), in order; nil is a separator.
    /// The startup disk can't be ejected; a disk that can't take a new name has no Rename.
    public var actions: [VolumeAction?] {
        var list: [VolumeAction?] = [.open, .openInNewTab, .openInTerminal, nil]
        if canRename { list.append(.rename) }
        list += [.copyPath, .properties]
        if (isEjectable || isNetwork), !isRoot { list += [nil, .eject] }
        return list
    }
}

/// One line of a disk's right-click menu on the Home page and in the sidebar.
public enum VolumeAction: String, Sendable, CaseIterable {
    case open, openInNewTab, openInTerminal, rename, copyPath, properties, eject
}

/// A disk's facts for Properties (S-033): its format and space.
public struct VolumeFacts: Sendable, Equatable {
    public let name: String
    public let format: String?
    public let capacity: Int64?
    public let available: Int64?
    public let isReadOnly: Bool

    public var used: Int64? {
        guard let capacity, let available else { return nil }
        return max(0, capacity - available)
    }
}

public enum Volumes {
    public static func mounted() -> [Volume] {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeIsRootFileSystemKey, .volumeIsLocalKey,
                                      .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsBrowsableKey,
                                      .volumeSupportsRenamingKey, .volumeIsReadOnlyKey, .volumeURLForRemountingKey,
                                      .volumeTypeNameKey, .volumeUUIDStringKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.volumeIsBrowsable != false else { return nil }
            return Volume(url: url.canonical, name: values.volumeLocalizedName ?? url.lastPathComponent,
                          isRoot: values.volumeIsRootFileSystem ?? false, isNetwork: values.volumeIsLocal == false,
                          isEjectable: values.volumeIsEjectable == true || values.volumeIsRemovable == true,
                          canRename: values.volumeSupportsRenaming == true && values.volumeIsReadOnly != true,
                          remoteURL: values.volumeIsLocal == false ? values.volumeURLForRemounting : nil,
                          fileSystem: values.volumeTypeName, uuid: values.volumeUUIDString)
        }
        .sorted { $0.isRoot != $1.isRoot ? $0.isRoot : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The mounted disk whose top folder is `url`, or nil for any other folder.
    public static func volume(at url: URL) -> Volume? {
        let url = url.canonical
        return mounted().first { $0.url == url }
    }

    /// Whether `url` is the top folder of a disk ("/", "/Volumes/Backup").
    public static func isVolumeRoot(_ url: URL) -> Bool {
        guard url.isFileURL, let root = (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume else { return false }
        return root.canonical == url.canonical
    }

    public static func facts(at url: URL) -> VolumeFacts? {
        let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeLocalizedFormatDescriptionKey,
                                         .volumeTotalCapacityKey, .volumeIsReadOnlyKey]
        guard isVolumeRoot(url), let values = try? url.resourceValues(forKeys: keys) else { return nil }
        return VolumeFacts(name: values.volumeLocalizedName ?? url.lastPathComponent,
                           format: values.volumeLocalizedFormatDescription,
                           capacity: values.volumeTotalCapacity.map(Int64.init),
                           available: availableSpace(at: url),
                           isReadOnly: values.volumeIsReadOnly ?? false)
    }

    /// Why a disk can't take this name, or nil. Disk names follow file names' rules.
    public static func problem(naming newName: String) -> NameProblem? {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .empty }
        if name.contains(":") { return .colon }
        if name.utf8.count > 255 { return .tooLong }
        return nil
    }

    /// Gives a disk a new name; its folder in /Volumes follows a moment later.
    public static func rename(_ url: URL, to newName: String) throws {
        if let problem = problem(naming: newName) { throw problem }
        var target = url
        var values = URLResourceValues()
        values.volumeName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        try target.setResourceValues(values)
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
