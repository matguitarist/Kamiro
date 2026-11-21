import Foundation

/// What Kamiro does with an item another app sends it: through "Show in Finder" once Kamiro shows
/// files (S-038), or the kamiro command (S-039). A folder opens in a window; a file, an app or
/// another package shows selected in its folder. A reveal shows even a folder in its parent.
public struct OpenRequest: Equatable, Sendable {
    public var folder: URL
    public var select: URL?

    public init(folder: URL, select: URL? = nil) {
        self.folder = folder
        self.select = select
    }

    /// Nil for an item that isn't there, or isn't a file.
    public init?(_ url: URL, reveal: Bool = false) {
        guard url.isFileURL else { return nil }
        let url = url.canonical
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return nil }
        let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
        if url.path == "/" || (isFolder.boolValue && !isPackage && !reveal) {
            self.init(folder: url)
        } else {
            self.init(folder: url.deletingLastPathComponent().canonical, select: url)
        }
    }
}

/// The kamiro command (S-039): a small zsh script that hands its paths to Kamiro with open(1).
/// Kamiro writes it itself, so it always names this app, and only removes a kamiro it wrote.
public enum CommandLineTool {
    public static let name = "kamiro"
    /// On every Mac's PATH (/etc/paths), and the place command-line tools from apps go.
    public static let standardFolder = URL(filePath: "/usr/local/bin")
    static let marker = "# Installed by Kamiro"

    public enum Status: Equatable, Sendable {
        /// No kamiro there.
        case missing
        /// This version of the script.
        case installed
        /// One Kamiro wrote, from another version or for another copy of the app.
        case outdated
        /// Something else called kamiro: left alone.
        case foreign
    }

    public static func script(bundleID: String) -> String {
        """
        #!/bin/zsh
        \(marker) (Settings › General › Command Line). Opens each folder in Kamiro
        # and shows each file selected in its folder; with no path, the current folder.
        if [[ $1 == -h || $1 == --help ]]; then
          print "usage: kamiro [path ...]"
          print "Opens each folder in Kamiro and shows each file selected in its folder."
          print "With no path, opens the current folder."
          exit 0
        fi
        (( $# )) || set -- .
        paths=()
        result=0
        for item in "$@"; do
          if [[ -e $item ]]; then
            paths+=("${item:a}")
          else
            print -u2 "kamiro: $item: no such file or folder"
            result=1
          fi
        done
        (( $#paths )) && { open -b \(bundleID) "${paths[@]}" || result=1 }
        exit $result

        """
    }

    public static func status(in folder: URL, bundleID: String) -> Status {
        let file = folder.appending(path: name)
        guard let data = FileManager.default.contents(atPath: file.path) else {
            // A broken link still blocks the name.
            let link = try? FileManager.default.destinationOfSymbolicLink(atPath: file.path)
            return link == nil ? .missing : .foreign
        }
        let text = String(decoding: data, as: UTF8.self)
        if text == script(bundleID: bundleID) { return .installed }
        return text.contains(marker) ? .outdated : .foreign
    }
}
