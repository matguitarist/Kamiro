# Kamiro

A file manager for the Mac that looks like Finder and works like Windows File Explorer: for people who move a lot of files and miss cut and paste, a path they can type, and real details columns.

## Replaces
Finder for daily file work, and the add-ons people buy to patch it (Command X, Floating Finder). Inspired by explorer-macos (MIT): its behaviour, not its Windows look.

## Main jobs
1. **Browse**: go to a folder fast (sidebar, typed path, Up, Back) and see it in details, icons or columns.
2. **Move files**: cut, copy, paste, rename, new file or folder, trash, with progress and Undo.
3. **Know your files**: sizes (folders too), dates, kinds, previews, tags, and search.

## Data
- Location: URL, display name, volume, kind (folder, file, package, volume, alias).
- Item (read from disk): name, size or folder size, dates, kind, tags, hidden, iCloud status.
- Pin: a folder in the sidebar's Pinned section, with its order.
- Transfer: operation (copy, move, trash, create), sources, destination, progress, undo record.
- View settings: mode, sort, columns, grouping — per folder, with a default.

## Platforms
Mac only: Swift 6, SwiftUI with AppKit where speed needs it, SwiftPM at the root (`new-mac-app`). macOS 26.

## Shape
One window with native tabs: sidebar (Home, Pinned, Locations, Tags), content (details, icons or columns), inspector on the right, status bar under the content. Toolbar: Back, Forward, Up, the address bar in the middle, view switcher, search. Local data, works offline, no accounts. Developer ID, notarized, no sandbox (decided by the agent: a sandboxed browser can't browse freely).

## Distribution
Public, free and open source under MIT (owner, 2026-11-19): public GitHub repo, README.md and README.fr.md, notarized releases with Sparkle updates. Credits explorer-macos in the README and About window.

## System hooks
Privacy prompts for Desktop, Documents, Downloads and volumes, with a guide to Full Disk Access. FSEvents for live refresh. Quick Look (Space, thumbnails). Spotlight search. Finder tags. Default file viewer (NSFileViewer) so "Reveal in Finder" opens Kamiro. A `kamiro` terminal command. Open in Terminal.

## Reference
Finder on macOS 26 for the look; Windows 11 File Explorer and explorer-macos for the habits (docs/research/file-managers.md). Borrowed code and ideas are listed in docs/BORROWED.md.

## Look
Native: Finder's sidebar, toolbar and Liquid Glass from the system parts, no custom chrome, no Windows colours. Accent: system (decided by the agent; the owner may pick one). English and French.
Keys: every Finder shortcut keeps its meaning; Explorer's are added where free (⌘X cut, ⌘L address bar, F2 rename, ⌘↑ Up, ⌥↩ Properties). Return renames like Finder unless Settings › General › "Return opens items" is on (owner, 2026-11-19).

## Not in version one
- Remote servers, cloud accounts, folder sync (ForkLift's ground).
- Dual pane and workspaces.
- Batch rename, Gallery view, the Desktop (Finder keeps it).
