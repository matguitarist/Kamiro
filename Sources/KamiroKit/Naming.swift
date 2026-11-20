import Foundation

/// New names for copies, kept-both items and new items, the Finder's way.
public enum Naming {
    /// "report.pdf" → "report copy.pdf", then "report copy 2.pdf". `word` is the localized "copy".
    public static func copy(of name: String, isFolder: Bool = false, word: String = "copy", in folder: URL,
                            taken: (String) -> Bool = { _ in false }) -> String {
        let (stem, ext) = split(name, isFolder: isFolder)
        return first(stem: "\(stem) \(word)", ext: ext, startAt: 1, in: folder, taken: taken)
    }

    /// "report.pdf" → "report 2.pdf", then "report 3.pdf" (Keep Both).
    public static func numbered(_ name: String, isFolder: Bool = false, in folder: URL,
                                taken: (String) -> Bool = { _ in false }) -> String {
        let (stem, ext) = split(name, isFolder: isFolder)
        return first(stem: stem, ext: ext, startAt: 2, in: folder, taken: taken)
    }

    /// The name itself when it's free, else "name 2", "name 3"… (the Trash, Keep Both on a free name).
    public static func free(_ name: String, isFolder: Bool = false, in folder: URL) -> String {
        let (stem, ext) = split(name, isFolder: isFolder)
        return first(stem: stem, ext: ext, startAt: 1, in: folder, taken: { _ in false })
    }

    /// "untitled folder", then "untitled folder 2"; with an extension, "untitled.txt", "untitled 2.txt".
    public static func untitled(_ base: String, ext: String = "", in folder: URL,
                                taken: (String) -> Bool = { _ in false }) -> String {
        first(stem: base, ext: ext, startAt: 1, in: folder, taken: taken)
    }

    /// The name and its extension. Folders have no extension; packages (.app) do.
    public static func split(_ name: String, isFolder: Bool = false) -> (stem: String, ext: String) {
        guard !isFolder, let dot = name.lastIndex(of: "."), dot != name.startIndex,
              name.index(after: dot) != name.endIndex else { return (name, "") }
        return (String(name[..<dot]), String(name[name.index(after: dot)...]))
    }

    /// The first free name: "stem.ext" (when startAt is 1), then "stem 2.ext", "stem 3.ext"…
    private static func first(stem: String, ext: String, startAt: Int, in folder: URL, taken: (String) -> Bool) -> String {
        var number = startAt
        while true {
            let base = number == 1 ? stem : "\(stem) \(number)"
            let name = ext.isEmpty ? base : "\(base).\(ext)"
            if !taken(name), !FileManager.default.fileExists(atPath: folder.appending(path: name).path) { return name }
            number += 1
        }
    }
}

/// Why a new name can't be used.
public enum NameProblem: Error, Equatable, Sendable {
    case empty, colon, tooLong
    /// Another item in the folder has this name.
    case taken
}

public enum NameCheck {
    /// Checks a new name for `url`. nil when it can be used (or didn't change).
    public static func problem(renaming url: URL, to newName: String) -> NameProblem? {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .empty }
        if name.contains(":") { return .colon }
        if name.utf8.count > 255 { return .tooLong }
        if name == url.lastPathComponent { return nil }
        let target = url.deletingLastPathComponent().appending(path: name)
        // A change of case only ("notes" → "Notes") is the same file on most Mac disks.
        let caseOnly = name.lowercased() == url.lastPathComponent.lowercased()
        if !caseOnly, FileManager.default.fileExists(atPath: target.path) { return .taken }
        return nil
    }

    /// The old and new extensions when a rename changes a file's extension, which asks first.
    public static func extensionChange(from oldName: String, to newName: String, isFolder: Bool) -> (old: String, new: String)? {
        guard !isFolder else { return nil }
        let old = Naming.split(oldName).ext
        let new = Naming.split(newName).ext
        return old.lowercased() == new.lowercased() ? nil : (old, new)
    }
}

/// The New File menu: four groups, like PowerClick (docs/research/context-menu.md).
public struct FileTemplate: Identifiable, Sendable, Hashable {
    public enum Group: String, CaseIterable, Sendable { case basic, data, web, code }

    public let id: String
    public let group: Group
    /// Without the dot; empty for Empty File.
    public let ext: String
    public let contents: String
    public let executable: Bool

    public static let all: [FileTemplate] = [
        FileTemplate(id: "empty", group: .basic, ext: "", contents: "", executable: false),
        FileTemplate(id: "text", group: .basic, ext: "txt", contents: "", executable: false),
        FileTemplate(id: "rtf", group: .basic, ext: "rtf",
                     contents: "{\\rtf1\\ansi\\ansicpg1252\\cocoartf2822\n{\\fonttbl\\f0\\fswiss Helvetica;}\n\\f0\\fs26 \n}\n",
                     executable: false),
        FileTemplate(id: "markdown", group: .basic, ext: "md", contents: "# Untitled\n", executable: false),
        FileTemplate(id: "json", group: .data, ext: "json", contents: "{\n}\n", executable: false),
        FileTemplate(id: "xml", group: .data, ext: "xml", contents: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root/>\n", executable: false),
        FileTemplate(id: "yaml", group: .data, ext: "yaml", contents: "# YAML\n", executable: false),
        FileTemplate(id: "csv", group: .data, ext: "csv", contents: "name,value\n", executable: false),
        FileTemplate(id: "html", group: .web, ext: "html", contents: """
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <title>Untitled</title>
            </head>
            <body>
            </body>
            </html>

            """, executable: false),
        FileTemplate(id: "css", group: .web, ext: "css", contents: "", executable: false),
        FileTemplate(id: "javascript", group: .web, ext: "js", contents: "", executable: false),
        FileTemplate(id: "typescript", group: .web, ext: "ts", contents: "export {};\n", executable: false),
        FileTemplate(id: "python", group: .code, ext: "py", contents: "#!/usr/bin/env python3\n\n", executable: true),
        FileTemplate(id: "shell", group: .code, ext: "sh", contents: "#!/bin/zsh\n\n", executable: true),
        FileTemplate(id: "swift", group: .code, ext: "swift", contents: "import Foundation\n\n", executable: false),
    ]

    /// Writes "untitled.<ext>" (or the next free name) in `folder`; scripts are made executable.
    public func make(in folder: URL, base: String) throws -> URL {
        let url = folder.appending(path: Naming.untitled(base, ext: ext, in: folder)).canonical
        try Data(contents.utf8).write(to: url, options: .withoutOverwriting)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return url
    }
}
