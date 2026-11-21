import Foundation

/// The right-click menu's actions that Settings › Menu can hide (S-047). Open, Cut, Copy,
/// Paste, Rename, Move to Trash, New Folder and Properties always show.
public enum MenuEntry: String, CaseIterable, Sendable {
    case openWith, openInNewTab, quickLook, copyPath, copyInfo, duplicate, copyTo, moveTo
    case compress, extract, convert, tags, pinToSidebar, openInTerminal, openInEditor
    case newFile, newFileFromClipboard
}

/// What the right-click menu leaves out: actions, and New File types. Kept as their names;
/// names a newer or older Kamiro wrote and this one doesn't know are dropped.
public struct MenuChoices: Equatable, Sendable {
    public private(set) var hiddenEntries: Set<MenuEntry>
    public private(set) var hiddenTemplates: Set<String>

    public init(hiddenEntries: [String] = [], hiddenTemplates: [String] = []) {
        self.hiddenEntries = Set(hiddenEntries.compactMap(MenuEntry.init))
        let known = Set(FileTemplate.all.map(\.id))
        self.hiddenTemplates = Set(hiddenTemplates).intersection(known)
    }

    public func shows(_ entry: MenuEntry) -> Bool { !hiddenEntries.contains(entry) }
    public func shows(_ template: FileTemplate) -> Bool { !hiddenTemplates.contains(template.id) }

    /// New File's types, in their usual order.
    public var templates: [FileTemplate] { FileTemplate.all.filter(shows) }

    /// New File shows while it's on and has a type left.
    public var showsNewFile: Bool { shows(.newFile) && !templates.isEmpty }

    public mutating func show(_ entry: MenuEntry, _ shown: Bool) {
        if shown { hiddenEntries.remove(entry) } else { hiddenEntries.insert(entry) }
    }

    public mutating func show(_ template: FileTemplate, _ shown: Bool) {
        if shown { hiddenTemplates.remove(template.id) } else { hiddenTemplates.insert(template.id) }
    }

    public var isEverythingShown: Bool { hiddenEntries.isEmpty && hiddenTemplates.isEmpty }

    /// For storing: in menu order, so the file reads the same each time.
    public var storedEntries: [String] { MenuEntry.allCases.filter(hiddenEntries.contains).map(\.rawValue) }
    public var storedTemplates: [String] { FileTemplate.all.map(\.id).filter(hiddenTemplates.contains) }
}
