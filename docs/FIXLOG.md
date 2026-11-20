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
