# Kamiro — User stories

Source of truth for the "Kamiro Roadmap" project in Thimble. Brief: docs/BRIEF.md. Research: docs/research/file-managers.md.
Snapshot pages named in `Screens:` are built by snapshot mode (`tools/snap.sh`) on a seed folder tree (`tools/seed-tree.sh`: 40 mixed files, a 10,000-file folder, a hidden file, a package, an image set).

---

## M1 Browse (0.1.0)

### S-001 Open a folder in a Finder-style window
As the user, I open Kamiro and see my home folder in a window with a glass sidebar (Home, Pinned, Locations) and a toolbar, like Finder on macOS 26.
Screens: browse, browse-dark
Acceptance:
- [snap] Sidebar, toolbar and content use system parts only (NavigationSplitView, toolbar); no custom backgrounds behind bars.
- [snap] Locations lists the startup disk and mounted volumes with their system icons.
- [self] Clicking a sidebar item shows that folder; ⌘N opens a new window at Home.
- [manual] Side by side with Finder in light and dark, nothing looks foreign.
UX:
- Flow: launch, ⌘N, File › New Window → window at Home, first row not selected → click sidebar item → content shows it
- Surface: sidebar window (a place people come back to)
- States: empty folder "Folder Is Empty" with "New Folder"; unreadable volume "Kamiro can't read this disk." inline
- Words: "Home", "Pinned", "Locations" / « Accueil », « Épinglés », « Emplacements »
- Access: ⌃⌘S toggles sidebar; VoiceOver reads each sidebar item's name
Status: doing
Built: NavigationSplitView with Pinned (home, Applications, Desktop, Documents, Downloads) and Locations (mounted volumes, live). ⌘N opens a window at Home; ⌥-double-click opens a folder in a new one. The empty folder shows "Folder Is Empty"; its New Folder button comes with S-015. Waits on the owner's side-by-side look with Finder.

### S-002 See a folder in the details view
As the user, I see the folder's items as rows with Name, Date Modified, Size and Kind, sorted by name, with folders first.
Screens: browse, details-10k
Depends: S-001
Acceptance:
- [self] A 10,000-file folder shows its first rows within 300 ms and scrolls without dropped frames (NSOutlineView).
- [unit] Sorting by name is Finder's (localized standard compare, numbers in order: "2" before "10").
- [snap] Icons come from NSWorkspace; long names truncate in the middle with the full name in a tooltip.
- [self] Arrow keys, ⇧-click, ⌘-click and ⌘A select; type-to-select jumps to a name.
UX:
- Flow: folder shown → click header to sort, again to reverse → arrows move selection
- Surface: content column (NSOutlineView)
- States: loading only past 0.5 s ("Loading…" with spinner); too many rows scroll smoothly
- Words: column titles "Name", "Date Modified", "Size", "Kind" / « Nom », « Date de modification », « Taille », « Type »
- Access: full keyboard; VoiceOver reads name, kind and size per row
Status: done
Built: NSTableView (not SwiftUI Table) with base keys only; Kind from a per-extension cache. Self-test: 10,000 files listed and sorted under 300 ms.

