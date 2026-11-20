import Foundation

/// Who can do what with an item, as Properties shows it (S-026).
public struct Permissions: Equatable, Sendable {
    public enum Access: Equatable, Sendable {
        case readWrite, readOnly, writeOnly, none

        init(bits: Int) {
            switch (bits & 4 != 0, bits & 2 != 0) {
            case (true, true): self = .readWrite
            case (true, false): self = .readOnly
            case (false, true): self = .writeOnly
            case (false, false): self = .none
            }
        }
    }

    public let owner: String
    public let group: String
    public let ownerAccess: Access
    public let groupAccess: Access
    public let everyoneAccess: Access

    public init(mode: Int, owner: String, group: String) {
        self.owner = owner
        self.group = group
        ownerAccess = Access(bits: mode >> 6 & 7)
        groupAccess = Access(bits: mode >> 3 & 7)
        everyoneAccess = Access(bits: mode & 7)
    }

    public static func of(_ url: URL) -> Permissions? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue else { return nil }
        return Permissions(mode: mode, owner: attributes[.ownerAccountName] as? String ?? "?",
                           group: attributes[.groupOwnerAccountName] as? String ?? "?")
    }
}

/// The Options switches in Properties.
public enum ItemFlags {
    public static func isLocked(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isUserImmutableKey]))?.isUserImmutable == true
    }

    public static func isHidden(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isHiddenKey]))?.isHidden == true
    }

    public static func setLocked(_ locked: Bool, _ url: URL) throws {
        var values = URLResourceValues()
        values.isUserImmutable = locked
        var target = url
        try target.setResourceValues(values)
    }

    public static func setHidden(_ hidden: Bool, _ url: URL) throws {
        var values = URLResourceValues()
        values.isHidden = hidden
        var target = url
        try target.setResourceValues(values)
    }
}
