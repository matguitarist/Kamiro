import Foundation
import Testing
@testable import KamiroKit

@Test func everythingShowsUntilHidden() {
    let choices = MenuChoices()
    #expect(MenuEntry.allCases.allSatisfy(choices.shows))
    #expect(choices.templates == FileTemplate.all)
    #expect(choices.showsNewFile)
    #expect(choices.isEverythingShown)
}

@Test func hiddenActionsAndTypesAreKeptByNameAndUnknownNamesDropped() {
    var choices = MenuChoices(hiddenEntries: ["convert", "teleport", "tags"], hiddenTemplates: ["xml", "cobol"])
    #expect(!choices.shows(.convert) && !choices.shows(.tags) && choices.shows(.copyTo))
    #expect(choices.storedEntries == ["convert", "tags"])
    #expect(choices.storedTemplates == ["xml"])
    #expect(!choices.templates.contains { $0.id == "xml" } && choices.templates.count == FileTemplate.all.count - 1)
    choices.show(.convert, true)
    choices.show(.quickLook, false)
    #expect(choices.storedEntries == ["quickLook", "tags"], "stored in menu order")
    let again = MenuChoices(hiddenEntries: choices.storedEntries, hiddenTemplates: choices.storedTemplates)
    #expect(again == choices)
}

@Test func newFileGoesAwayWithItsLastType() {
    var choices = MenuChoices()
    for template in FileTemplate.all.dropLast() { choices.show(template, false) }
    #expect(choices.showsNewFile)
    choices.show(FileTemplate.all.last!, false)
    #expect(!choices.showsNewFile)
    choices = MenuChoices(hiddenEntries: ["newFile"])
    #expect(!choices.showsNewFile)
}
