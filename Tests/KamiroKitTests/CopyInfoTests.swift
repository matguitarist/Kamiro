import Foundation
import Testing
@testable import KamiroKit

@Test func copyInfoGivesOneLinePerItem() {
    let urls = [URL(filePath: "/Users/me/Docs/Guide.pdf"), URL(filePath: "/Users/me/Docs/archive.tar.gz"),
                URL(filePath: "/Users/me/Projects")]
    #expect(CopyInfo.name.text(for: urls) == "Guide.pdf\narchive.tar.gz\nProjects")
    #expect(CopyInfo.nameWithoutExtension.text(for: urls) == "Guide\narchive.tar")
    #expect(CopyInfo.fileExtension.text(for: urls) == "pdf\ngz")
    #expect(CopyInfo.parentPath.text(for: urls) == "/Users/me/Docs\n/Users/me/Docs\n/Users/me")
}

@Test func extensionChoicesNeedAnExtension() {
    let folder = [URL(filePath: "/Users/me/Projects")]
    #expect(!CopyInfo.fileExtension.applies(to: folder))
    #expect(!CopyInfo.nameWithoutExtension.applies(to: folder))
    #expect(CopyInfo.name.applies(to: folder) && CopyInfo.parentPath.applies(to: folder))
    #expect(!CopyInfo.name.applies(to: []))
}

@Test func editorIsTheChosenOneOrTheFirstInstalled() {
    let zed = EditorApp.known.first { $0.name == "Zed" }!
    let xcode = EditorApp.known.first { $0.name == "Xcode" }!
    let installed = EditorApp.installed { [zed.bundleID, xcode.bundleID].contains($0) }
    #expect(installed == [zed, xcode])
    #expect(EditorApp.chosen(xcode.bundleID, installed: installed) == xcode)
    #expect(EditorApp.chosen("com.microsoft.VSCode", installed: installed) == zed)
    #expect(EditorApp.chosen(nil, installed: []) == nil)
    let codium = EditorApp.known.first { $0.bundleID == "com.vscodium" }
    #expect(codium?.name == "VSCodium" && EditorApp.installed { $0 == "com.vscodium" } == [codium!])
    #expect(Set(EditorApp.known.map(\.bundleID)).count == EditorApp.known.count)
}

@Test func editorsOpenFoldersAndTextOnly() {
    #expect(EditorApp.opens(URL(filePath: "/p"), isFolder: true))
    for name in ["main.swift", "notes.md", "data.json", "readme.txt", "Info.plist", "Makefile", "page.html"] {
        #expect(EditorApp.opens(URL(filePath: "/p/\(name)"), isFolder: false), "\(name)")
    }
    for name in ["photo.jpg", "Guide.pdf", "song.m4a", "archive.zip",
                 "App.xcodeproj", "App.xcworkspace", "project.godot", "Main.tscn", "Level.unity", "Game.sln",
                 "Game.csproj", "Game.uproject"] {
        #expect(!EditorApp.opens(URL(filePath: "/p/\(name)"), isFolder: false), "\(name)")
    }
}