### S-003 Go back, forward and up
As the user, I go back and forward through the folders I visited and up to the enclosing folder.
Screens: browse
Depends: S-002
Acceptance:
- [unit] History per window: back, forward, up; going up selects the folder I came from.
- [self] ⌘[ ⌘] ⌘↑ and the toolbar buttons work; disabled where they don't apply.
- [self] Long-press on Back lists recent folders.
UX:
- Flow: ⌘[ / toolbar ‹ → previous folder, its selection restored; ⌘↑ / toolbar ↑ → parent with child selected
- Surface: toolbar buttons
- Words: tooltips "Go back (⌘[)", "Go forward (⌘])", "Go to enclosing folder (⌘↑)" / « Revenir (⌘[) », « Avancer (⌘]) », « Dossier parent (⌘↑) »
- Access: Go menu holds all three with shortcuts
Status: done

### S-004 Jump through the address bar
As the user, I see the current path as crumbs in the toolbar; clicking one goes there, and its chevron lists the folders inside it.
Screens: browse, address-menu
Depends: S-003
Acceptance:
- [snap] Crumbs show volume icon and folder names; long paths collapse the middle into "…".
- [self] Clicking a crumb goes there; its chevron menu lists subfolders and opens one.
- [self] Dragging a file onto a crumb moves it there (after S-018).
UX:
- Flow: click crumb → folder; click › → menu of subfolders → pick → folder
- Surface: toolbar principal item; menu for subfolders (a few choices tied to one control)
- Words: "…" menu item "Show Full Path" / « Afficher le chemin complet »
- Access: VoiceOver reads "Path: Users, mathieu, Documents"
Status: done
Built: dragging onto a crumb comes with S-018.

### S-005 Type a path
As the user, I press ⌘L (or ⇧⌘G, or click the empty part of the address bar) and type a path, with Tab completion, to go there.
Screens: address-edit
Depends: S-004
Acceptance:
- [unit] "~", relative names, and paths pasted with quotes or a file:// URL resolve; a file path opens its folder with the file selected.
- [self] Completion lists matching folders as I type; Tab completes, Return goes, Escape restores the crumbs.
- [self] A path that doesn't exist shakes the field and says "No folder at this path." under it.
UX:
- Flow: ⌘L, ⇧⌘G, Go › Go to Folder…, click empty bar → field with path selected → type → Return goes / Escape cancels
- Surface: inline (the address bar turns into a field)
- States: error "No folder at this path." / « Aucun dossier à ce chemin. »
- Words: placeholder "Type a path" / « Saisir un chemin »
- Access: focus returns to the list after Return
Status: done

### S-006 Open files and folders
As the user, I double-click or press ⌘↓ to open a folder in place or a file in its app; with "Return opens items" on, Return does it too.
Screens: browse, settings-general
Depends: S-002
Acceptance:
- [self] ⌘↓ and double-click open; ⌥-double-click opens a folder in a new window.
- [self] Return renames by default; with Settings › General › "Return opens items" on, Return opens and F2 renames.
- [unit] Packages (.app, .bundle) open as files; ⌃-click › Show Package Contents browses them.
UX:
- Flow: double-click / ⌘↓ / File › Open → folder shows or app opens
- Surface: inline
- Words: "Open", "Return opens items" / « Ouvrir », « Retour ouvre les éléments »
Status: done
Built: Show Package Contents comes with the right-click menu (S-033); packages already open as files.

### S-007 Preview with Quick Look
As the user, I press Space to preview the selection with Quick Look, and arrows move through items while it's open.
Screens: quicklook
Depends: S-002
Acceptance:
- [self] Space opens QLPreviewPanel for the selection; Space or Escape closes it; arrows change the previewed item.
UX:
- Flow: select → Space → panel → arrows → Space closes
- Surface: system Quick Look panel
- Words: menu "Quick Look" ⌘Y / « Coup d'œil »
Status: done

### S-008 Read the status bar
As the user, I see under the list how many items there are, how many are selected with their total size, and the free space on the disk.
Screens: browse
Depends: S-002
Acceptance:
- [unit] "12 items, 3 selected (4.2 MB), 120 GB available" with plural rules in English and French.
- [self] View › Hide Status Bar (⌘/) hides it.
UX:
- Surface: bar under the content (inline information)
- Words: "%d items", "%d selected (%@)", "%@ available" / « %d éléments », « %d sélectionnés (%@) », « %@ disponibles »
- Access: VoiceOver reads it as one static text
Status: done

### S-009 See changes made elsewhere
As the user, the folder updates on its own when files are added, removed or renamed by another app.
Screens: browse
Depends: S-002
Acceptance:
- [self] A file created with `touch` appears within 0.5 s; selection and scroll stay put.
- [unit] Bursts of events are coalesced; a renamed selected file stays selected.
- [self] ⌘R refreshes by hand.
UX:
- Flow: change outside → row appears or leaves in place, no flash
- Words: menu "Refresh" ⌘R / « Actualiser »
Status: done
Built: FSEvents on the shown folder; a renamed file keeps its selection by file ID.

### S-010 Grant folder access
As the user, the first time I open Desktop, Documents, Downloads or a volume, macOS asks once; if I said no, Kamiro tells me how to allow it, and offers the Full Disk Access guide.
Screens: access-denied
Depends: S-002
Acceptance:
- [self] Info.plist has purpose strings for Desktop, Documents, Downloads, removable and network volumes.
- [self] A denied folder shows "Kamiro can't open this folder." with "Open Privacy Settings".
- [manual] After a TCC reset, opening ~/Desktop prompts once and lists files after Allow.
UX:
- Flow: open protected folder → system prompt → list; denied → inline message → "Open Privacy Settings" → System Settings › Privacy › Files and Folders
- Surface: content area (ContentUnavailableView), never an alert
- States: denied "Kamiro can't open this folder." / « Kamiro ne peut pas ouvrir ce dossier. » with "Open Privacy Settings" / « Ouvrir les réglages de confidentialité »
Status: doing
Built: purpose strings in English and French (InfoPlist.xcstrings); a closed folder shows "Kamiro can't open this folder." with Open Privacy Settings. Waits on the owner's manual check after a TCC reset.

## M2 Move files (0.2.0)

### S-011 Cut, copy and paste files
As the user, I cut (⌘X) or copy (⌘C) items and paste them (⌘V) into another folder; cut items look dimmed until pasted. ⌥⌘V moves copied items, like Finder.
Screens: cut-dimmed
Depends: S-002
Acceptance:
- [unit] Cut then paste moves; copy then paste copies; paste into the same folder makes "name copy", "name copy 2".
- [self] Cut items draw at half opacity until pasted or Escape.
- [self] ⌘X in a text field (rename, address bar) still cuts text.
- [unit] Copying files puts file URLs on the pasteboard so Finder and other apps can paste them.
Status: done
Built: Cut, Copy and Paste go through the responder chain (FileTable), so the Edit menu still edits text in a field; Edit › Move Items Here is ⌥⌘V. Test runs use a private pasteboard.

### S-012 Watch a transfer and cancel it
As the user, a long copy or move shows its progress with time left, and I can cancel it; nothing half-copied is left behind.
Screens: transfer-progress
Depends: S-011
Acceptance:
- [unit] Progress counts bytes up front; APFS clones finish at once and count as done.
- [unit] Cancel removes the partial copy and leaves sources untouched.
- [self] Several transfers queue in one popover from a toolbar progress button.
Status: done
Built: TransferEngine in KamiroKit (copyfile with COPYFILE_CLONE, bytes counted up front); a ring in the toolbar opens the transfers popover after half a second, each transfer with Stop.

### S-013 Decide on name conflicts
As the user, when a pasted item already exists, I choose Replace, Keep Both or Skip, with "Apply to All".
Screens: conflict-sheet
Depends: S-012
Acceptance:
- [unit] Keep Both names "name 2"; Replace moves the old one to the Trash, not deletes it.
- [self] The sheet shows both items' size and date.
Status: done
Built: the sheet shows both items' icon, size and date; Keep Both is the default button, Replace sends the old one to the Trash, Stop ends the transfer.

### S-014 Rename inline
As the user, I press Return (or F2) to rename the selected item in place; the name is selected without its extension.
Screens: rename
Depends: S-002
Acceptance:
- [self] Return/F2 starts; Return saves; Escape cancels; Tab moves to the next item.
- [unit] Illegal names (":" , empty, existing) show an inline error; changing an extension asks first.
Status: done
Built: Return renames (or opens with the setting on), F2 always renames; clicking elsewhere saves; a changed extension asks first, like the Finder.

### S-015 Make a new folder or file
As the user, I make a new folder (⇧⌘N) or a new file from a template here, and its name is ready to edit. Templates come in four groups, like PowerClick (docs/research/context-menu.md): Basic (Empty File, Text, Rich Text, Markdown), Data (JSON, XML, YAML, CSV), Web (HTML, CSS, JavaScript, TypeScript), Code (Python, Shell Script, Swift).
Screens: new-menu
Depends: S-014
Acceptance:
- [unit] "untitled folder", "untitled folder 2"; every template writes a valid file (JSON parses, shell script is executable with a shebang).
- [self] New File submenu in File menu, right-click on empty space and the toolbar.
Status: done
Built: New Folder (⇧⌘N) and New File in the File menu, the right-click menu and a + menu in the toolbar.

### S-016 Move to Trash or delete
As the user, I move items to the Trash (⌘⌫) or delete them right away (⌥⌘⌫) after a confirmation.
Screens: delete-confirm
Depends: S-011
Acceptance:
- [unit] Trash uses FileManager.trashItem and can be put back; Delete Immediately asks "Delete 3 Items Immediately?".
- [self] ⌫ alone trashes only when "Return opens items" is on (Explorer habit).
Status: done
Built: ⌘⌫ and ⌥⌘⌫ are menu shortcuts only while the list has the keyboard, so they still edit text in a field. Test runs trash into /tmp/Kamiro-trash.

### S-017 Undo file changes
As the user, ⌘Z undoes my last rename, move, copy, new item or trash, several levels deep; ⇧⌘Z redoes.
Depends: S-011, S-014, S-015, S-016
Acceptance:
- [unit] Undo per operation type, including a batch move as one step.
- [self] Edit menu shows "Undo Move of 3 Items".
Status: done
Built: one Undo stack for file changes in every window (FileUndo), each change recorded as moves and trashing (FileChange) so its undo has a redo.

### S-018 Drag and drop files
As the user, I drag items to a folder, a crumb, the sidebar or another app; same disk moves, another disk copies, ⌥ copies, ⌘ moves. Hovering a folder springs it open.
Screens: drag
Depends: S-012
Acceptance:
- [self] Drop on folder row, crumb, sidebar item; spring-loaded open after 0.7 s.
- [manual] Drag to and from Finder, Mail and the Desktop works both ways.
Status: doing
Built: drag out of the list, drop on folder rows, the list, crumbs and sidebar items; spring-loaded folder rows. Waits on the owner's drag to and from Finder, Mail and the Desktop.

## M3 Views (0.3.0)

### S-019 See folders as icons with thumbnails
As the user, I switch to icon view (⌘1) and see thumbnails for images, videos and PDFs, with an icon size slider in the status bar.
Screens: icons, icons-dark
Depends: S-002
Acceptance:
- [self] Thumbnails load only for visible items, from QLThumbnailGenerator, cached.
- [self] A 10,000-file folder scrolls smoothly (benchmark NSCollectionView vs LazyVGrid first).
Status: done
Built: View › as Icons (⌘1) or the toolbar's View menu. NSCollectionView, chosen without a LazyVGrid benchmark: SwiftUI's Table already hung on large folders (docs/research), and the self-test measures 60 scroll steps through 10,000 icons. Thumbnails come from QLThumbnailGenerator for items as they appear, in three size steps, cached; documents get a page edge. The icon size slider sits at the right of the status bar.

### S-020 Browse in columns
As the user, I switch to column view (⌘3) and browse a tree left to right, with a preview of the selected file in the last column.
Screens: columns
Depends: S-002
Acceptance:
- [self] Columns size to their longest name (up to a limit) and can be resized; arrows move across.
Status: done
Built: View › as Columns (⌘3). NSBrowser, item-based: columns start at the window's folder, the folder holding the selection becomes the window's folder (so cut, copy, paste and the status bar work as in the other views), columns size to their longest name between 160 and 360 pt and can be dragged wider, and a selected file gets a Quick Look preview with its kind, size and date. Rows show the icon as a text attachment (macOS 26 draws them with plain text cells), so renaming puts the plain name in the field.

### S-021 Choose and sort columns
As the user, I right-click the header to show columns (Date Created, Date Added, Tags, Extension, Comments) and drag them to reorder.
Screens: columns-menu
Depends: S-002
Acceptance:
- [unit] Columns and sort persist per folder, with a default for new folders.
Status: done
Built: Right-click the details header to show Date Created, Date Added, Extension, Tags or Comments; drag headers to reorder and edges to resize. Each folder keeps its view (mode, sort, columns, widths) in views.json beside the settings; folders never changed get the default, which View › Use as Defaults sets. Tags and Comments are read only for rows on screen and don't sort. Column view stays on while browsing in it.

### S-022 Group items
As the user, I group the list by Kind, Date Modified, Size or Name (View › Group By), with collapsible group headers.
Screens: grouped
Depends: S-021
Acceptance:
- [unit] Date groups: Today, Yesterday, Previous 7 Days, Previous 30 Days, then months.
Status: done
Built: View › Group By (None, Kind, Date Modified, Size, Name), in the details view. Each group gets a header with a chevron, its name and count; a click folds it. Date groups follow the Finder: Today, Yesterday, Previous 7 Days, Previous 30 Days, then this year's months, then years. Size groups go biggest first and use folder sizes once known (S-023). The grouping is saved with the folder's view; folded groups are not.

### S-023 See folder sizes
As the user, the Size column shows folders' sizes too, computed in the background and kept up to date.
Screens: browse
Depends: S-002
Acceptance:
- [unit] Sizes use allocated size, count hard links once, and cancel when I leave the folder.
- [self] Folders show "—" until computed, then the size; sorting by size works once computed.
Status: todo

### S-024 Show hidden files
As the user, I toggle hidden files (⇧⌘.) and see them dimmed.
Screens: hidden
Depends: S-002
Acceptance:
- [self] Dotfiles and hidden-flag items appear at half opacity; the choice is global.
Status: todo

## M4 Know your files (0.4.0)

### S-025 Read details in the inspector
As the user, I open the inspector (⌥⌘I) to see a preview and the selection's details: kind, size, dates, where, tags, dimensions or duration.
Screens: inspector, inspector-dark
Depends: S-002
Status: todo

### S-026 Open Properties
As the user, I press ⌘I (or ⌥↩) for a Properties window: name, where, size with item count, dates, permissions, Open With, locked, hidden.
Screens: properties
Depends: S-023
Status: todo

### S-027 Tag files
As the user, I add Finder tags from the right-click menu and see them in a Tags column and the sidebar's Tags section.
Screens: tags
Depends: S-021
Status: todo

### S-028 Filter this folder
As the user, I type in the toolbar search to filter the current folder by name as I type.
Screens: filter
Depends: S-002
Status: todo

### S-029 Search everywhere
As the user, I search This Mac or this folder and its subfolders with Spotlight, with Kind and Date filters, and open results in place.
Screens: search-results
Depends: S-028
Status: todo

## M5 Tabs and shortcuts (0.5.0)

### S-030 Use tabs
As the user, I open folders in tabs (⌘T, ⌘-double-click) and drag a tab out to a new window.
Screens: tabs
Depends: S-001
Status: todo

### S-031 Start from Home
As the user, the Home page shows my pinned folders, recent files and volumes with free space.
Screens: home
Depends: S-032
Status: todo

### S-032 Pin folders to the sidebar
As the user, I drag a folder to the sidebar or choose Pin to Sidebar; I reorder and unpin pins; I hide sidebar sections I don't use.
Screens: browse
Depends: S-001
Status: todo

### S-033 Right-click for everything
As the user, one right-click menu holds what I need: Open, Open With, Cut, Copy, Paste, Rename, Duplicate, New, Compress, Copy Path, Open in Terminal, Tags, Quick Look, Properties, Move to Trash.
Reference: PowerClick (docs/research/context-menu.md).
Screens: context-item, context-empty, context-image
Depends: S-011, S-015
Acceptance:
- [self] The menu follows the selection: empty space shows New and Paste; a file shows Open, Copy and Copy To; images and media add Convert; actions that don't apply are left out, not dimmed.
- [snap] Groups are separated, one level of submenus at most; no "Show more options".
Status: todo

### S-034 Copy a path and open a terminal here
As the user, I copy an item's path (⌥⌘C), or from a Copy submenu its name, name without extension, extension or parent folder path; and I open the current folder in Terminal (or Ghostty, iTerm) or the selection in my code editor (VS Code, Cursor, Zed, Xcode).
Depends: S-033
Status: todo

### S-035 Compress and extract
As the user, I compress items to a zip and extract a zip next to it.
Depends: S-012
Status: todo

### S-036 Open with another app
As the user, I pick an app from Open With, or Other…, and can make it the default for that kind.
Depends: S-033
Status: todo

### S-037 Eject volumes and connect to a server
As the user, I eject a volume from the sidebar and connect to an SMB or AFP server (⌘K).
Screens: connect-server
Depends: S-001
Status: todo

### S-044 New file from the clipboard
As the user, I choose New File from Clipboard and get a file whose type follows the clipboard: text, JSON, a table as CSV, a link as .webloc, an image as PNG.
Reference: PowerClick (docs/research/context-menu.md).
Depends: S-015
Status: todo

### S-045 Convert files
As the user, I right-click images to convert them (JPEG, PNG, HEIC, WebP, TIFF, GIF, ICNS), videos to MP4, GIF or audio, and images or PDFs to a smaller size for email; the result lands next to the original as a transfer with progress.
Reference: PowerClick (docs/research/context-menu.md).
Depends: S-033, S-012
Acceptance:
- [unit] Each image format round-trips with ImageIO; a video converts with AVFoundation; nothing leaves the Mac.
- [unit] Converted files never overwrite: "photo.png" becomes "photo.jpg", or "photo 2.jpg" if taken.
Status: todo

### S-046 Copy To and Move To
As the user, I copy or move the selection to a folder chosen from my pinned and recent folders, or Other….
Reference: PowerClick (docs/research/context-menu.md).
Depends: S-033, S-032
Status: todo

### S-047 Choose what the right-click menu shows
As the user, Settings › Menu lets me hide the actions and New File templates I never use.
Reference: PowerClick (docs/research/context-menu.md).
Depends: S-033, S-040
Status: todo

## M6 System and polish (1.0.0)

### S-038 Make Kamiro the default file browser
As the user, I turn on Settings › General › "Use Kamiro to reveal files", so "Show in Finder" in other apps opens Kamiro.
Screens: settings-general
Acceptance:
- [manual] After turning it on, "Show in Finder" from Safari's downloads opens Kamiro with the file selected; turning it off restores Finder.
Status: todo

### S-039 Open Kamiro from the terminal
As the user, I run `kamiro .` or `kamiro ~/file.txt` to open a folder or reveal a file; Settings installs the command.
Status: todo

### S-040 Settings
As the user, Settings has General (new window opens at, Return opens items, default browser, terminal app, code editor), Views (default view, columns, folders first), Sidebar and Menu.
Screens: settings-general, settings-views, settings-sidebar
Status: todo

### S-041 French
As the user, every screen reads in French when the Mac is in French, with a language choice in Settings.
Status: todo

### S-042 App icon
As the user, Kamiro has its own Liquid Glass icon, distinct from Finder's.
Status: todo

### S-043 Release 1.0
As the user, I download a notarized Kamiro from its public GitHub release (MIT, free) and it updates itself with Sparkle.
Acceptance:
- [live] The DMG from the GitHub release opens without a Gatekeeper warning; Sparkle finds the next version.
- [manual] README.md and README.fr.md credit explorer-macos; LICENSE is MIT with LICENSES/explorer-macos.txt beside it.
Status: todo

## Later
- Dual pane (side-by-side folders in one tab), with F5 copy / F6 move to the other pane.
- Batch rename with a live preview; rules from PowerClick (prefix, suffix, case, sequence, date).
- Gallery view.
- Workspaces (saved sets of tabs).
- Disk usage map of a folder.
- Browse inside archives as folders.
- Read QR codes and barcodes in images and PDFs (PowerClick).
- Transcribe audio and video on device (PowerClick).

## Dropped
- Remote servers (SFTP, S3, cloud accounts): ForkLift's ground.
- Folder sync and compare: out of scope for a Finder replacement.
- The Desktop: Finder keeps drawing it.
- Windows 11 look and colours: Kamiro looks like a Mac app.
- "Show more options" two-level right-click menu: one full menu instead.
