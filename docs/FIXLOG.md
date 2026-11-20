# Kamiro fix log

## 2026-11-19 The list lost the keyboard after a folder that couldn't open
After the window showed "Kamiro can't open this folder" and went back to a readable folder,
the list was built again and asked for the keyboard before it was in the window, so the ask
was dropped: arrows, Return and ⌘X did nothing until a click. Found by the M2 self-test.
Fix: DetailsCoordinator keeps the focus request until the table has a window, and
FileTable.viewDidMoveToWindow runs it.
Rule: an NSView inside SwiftUI can be created before it has a window; any request that needs
the window (first responder, scroll, sheet) waits for viewDidMoveToWindow.

## 2026-11-19 Reading a big folder waited behind the redraw
Clearing the list redrew the window before the read started, adding about 50 ms on 10,000
files (the 300 ms check failed at 303 to 310 ms).
Fix: BrowserModel starts the read in a detached task before it touches the observed state.
Rule: start slow background work first, then change what SwiftUI watches.

## 2026-11-19 Switching from icons to columns crashed
Going from the icon view to the column view with a folder to open crashed, either inside
Observation (SwiftUI tracking) or with NSBrowser's "not a valid set of index paths". Found by
the full M3 snapshot run; present since S-020.
Fix: ColumnBrowser.updateNSView hands the sync to the next main-queue turn instead of building
columns inside SwiftUI's update, and ColumnCoordinator.show opens the folder's column before
selecting rows in it. The FSEvents watchers now retain their callback box too.
Rule: an AppKit view that builds SwiftUI views of its own (NSBrowser's preview column, hosted
cells) is driven after updateNSView returns, not from inside it; and NSBrowser selects only in
columns it has loaded.

## 2026-11-20 Folder sizes kept the CPU busy for hours
In a folder holding ~/Library, Kamiro measured sizes without end: Library changes all the time,
each change put it back in the queue, and each walk took minutes (34 min of CPU in 1 h 40).
Found while running the self-test beside the installed app.
Fix: FolderSizes waits FolderSize.recheckDelay (ten times the last measure, at least 2 s) before
measuring a folder again, and measures at utility priority.
Rule: work started by file-system events is spaced by what it costs, never repeated on every event.

## 2026-11-20 Test runs changed the real window size
APP_SNAPSHOT_MIN=1 shrank the window, and macOS saved that frame in the real defaults, so the
next self-test ran in a narrow window and failed.
Fix: tools/snap.sh and tools/selftest.sh put "NSWindow Frame browser-AppWindow-1" back on exit.
Rule: a test run restores every real setting it can touch, including ones macOS writes for it.

## 2026-11-20 Light stripes in a dark list
Switching to dark mode while the toolbar search field had the keyboard left the details list's
empty rows (below the last item) in their light-mode colors. The table repainted its rows but not
the stripes drawn past them. FileTable now marks itself and its clip view for redrawing in
viewDidChangeEffectiveAppearance. Seen in the search-results-dark snapshot.
Rule: an AppKit view that draws its own background redraws it when the appearance changes; check the dark snapshot of every page that leaves the keyboard outside the list.

## 2026-11-20 External drives showed "Zero KB" free
The status bar and the new Home page read volumeAvailableCapacityForImportantUsage, which is 0
on some external and network volumes, so a 4 TB drive with 1.3 TB free showed "Zero KB".
Found by the Home page snapshot.
Fix: Volumes.availableSpace falls back to volumeAvailableCapacity when the important-usage
value is 0.
Rule: "important usage" space is for the boot volume; for any other volume, check it against
the plain free space.

## 2026-11-20 snap.sh didn't put the real window size back
restoreFrame wrote the saved frame with `defaults write` without a type, and the frame string
(with its JSON tiling state) didn't parse, so a snapshot run left the real window at the test
size. Fix: `defaults write … -string`.
Rule: write saved strings back with an explicit `-string`; `defaults` reads untyped values as plists.

## 2026-11-20 Column view: columns seemed not to resize, and an empty column followed the preview
NSBrowser's user resizing only works from a small "||" grip at the bottom of each column, which
people don't find (and which is off screen when the window is taller than the display). The
preview column was sized like a folder column: a file has no children, so it got the 160 pt
minimum, and the rest of the browser stayed empty, which read as a third, dead column.
Fix: FileBrowser takes clicks on the whole edge between columns (hitTest, mouseDown, cursor
rects) and the coordinator keeps the chosen widths per folder; the preview column widens to
the right edge after every layout (tile). Found by the owner.
Rule: an AppKit control's built-in affordance isn't enough if people can't find it; check
the whole hit area, and size special columns (previews, footers) on their own, not by the
rule for ordinary ones.

## 2026-11-20 Scrolling 10,000 icons and reading a big folder were over budget
The self-test's scroll check took 17.7 to 18.2 ms a step (limit 16) and the 10,000-file read
300 to 304 ms (limit 300). Shipped that way in 1.0.0.
Profiled with `sample` during the self-test:
- Asking QLThumbnailGenerator for a thumbnail waits on its queue (dispatch_sync): 13% of the
  scroll time on the main thread. Thumbnails.load now asks from a queue of its own.
- IconCell.layout measured the name (cellSizeForBounds) and set every frame on each pass,
  even for an unchanged reused cell: 24%. It now skips when size, icon size, name and
  rename state are the same as last time.
- FileItem.init made each URL canonical, and standardizing checks the disk (a stat per file):
  half of FolderReader.list. The listing now makes the folder canonical once and builds its
  children's URLs from it.
Rule: profile before guessing; on main, never call an API that waits on another queue, and
in per-item code (cells, listings) never touch the disk for what the parent already knows.

## 2026-11-20 Compress kept the file's extension in the zip's name
Compressing “Capture d’écran 2026-11-17 at 18.25.11.png” made “… 18.25.11.png.zip”. That was
the Finder's way, copied on purpose in S-035, but the owner wants the extension gone.
Fix: Archive.name drops a single file's extension (“report.zip”); a folder keeps its whole
name even with dots in it (“My.Project.zip”).
Rule: a name built from another file's name splits off the extension only for files, never
for folders, and the owner's habit wins over copying the Finder.
