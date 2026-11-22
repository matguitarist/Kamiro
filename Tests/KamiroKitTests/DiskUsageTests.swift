import CoreGraphics
import Foundation
import Testing
@testable import KamiroKit

@Test func treemapFillsItsBoxInProportion() {
    let sizes: [Double] = [6, 6, 4, 3, 2, 2, 1]
    let box = CGRect(x: 0, y: 0, width: 600, height: 400)
    let rects = Treemap.layout(sizes, in: box)
    let total = sizes.reduce(0, +)
    for (size, rect) in zip(sizes, rects) {
        let expected = Double(box.width * box.height) * size / total
        #expect(abs(Double(rect.width * rect.height) - expected) < 1, "\(rect) for \(size)")
        #expect(box.insetBy(dx: -0.01, dy: -0.01).contains(rect))
    }
    // Nothing overlaps.
    for i in rects.indices {
        for j in rects.indices where j > i {
            #expect(rects[i].intersection(rects[j]).width * rects[i].intersection(rects[j]).height < 0.01)
        }
    }
    // Close to square: no tile thinner than 1 to 4 here.
    #expect(rects.allSatisfy { max($0.width / $0.height, $0.height / $0.width) < 4 })
}

@Test func treemapGivesNothingToEmptyItems() {
    let rects = Treemap.layout([0, 5, -1], in: CGRect(x: 0, y: 0, width: 10, height: 10))
    #expect(rects[0] == .zero && rects[2] == .zero)
    #expect(rects[1].width == 10 && rects[1].height == 10)
    #expect(Treemap.layout([1, 2], in: .zero).allSatisfy { $0 == .zero })
}

@Test func treemapTilesOpenRoomyFolders() {
    let a = DiskNode(url: URL(filePath: "/r/A/a"), name: "a", size: 50, category: .other)
    let b = DiskNode(url: URL(filePath: "/r/A/b"), name: "b", size: 50, category: .other)
    let folder = DiskNode(url: URL(filePath: "/r/A"), name: "A", size: 100, items: 2, category: .folder, children: [a, b])
    let file = DiskNode(url: URL(filePath: "/r/c"), name: "c", size: 100, category: .pictures)
    let root = DiskNode(url: URL(filePath: "/r"), name: "r", size: 200, items: 4, category: .folder, children: [folder, file])
    let tiles = Treemap.tiles(for: root, in: CGRect(x: 0, y: 0, width: 400, height: 200))
    #expect(tiles.map(\.node.name) == ["A", "a", "b", "c"])
    #expect(tiles[0].isOpen && tiles[1].depth == 1)
    #expect(tiles[0].rect.contains(tiles[1].rect) && tiles[1].rect.minY >= 16)
    #expect(root.path(to: "/r/A/b")?.map(\.name) == ["r", "A", "b"])
    #expect(Treemap.tiles(for: root, in: CGRect(x: 0, y: 0, width: 400, height: 200), depth: 1).count == 2)
}

@Test func diskUsageMatchesFolderSizeAndFoldsSmallFiles() throws {
    let root = URL(filePath: NSTemporaryDirectory()).appending(path: "Kamiro-diskusage-\(UUID().uuidString)")
    let inner = root.appending(path: "Inner")
    try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for n in 0..<8 { try Data(count: 5_000 * (n + 1)).write(to: inner.appending(path: "f\(n).bin")) }
    try Data(count: 100_000).write(to: root.appending(path: "big.mov"))
    try FileManager.default.linkItem(at: root.appending(path: "big.mov"), to: inner.appending(path: "same.mov"))
    try Data("hi".utf8).write(to: root.appending(path: ".hidden"))

    let tree = try DiskUsage.scan(root, keep: 3)
    #expect(tree.size == (try FolderSize.measure(root)))
    #expect(tree.items == 12)
    let innerNode = try #require(tree.children.first { $0.name == "Inner" })
    // Three biggest files, then one tile for the other five (the link is counted once, in either place).
    let smaller = try #require(innerNode.children.first { $0.isSmallerItems })
    #expect(smaller.isSmallerItems && smaller.items >= 5)
    #expect(innerNode.children.filter { !$0.isSmallerItems }.count == 3)
    #expect(tree.children.map(\.size) == tree.children.map(\.size).sorted(by: >))
    #expect(tree.children.contains { $0.category == .movies } || innerNode.children.contains { $0.category == .movies })
    #expect(tree.path(to: root.canonical.appending(path: "Inner/f7.bin").path)?.map(\.name).suffix(2) == ["Inner", "f7.bin"])
    #expect(throws: FolderError.self) { try DiskUsage.scan(root.appending(path: "nope")) }
}

@Test func diskCategoriesFollowTypes() {
    #expect(DiskCategory.of(URL(filePath: "/x/a.jpg")) == .pictures)
    #expect(DiskCategory.of(URL(filePath: "/x/a.mov")) == .movies)
    #expect(DiskCategory.of(URL(filePath: "/x/a.mp3")) == .music)
    #expect(DiskCategory.of(URL(filePath: "/x/a.zip")) == .archives)
    #expect(DiskCategory.of(URL(filePath: "/x/a.swift")) == .code)
    #expect(DiskCategory.of(URL(filePath: "/x/a.pdf")) == .documents)
    #expect(DiskCategory.of(URL(filePath: "/x/A.app"), isPackage: true) == .apps)
    #expect(DiskCategory.of(URL(filePath: "/x/noext")) == .other)
}
