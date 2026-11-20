import Foundation

/// The icons people pick for a server or disk in the sidebar (S-056).
public enum PlaceIcon: String, CaseIterable, Sendable, Identifiable {
    case network, server, nas, pc, mac, laptop, cloud, internalDrive, externalDrive

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .network: "network"
        case .server: "server.rack"
        case .nas: "externaldrive.connected.to.line.below"
        case .pc: "pc"
        case .mac: "desktopcomputer"
        case .laptop: "laptopcomputer"
        case .cloud: "cloud"
        case .internalDrive: "internaldrive"
        case .externalDrive: "externaldrive"
        }
    }

    /// What a disk shows until someone picks: a cloud for WebDAV and for cloud storage mounted
    /// by a tool (rclone, Mountain Duck and the like run on macFUSE, FUSE-T or a local NFS server).
    public static func automatic(for volume: Volume) -> PlaceIcon {
        if isCloud(volume) { return .cloud }
        if volume.isNetwork { return .network }
        return volume.isRoot ? .internalDrive : .externalDrive
    }

    public static func isCloud(_ volume: Volume) -> Bool {
        if let fileSystem = volume.fileSystem?.lowercased(), ["fuse", "rclone"].contains(where: fileSystem.contains) {
            return true
        }
        guard let remote = volume.remoteURL, let scheme = remote.scheme?.lowercased() else { return false }
        if ["http", "https", "webdav", "webdavs"].contains(scheme) { return true }
        // rclone nfsmount serves the cloud from this Mac.
        let host = remote.host(percentEncoded: false)?.lowercased() ?? ""
        return scheme == "nfs" && ["localhost", "127.0.0.1", "::1"].contains(host)
    }
}

extension Volume {
    /// Cloud storage mounted as a disk (WebDAV, rclone and the like).
    public var isCloud: Bool { PlaceIcon.isCloud(self) }
}

/// The icons people picked, by server or disk; the rest keep their automatic icon.
public struct PlaceIcons: Equatable, Sendable {
    public private(set) var chosen: [String: PlaceIcon]

    public init(saved: [String: String] = [:]) {
        chosen = saved.compactMapValues(PlaceIcon.init(rawValue:))
    }

    /// What is saved: the key and the icon's name.
    public var saved: [String: String] { chosen.mapValues(\.rawValue) }

    public func icon(for key: String) -> PlaceIcon? { chosen[key] }

    /// Picks an icon; nil goes back to the automatic one.
    public mutating func set(_ icon: PlaceIcon?, for key: String) {
        chosen[key] = icon
    }

    /// A server under any spelling (Bonjour name, .local, bare name) is one server.
    public static func key(server: URL) -> String {
        "server:" + ServerHost.key(server.host(percentEncoded: false) ?? server.absoluteString)
    }

    /// A share by its server and name, so it keeps its icon when it mounts again elsewhere;
    /// a disk by its UUID, or its path when it has none.
    public static func key(volume: Volume) -> String {
        if let remote = volume.remoteURL {
            let host = ServerHost.key(remote.host(percentEncoded: false) ?? "")
            return "share:\(remote.scheme?.lowercased() ?? "")://\(host)/\(ServerHost.share(of: remote)?.lowercased() ?? "")"
        }
        return "disk:" + (volume.uuid ?? volume.url.path)
    }
}
