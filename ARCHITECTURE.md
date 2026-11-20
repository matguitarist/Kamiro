# Kamiro architecture

## Targets

- **KamiroKit** (no SwiftUI): reading folders (`FolderReader`, `FileItem`), sorting (`ItemOrder`),
  grouping (`Grouping`), view memory (`FolderView`, `ViewStore`), folder sizes (`FolderSize`),
  file operations, and the FSEvents watchers (`FolderWatcher` for one folder, `TreeWatcher` for a tree).
  Unit tests in `Tests/KamiroKitTests`.
- **Kamiro** (the app) depends on KamiroKit, never the other way.

## The window

- `BrowserModel` (one per window, `@MainActor @Observable`): the folder, history, items, selection,
  view mode and per-folder view, loading. Reads run in detached tasks; the model applies results.
- `FolderSizes`: the subfolder size queue the model owns; measuring runs off the main thread and
  stops when the window opens another folder.
- Three list views, each an AppKit view behind an `NSViewRepresentable` with a coordinator that
  syncs from the model by version counters (`itemsVersion`, `groupVersion`, `sizesVersion`, tokens):
  details (`DetailsTable`, NSTableView), icons (`IconGrid`, NSCollectionView), columns
  (`ColumnBrowser`, NSBrowser). Shared keys, Quick Look, rename and menus are in `ListSupport`.
  The column browser syncs after SwiftUI's update pass, not inside it (FIXLOG 2026-11-19).
- `MenuState` mirrors the front window for the menu bar; `HiddenFiles` is the one app-wide choice.

## Checks

`SelfTest` (+Views) drives a real window on a /tmp tree; `Snapshot` shoots every page.

## Cloud folders (S-057, S-058)

`Cloud` (KamiroKit/Cloud.swift) knows iCloud Drive (~/Library/Mobile Documents/com~apple~CloudDocs), the
apps' containers next to it, and ~/Library/CloudStorage. `Location.parent` asks it first, so iCloud Drive
and sync folders are a top and an app's folder sits in iCloud Drive. BrowserModel reads `CloudStatus`
only in cloud folders, after the list, in a task like folder sizes (`cloud`, `cloudVersion`). Test runs
point `Cloud` at /tmp/Kamiro-home and read statuses from an extended attribute.

## Places that aren't folders (M4)

A window shows either a folder (a file URL) or a VirtualPlace (KamiroKit/Places.swift): a tag's items
or search results, written as `kamiro:tag?name=Red` or `kamiro:search?text=…&in=…&kind=…&date=…`.
Because they are URLs, Back and Forward, per-place view memory and the restored window need no
special case. BrowserModel.read asks the place for its items (Spotlight; test runs walk the /tmp
tree instead). Actions that need a real folder check `isVirtual`. A search's scope or filters
change with History.replace, so Back leaves the search in one step. The toolbar filter
(NameFilter) narrows `items` from `allItems` without reading the folder again.
