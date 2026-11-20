# Architecture review, 2026-11-20 (end of M4)

Survey: no Swift file over 600 lines (largest: ColumnBrowser 578, DetailsTable 540, IconGrid 529).
BrowserModel is 458 lines after FolderSizes moved out in M3. No duplicated private structs.
FIXLOG gained two entries (window frame in test runs, light stripes in dark mode), in different areas.
New this milestone: places that aren't folders (VirtualPlace: a tag, a search), carried as kamiro: URLs
so history, view memory and the window's restore work unchanged.

## What a place allows, in one type  [Worth exploring]

Files: BrowserModel, Commands, FileActions, ListSupport, BrowserView, TagsUI, SearchUI, FolderSizes
Signal: S-027 and S-029 each touched more than 6 files; 24 checks of `isVirtual` or `isFileURL` in 9 files.
Problem: each action decides on its own whether it applies to a tag or search (New Folder, Paste, drop,
Enclosing Folder, Go Up, columns view, watching, folder sizes). S-033 (right-click for everything),
S-034 (terminal here) and S-035 (compress) will each add another check.
Proposal (KamiroKit, plain values, unit-testable):
```swift
public struct PlaceRules: Equatable, Sendable {
    public var canMakeItems: Bool      // New Folder, New File, Paste, drop
    public var canGoUp: Bool
    public var allowsColumns: Bool
    public var watchesChanges: Bool
    public var showsEnclosingFolder: Bool
    public static func of(_ url: URL) -> PlaceRules
}
```
Benefits: one switch on the place kind; a new action asks `model.rules`; a unit test lists what each
place allows.
Proof of same behavior: self-test (tags: nothing to make or paste; search: Back, Enclosing Folder),
the tags and search-results snapshots.
Plan: one commit adding PlaceRules with tests; one moving callers over. Best done just before S-033.

## Split the three list views by concern  [Worth exploring]

Unchanged from the M3 review: ColumnBrowser, DetailsTable and IconGrid near 600 lines with 4–6
types each; drag and drop code is similar across the three coordinators.

## Spotlight behind a seam  [Speculative]

TagFinder.spotlight and Search.spotlight are not exercised by tests: test runs walk /tmp because
Spotlight doesn't index it. A seam would still have one real adapter; a by-hand check on an indexed
folder covers it.

**Top recommendation:** What a place allows, in one type (Worth exploring): not done unattended;
suggested before S-033.

Considered, not recommended: moving the filter out of BrowserModel (about 25 lines, tied to loading).
