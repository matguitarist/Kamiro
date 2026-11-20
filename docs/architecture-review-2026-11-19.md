# Architecture review, 2026-11-19 (end of M3)

Survey: no Swift file over 600 lines (largest: ColumnBrowser 578, DetailsTable 534, IconGrid 529).
BrowserModel is one type of about 440 lines and every M3 story changed it (8 commits in 30 days).
No duplicated private structs. FIXLOG has 3 entries, in different areas.

## Folder sizes as their own module  [Strong]

Files: Sources/Kamiro/BrowserModel.swift (455 lines)
Signal: a type over 400 lines; touched by every story of the milestone.
Problem: BrowserModel owns navigation, loading, view memory, the address bar and now the folder
size queue, its FSEvents watch, cancellation and run counting (seven stored properties for sizes
alone). A change to how sizes are measured means reading the whole model.
Proposal:
```swift
@MainActor @Observable final class FolderSizes {
    private(set) var sizes: [URL: Int64]
    private(set) var version: Int
    var isMeasuring: Bool
    @ObservationIgnored var arrived: () -> Void        // the model sorts again
    func start(in folder: URL, items: @escaping () -> [FileItem])
    func measure(_ urls: [URL])
}
```
Benefits: locality (the queue, the watcher and cancellation live in one file); BrowserModel drops
about 60 lines and seven properties.
Proof of same behavior: the S-023 self-test checks (— until measured, sizes shown, sort, follows
changes, unreadable folder, stops on leaving), unit tests, browse snapshot.
Plan: one commit (new file, model holds it).

## Split the three list views by concern  [Worth exploring]

Files: ColumnBrowser.swift (578), DetailsTable.swift (534), IconGrid.swift (529)
Signal: each nears 600 lines and holds 4–6 types (representable, coordinator, AppKit subclass,
cells, previews).
Proposal: one file per type group (e.g. ColumnBrowser+Drag.swift, ColumnPreview.swift); drag and
drop code is similar across the three coordinators and could share a helper in ListSupport.
Not now: under the 600-line signal and no bug came from it.

## A file system seam for the model  [Speculative]

BrowserModel calls FolderReader and FolderSize directly. Tests run on a /tmp tree instead, which
works well; a seam would have one adapter.

**Top recommendation:** Folder sizes as their own module (Strong), done in this check-in.

Considered, not recommended: moving per-folder view memory out of BrowserModel (about 50 lines,
tightly tied to navigation), and an ARCHITECTURE.md rewrite (none exists yet; added below).
