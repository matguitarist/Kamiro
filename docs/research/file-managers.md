# File managers on macOS

Research for Kamiro. Done 2026-11-19.
Question: what makes the best file manager on macOS 26, and which Explorer habits belong in a Finder-looking app?
[V] verified in a source, [K] from knowledge, [U] unverified, test first.

## Findings

- Every paid Finder alternative except Path Finder and QSpace is a dual-pane "commander" (ForkLift, Commander One, Marta, Nimble Commander, fman). No polished app is "Finder plus Explorer's habits"; the only Windows 11-style app is explorer-macos, a hobby project (MIT, 5 stars, not notarized). [V](https://www.shuffleapp.co/blog/best-finder-alternatives-macos) [V](https://github.com/preslav-panayotov/explorer-macos)
- Switchers' most-cited Finder gaps: no real Cut, no address bar you can type in, no Up button, Copy as Pathname hidden, Return renames instead of opening, no New File, column view cramps long names, views go stale, folder sizes slow or missing. People pay for add-ons (Command X, Floating Finder) for single gaps. [V](https://news.ycombinator.com/item?id=43250277) [V](https://news.ycombinator.com/item?id=49589722) [V](https://discussions.apple.com/thread/252249785) [V](https://floating-finder.pages.dev/)
- Explorer doesn't show folder sizes either: showing them beats both. [V](https://www.howtogeek.com/finder-vs-windows-explorer-differences-every-mac-switcher-needs-to-know/)
- The native look is the open gap: Commander One and Marta lose on "not Mac-like, no sidebar"; QSpace is loved for "feels like Finder, turbocharged"; ForkLift gained by adopting the Tahoe sidebar (4.4.3). [V](https://www.macupdate.com/app/mac/55082/commander-one) [V](https://apps.apple.com/us/app/qspace/id1469774098) [V](https://alternativeto.net/news/2025/10/forklift-4-4-3-adds-macos-tahoe-sidebar-style-appmover-feature-removal-and-bug-fixes)
- Finder 26: Icon ⌘1, List ⌘2, Column ⌘3, Gallery ⌘4; Preview ⇧⌘P, path bar ⌥⌘P, status bar ⌘/; glass sidebar and toolbar; critics note double bezels and mismatched toolbar heights from hand-made chrome. [V](https://support.apple.com/en-us/102650) [V](https://www.macobserver.com/news/macos-26-critics/)
- Liquid Glass comes free with NavigationSplitView, the system toolbar and `.inspector`. [V](https://developer.apple.com/videos/play/wwdc2025/323/)
- Explorer: Ctrl+L / Alt+D address bar, F2 rename, Ctrl+X/C/V, Alt+Enter Properties, Alt+Shift+P details pane, breadcrumb chevrons list sibling folders, header right-click picks columns, Group by. [V](https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec) [K]
- Explorer is criticised for being slow and for Home/Gallery that can't be removed. [V](https://www.techradar.com/computing/windows/finding-windows-11-sluggish-when-youre-working-with-files-and-folders-youre-not-alone-and-its-high-time-for-microsoft-to-sort-out-file-explorer) [V](https://learn.microsoft.com/en-us/answers/questions/5733937/why-cant-i-remove-home-and-gallery-from-windows-ex)
- Platform: a sandboxed browser only sees folders the user picked, so Path Finder and ForkLift ship without the sandbox (Developer ID, notarized). [K] Desktop, Documents, Downloads, removable and network volumes, iCloud Drive prompt per app, and reads fail silently without purpose strings. [V](https://support.apple.com/guide/security/secddd1d86a6) [V](https://eclecticlight.co/2025/02/20/)
- SwiftUI `Table` hangs with about 1,200 rows; NSTableView/NSOutlineView is the common advice. [V](https://developer.apple.com/forums/thread/739849) [V](https://mjtsai.com/blog/2024/04/15/nstableview-with-swiftui) Whether macOS 26 fixed it: [U].
- `copyfile(3)` with CLONE never calls the progress callback on a successful APFS clone; cancel leaves partial files. [V](https://keith.github.io/xcode-man-pages/copyfile.3.html)
- `defaults write -g NSFileViewer <bundle id>` makes "Reveal in Finder" in many apps open another browser (Path Finder's checkbox); 26.4 reportedly reset it. [V](https://bloomapp.club/user-guide) [U] on 26.2.
- explorer-macos internals: copyfile engine with COPYFILE_QUIT cancel, LazyVStack lists (not to copy), one DispatchSource watcher, QLThumbnailGenerator, FileManager.trashItem, ad-hoc signed. [V](https://github.com/preslav-panayotov/explorer-macos)

## Likes and dislikes

| App | People like | People dislike | Sources |
| --- | --- | --- | --- |
| Path Finder 26 | More power than Finder; dual pane, Drop Stack, terminal, batch rename | Crashes and new bugs each version; subscription-like pricing; cluttered, not Finder-like | setapp.com/apps/path-finder, talk.tidbits.com/t/18179 |
| ForkLift 4 | Modern macOS look (Tahoe sidebar); remote and sync; transfer queue; New File in menu; workspaces | Column view unusable in narrow panes; v4 launch regressions; one-year license | eshop.macsales.com/blog/86687, atpeaz.com, pawelgrzybek.com |
| QSpace Pro | Feels like native Finder, turbocharged; 1–4 panes; fast; no subscription | Missing tabs per pane and Refresh; network folders don't refresh; thin docs, paid add-ons | apps.apple.com/us/app/qspace/id1469774098 |
| Commander One | Lots of power (FTP, cloud, archives) | Not Mac-like, no sidebar; can't hide second pane; PRO paywall; slow deletes | macupdate.com, g2.com |
| Marta | Fast, free, keyboard-driven, archives as folders | No sidebar, no thumbnails, no batch rename; config file settings; stalled | news.ycombinator.com/item?id=32335214, xda-developers.com |
| Nimble Commander | Very fast; live filter; SFTP/SMB | Steep learning curve; "not like Finder"; unmaintained; GPL | news.ycombinator.com/item?id=37347997 |
| Windows 11 Explorer | Tabs; address bar; details columns; Properties; New from menu | Slow; Home/Gallery can't be removed; short right-click menu hides the real one | tomsguide.com, techradar.com, learn.microsoft.com |
| explorer-macos | Real cut/paste, typed path, details columns, status bar, Properties, CLI | Windows look on a Mac; not notarized; lists slow on big folders [U] | github.com/preslav-panayotov/explorer-macos |
| Finder 26 | Quick Look, column view once learned, native look | No cut, no typed path, stale views, Return renames, hidden file system | HN threads above |

Patterns: must have — native look with a sidebar, speed, Quick Look, tabs, a one-time price, no setup.
Our chance — cut/paste, typed address bar, Up, Copy Path, New File, folder sizes, live refresh everywhere, full right-click menu at once, stability.

## Feature matrix

| Feature | Finder | Explorer | Path Finder | ForkLift | QSpace | explorer-macos | Version one? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Native macOS 26 sidebar and toolbar | ✓ | – | ~ | ✓ | ✓ | – | yes (S-001) |
| Details view, sortable columns | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | yes (S-002, S-021) |
| Icon view with thumbnails | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | yes (S-019) |
| Column view | ✓ | – | ✓ | ✓ | ✓ | – | yes (S-020) |
| Gallery view | ✓ | ~ | – | – | – | – | Later |
| Editable address bar with crumbs | – | ✓ | ✓ | ~ | ~ | ✓ | yes (S-004, S-005) |
| Back / Forward / Up | ~ | ✓ | ✓ | ✓ | ✓ | ✓ | yes (S-003) |
| Real cut and paste | – | ✓ | ✓ | ✓ | ✓ | ✓ | yes (S-011) |
| Transfer progress, cancel, conflicts | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | yes (S-012, S-013) |
| Multi-level undo | ~ | ✓ | ~ | ~ | ~ | ✓ | yes (S-017) |
| New file from menu | – | ✓ | ✓ | ✓ | ✓ | ✓ | yes (S-015) |
| Folder sizes | ~ | – | ✓ | ✓ | ✓ | – | yes (S-023) |
| Group by | ✓ | ✓ | ✓ | – | ✓ | ✓ | yes (S-022) |
| Details pane / inspector | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | yes (S-025) |
| Properties / Get Info | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | yes (S-026) |
| Status bar with selection size and free space | ~ | ✓ | ✓ | ✓ | ✓ | ✓ | yes (S-008) |
| Tabs | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | yes (S-030) |
| Tags | ✓ | – | ✓ | ✓ | ✓ | – | yes (S-027) |
| Search (name filter and Spotlight) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | yes (S-028, S-029) |
| Home page (pins, recents) | ~ | ✓ | – | – | – | ✓ | yes (S-031) |
| Open in Terminal, Copy Path | ~ | ✓ | ✓ | ✓ | ✓ | ✓ | yes (S-034) |
| Compress / extract | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | yes (S-035) |
| Default file viewer (Reveal in…) | ✓ | ✓ | ✓ | – | – | – | yes (S-038) |
| Terminal command | – | ✓ | – | – | – | ✓ | yes (S-039) |
| Dual pane | – | – | ✓ | ✓ | ✓ | – | Later |
| Batch rename | ✓ | ~ | ✓ | ✓ | ✓ | – | Later |
| Remote (SFTP, S3, cloud) | ~ | ~ | ✓ | ✓ | add-on | – | Dropped |
| Folder sync / compare | – | – | ✓ | ✓ | – | – | Dropped |

## Decisions

1. Position Kamiro as "Finder, plus Explorer's habits", one pane, because no polished app holds that spot [V].
2. Developer ID, notarized, no sandbox, with purpose strings and a Full Disk Access guide, because a sandboxed browser can't browse freely [K]. Planned test: listing ~/Desktop with and without the purpose strings on a fresh TCC reset.
3. Details view on NSOutlineView inside SwiftUI; chrome in SwiftUI (NavigationSplitView, toolbar, inspector), because SwiftUI Table hangs on large folders [V] and glass comes free with system parts [V]. Planned test: open a 100,000-file folder; first rows under 300 ms, scrolling at 120 fps.
4. Copy engine on copyfile with a pre-counted byte total, a job queue, conflict prompts and cleanup on cancel, borrowing explorer-macos's shape (MIT) [V].
5. Live refresh with FSEvents per open tab, because DispatchSource watches one folder only [K]. Planned test: a file created by `touch` appears within 0.5 s.
6. Keep every Finder shortcut and layer Explorer's on top (⌘X, ⌘L, F2, ⌘↑ Up), all in the menu bar [K].
7. Leave remote servers, sync and dual pane out of version one; that's ForkLift's ground [V].

## Open questions

- Does macOS 26 SwiftUI Table cope with 10k rows? [U] Benchmark before ruling it out for the icon/list views.
- Does NSFileViewer still redirect Reveal in Finder on 26.2? [U] Test in S-038.
- Does any competitor already use real Liquid Glass chrome? [U] Look at ForkLift 4.7 and QSpace.
