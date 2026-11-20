import Foundation
import Testing
@testable import KamiroKit

@Test func thumbnailsComeInThreeSizeSteps() {
    #expect(IconSize.thumbnailStep(32) == 64)
    #expect(IconSize.thumbnailStep(64) == 64)
    #expect(IconSize.thumbnailStep(65) == 128)
    #expect(IconSize.thumbnailStep(256) == 256)
}

private func scratchFile() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "KamiroViews-\(UUID().uuidString).json")
}

@Test func columnsAndSortPersistPerFolderWithADefaultForNewFolders() {
    let file = scratchFile()
    defer { try? FileManager.default.removeItem(at: file) }
    let photos = URL(filePath: "/tmp/a/Photos")
    let other = URL(filePath: "/tmp/a/Other")
    let store = ViewStore(url: file)
    var view = store.view(for: photos)
    #expect(view == FolderView())
    view.toggle(.created)
    view.toggle(.kind)
    view.order = ItemOrder(key: .size, ascending: false)
    view.mode = .icons
    view.widths[.name] = 400
    store.remember(view, for: photos)

    let again = ViewStore(url: file)
    #expect(again.view(for: photos).columns == [.name, .modified, .size, .created])
    #expect(again.view(for: photos).order == ItemOrder(key: .size, ascending: false))
    #expect(again.view(for: photos).mode == .icons)
    #expect(again.view(for: photos).widths[.name] == 400)
    #expect(again.view(for: URL(filePath: "/tmp/a/Photos/"))  == again.view(for: photos))
    #expect(again.view(for: other) == FolderView(), "a folder never changed gets the default")

    again.useAsDefaults(again.view(for: photos))
    #expect(ViewStore(url: file).view(for: other).columns == [.name, .modified, .size, .created])
}

@Test func nameStaysFirstAndHidingTheSortColumnSortsByName() {
    var view = FolderView(columns: [.size, .name, .size, .kind])
    #expect(view.columns == [.name, .size, .kind])
    view.toggle(.name)
    #expect(view.columns.first == .name)
    view.order = ItemOrder(key: .kind)
    view.toggle(.kind)
    #expect(view.order.key == .name)
}

@Test func anOlderOrDamagedViewFileStillOpens() throws {
    let file = scratchFile()
    defer { try? FileManager.default.removeItem(at: file) }
    try Data(#"{"standard": {"mode": "icons"}, "folders": {"/x": {"columns": ["name", "tags", "nonsense"]}}}"#.utf8).write(to: file)
    let store = ViewStore(url: file)
    #expect(store.view(for: URL(filePath: "/y")).mode == .icons)
    #expect(store.view(for: URL(filePath: "/x")).columns == [.name, .tags])
    #expect(store.view(for: URL(filePath: "/x")).order == ItemOrder())
    try Data("not json".utf8).write(to: file)
    #expect(ViewStore(url: file).view(for: URL(filePath: "/x")) == FolderView())
}

@Test func newSortKeysSortByTheirDates() {
    let old = Date(timeIntervalSince1970: 0)
    let new = Date(timeIntervalSince1970: 100)
    let items = [
        FileItem(url: URL(filePath: "/x/a.txt"), name: "a.txt", isFolder: false, created: new, added: old),
        FileItem(url: URL(filePath: "/x/b.md"), name: "b.md", isFolder: false, created: old, added: new),
    ]
    #expect(ItemOrder(key: .created).sorted(items).map(\.name) == ["b.md", "a.txt"])
    #expect(ItemOrder(key: .added).sorted(items).map(\.name) == ["a.txt", "b.md"])
    #expect(ItemOrder(key: .ext).sorted(items).map(\.name) == ["b.md", "a.txt"])
}

@Test func newFoldersOpenInDetailsUntilAnotherViewIsChosen() {
    var memory = ViewMemory()
    #expect(memory.standard.mode == .details)
    let shown = URL(filePath: "/tmp/shown")
    memory.remember(FolderView(mode: .details), for: shown)
    memory.setStandardMode(.icons)
    #expect(memory.view(for: URL(filePath: "/tmp/new")).mode == .icons)
    #expect(memory.view(for: shown).mode == .details)
}
