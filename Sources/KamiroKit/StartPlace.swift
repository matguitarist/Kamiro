import Foundation

/// Where new windows and tabs open (Settings › General, S-040): the Home page, a folder of the
/// home folder, or one the person chose. A folder that's gone opens Home instead.
public enum StartPlace: Hashable, Sendable {
    case home, homeFolder, desktop, documents, downloads
    case folder(URL)

    public static let standard: [StartPlace] = [.home, .homeFolder, .desktop, .documents, .downloads]

    /// As kept in the preferences: a name, or a folder's path.
    public init(stored: String?) {
        switch stored {
        case "homeFolder": self = .homeFolder
        case "desktop": self = .desktop
        case "documents": self = .documents
        case "downloads": self = .downloads
        case let path? where path.hasPrefix("/"): self = .folder(URL(filePath: path))
        default: self = .home
        }
    }

    public var stored: String {
        switch self {
        case .home: "home"
        case .homeFolder: "homeFolder"
        case .desktop: "desktop"
        case .documents: "documents"
        case .downloads: "downloads"
        case .folder(let url): url.path
        }
    }

    /// The folder it names in `home`; nil for the Home page.
    public func folder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        switch self {
        case .home: nil
        case .homeFolder: home
        case .desktop: home.appending(path: "Desktop")
        case .documents: home.appending(path: "Documents")
        case .downloads: home.appending(path: "Downloads")
        case .folder(let url): url
        }
    }

    /// What a new window opens on: the folder when it's there, else the Home page.
    public func url(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        var isFolder: ObjCBool = false
        guard let folder = folder(home: home), FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder),
              isFolder.boolValue else { return VirtualPlace.home.url }
        return folder
    }
}
