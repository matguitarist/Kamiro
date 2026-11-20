import Foundation
import Testing
@testable import KamiroKit

@Test func filterMatchesEveryWordIgnoringCaseAndAccents() {
    let names = ["Invoice 1.pdf", "Invoice 2.pdf", "Invoice 12.pdf", "Résumé.docx", "notes.md"]
    let items = names.map { FileItem(url: URL(filePath: "/x/\($0)"), name: $0, isFolder: false) }
    #expect(NameFilter.apply(items, "INVOICE").count == 3)
    #expect(NameFilter.apply(items, "inv 2").map(\.name) == ["Invoice 2.pdf", "Invoice 12.pdf"])
    #expect(NameFilter.apply(items, "resume").map(\.name) == ["Résumé.docx"])
    #expect(NameFilter.apply(items, "   ").count == 5)
    #expect(NameFilter.apply(items, "zzz").isEmpty)
}
