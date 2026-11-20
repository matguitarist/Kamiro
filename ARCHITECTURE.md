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
