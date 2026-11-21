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
- [self] ⌫ and ⌦ alone trash too (Explorer habit; owner, 2026-11-20).
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
- [self] Dragging anywhere on the edge between two columns resizes the left one; double-clicking it fits the names again; the preview column reaches the window's right edge; View › Hide Preview (⇧⌘P) takes it away.
Status: done
Built: View › as Columns (⌘3). NSBrowser, item-based: columns start at the window's folder, the folder holding the selection becomes the window's folder (so cut, copy, paste and the status bar work as in the other views), columns size to their longest name between 160 and 360 pt and can be dragged wider, and a selected file gets a Quick Look preview with its kind, size and date. Rows show the icon as a text attachment (macOS 26 draws them with plain text cells), so renaming puts the plain name in the field. Later: the whole edge between columns drags (NSBrowser only gave a small grip at the bottom), widths people choose are kept per folder while the window is open, the preview column fills the space to the right instead of leaving an empty strip, and View › Show/Hide Preview (⇧⌘P) turns it off.

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
Status: done
Built: After a folder loads, its subfolders and packages are measured one at a time off the main thread (allocated size, hard links once, hidden files included, other apps' containers in ~/Library left out so no permission prompts), and leaving the folder cancels it. Sizes show "—" until known (and stay "—" for folders Kamiro can't read); sorting and grouping by size use them, and so does the status bar's selection size. An FSEvents watch on the whole tree re-measures a subfolder when something inside it changes.

### S-024 Show hidden files
As the user, I toggle hidden files (⇧⌘.) and see them dimmed.
Screens: hidden
Depends: S-002
Acceptance:
- [self] Dotfiles and hidden-flag items appear at half opacity; the choice is global.
Status: done
Built: View › Show Hidden Files (⇧⌘.), and Hide Hidden Files to turn it off. One choice for every window, kept between launches; open windows (columns too) read their folders again. Dotfiles and items with the hidden flag show at half opacity in every view.

## M4 Know your files (0.4.0)

### S-025 Read details in the inspector
As the user, I open the inspector (⌥⌘I) to see a preview and the selection's details: kind, size, dates, where, tags, dimensions or duration.
Screens: inspector, inspector-dark
Depends: S-002
UX:
- Flow: ⌥⌘I or View › Show Inspector → a pane at the right of the list follows the selection → ⌥⌘I or View › Hide Inspector closes it; the choice is kept between launches
- Surface: inspector (details of the selection while working); a toolbar button (sidebar.right) at the right of the toolbar, asked for on 2026-11-20 (at the smallest size the address bar already moves into the toolbar's overflow, with or without it)
- States: nothing selected shows the folder itself; one item shows a preview, name, kind and Information; several show "3 items" and their total size; a folder's size is "—" until measured; facts that don't apply (Dimensions, Duration, Pages, Tags) are left out
- Words: "Show Inspector" / « Afficher l’inspecteur », "Hide Inspector" / « Masquer l’inspecteur », "Information" / « Informations », Kind, Size, Created, Modified, Added, Where, Tags, Dimensions, Duration, Pages
- Access: VoiceOver reads each label with its value; the path in Where shows in full on hover
Acceptance:
- [unit] Image dimensions, audio and video duration and PDF page counts are read from the file; other files have none.
- [self] ⌥⌘I shows the inspector with the selected item's name, kind, size and dimensions; nothing selected shows the folder; ⌥⌘I again hides it.
Status: done
Built: An inspector pane at the right of the window (⌥⌘I, View › Show Inspector), using SwiftUI's inspector: a Quick Look preview, name and kind, then Information (kind, size with folder sizes, dimensions, duration, pages, created, modified, added, tags, where). Nothing selected shows the folder; several items show the count and total size. Media facts are read in KamiroKit (ImageIO, AVFoundation, PDF). The details list now resizes its columns in reverse sequence (Name first, then the next ones), so the inspector never pushes columns out of sight. The self-test reads what the inspector shows through a small probe, since SwiftUI builds the pane's accessibility only for outside readers. A toolbar button (sidebar.right) shows and hides it too.

### S-026 Open Properties
As the user, I press ⌘I (or ⌥↩) for a Properties window: name, where, size with item count, dates, permissions, Open With, locked, hidden.
Screens: properties, properties-folder
Depends: S-023
UX:
- Flow: ⌘I, ⌥↩ (Windows' Alt+Enter), File › Properties or Properties in the right-click menu → a Properties window per selected item (the folder itself when nothing is selected), up to 10 → ⌘W closes it
- Surface: window (one item's full details, kept open beside the list; the inspector stays the quick look)
- States: a folder's size reads "Calculating…" until measured, then "193 KB on disk, 4 items"; a file shows "135 KB (138,240 bytes)"; Locked and Hidden apply at once, and a failure shows under the switch in words; apps and folders have no Opens With
- Words: window title "notes.md Properties" / « Propriétés de notes.md »; sections General, Opens With, Options, Sharing & Permissions; "Locked" / « Verrouillé », "Hidden" / « Masqué », "Read & Write" / « Lecture et écriture », "Read only" / « Lecture seule », "No Access" / « Aucun accès », "Everyone" / « Tout le monde »
- Access: every row reads label then value; the switches have their names; Tab moves between them
Acceptance:
- [unit] A folder's summary counts every item inside it, hidden ones too; permissions read as Read & Write, Read only, Write only or No Access for owner, group and everyone.
- [self] ⌘I and ⌥↩ open "Owl.jpg Properties"; a folder shows its size with the item count; Locked locks the file on disk and unlocking puts it back.
Status: done
Built: File › Properties (⌘I), ⌥↩ like Alt+Enter, and Properties at the bottom of the right-click menu open one window per selected item (up to 10; the folder when nothing is selected). It shows the icon, name and kind; General (size: bytes for files, size on disk and item count for folders, measured in the background; where; created; modified); Opens With (the default app, read only until S-036); Options (Locked and Hidden switches that apply at once, with the error in words if they fail); Sharing & Permissions (owner, group, everyone). Permissions and the folder summary live in KamiroKit with unit tests.

### S-027 Tag files
As the user, I add Finder tags from the right-click menu and see them in a Tags column and the sidebar's Tags section.
Screens: tags
Depends: S-021
UX:
- Flow: right-click › Tags › Red → the tag goes on every selected item (or comes off when they all have it) → the Tags column shows it; sidebar › Tags › Red → every item with that tag, from any folder → Back returns
- Surface: a submenu of the right-click menu; a sidebar section; the tag's items show in the window like a folder (a place that isn't a folder)
- States: a tag nothing has: "Nothing Is Tagged “Red”"; the menu checks a tag all selected items have, and shows a dash when only some have it; in a tag's items New Folder, New File and Paste are left out and columns show as details
- Words: "Tags" / « Tags », Red, Orange, Yellow, Green, Blue, Purple, Gray / Rouge, Orange, Jaune, Vert, Bleu, Violet, Gris (the Finder's names); address bar "Tags › Red"
- Access: each tag's color dot carries its name for VoiceOver; the tag names are words, never color alone
Acceptance:
- [unit] Tagging adds or removes one tag and keeps the others; a tag place survives as a URL; the Spotlight query escapes the name.
- [self] Right-click › Tags › Red tags every selected item and the Tags column shows it; sidebar › Red lists them, with nothing to make or paste there; choosing Red again takes it off.
Status: done
Built: Right-click › Tags lists the seven color tags (named in the Mac's language, as the Finder names them) and the selection's other tags, checked or dashed by how many selected items have them; choosing one tags every selected item, or untags them when they all have it. The sidebar has a Tags section; a tag opens a place that isn't a folder (a kamiro: URL, so Back, views and sorting work) listing every item with that tag from Spotlight, or by walking the test tree in test runs since Spotlight doesn't index /tmp. There, New Folder, New File, Paste and drops are left out and the column view shows as details. The address bar reads "Tags › Red". The Tags column came with S-021.

### S-028 Filter this folder
As the user, I type in the toolbar search to filter the current folder by name as I type.
Screens: filter
Depends: S-002
UX:
- Flow: ⌘F or a click in the toolbar's search field → type → the list keeps the items whose name holds every word, as you type → Escape or the field's ✕ clears it; going to another folder clears it too
- Surface: the toolbar search field (it narrows what's on screen, nothing opens)
- States: no match shows "No Items Match “xyz”" with Clear Filter; the status bar counts what's shown; a selected item the filter hides is unselected
- Words: prompt "Filter by Name" / « Filtrer par nom », Edit › "Find" / « Rechercher », "Clear Filter" / « Effacer le filtre »
- Access: the field is the search field VoiceOver knows; ⌘F reaches it from the list
Acceptance:
- [unit] A name matches when it holds every word typed, ignoring case and accents.
- [self] Typing "invoice" leaves the three invoices and the status bar says 3 items; "inv 2" leaves two; going to another folder clears the filter; ⌘F is Edit › Find.
Status: done
Built: The toolbar search field (SwiftUI searchable, prompt "Filter by Name") filters the folder as you type: an item stays when its name holds every word typed, ignoring case and accents (NameFilter in KamiroKit). Edit › Find (⌘F) puts the keyboard in it, Escape or ✕ clears it, and going to another folder clears it. The status bar counts what's shown; a selected item the filter hides is unselected; no match shows "No Items Match …" with Clear Filter. At the smallest window width the field folds into a button.

### S-029 Search everywhere
As the user, I search This Mac or this folder and its subfolders with Spotlight, with Kind and Date filters, and open results in place.
Screens: search-results
Depends: S-028
UX:
- Flow: type in the search field (it filters this folder) → Return searches this folder and its subfolders with Spotlight → the results show in the window with a scope bar: This Mac or “Folder”, Kind, Date → Open or double-click opens a result; Show in Enclosing Folder goes to its folder with it selected → Back returns to the folder, in one step however many filters changed
- Surface: the window itself (results are a place, like a folder); the scope bar sits above the list only while results show
- States: no results: the system's "No Results for “x”"; Spotlight runs off the main thread with "Loading…" past half a second; a selected result's folder shows in the status bar ("26 items — in ~/Projects"); New Folder, New File and Paste are left out
- Words: "This Mac" / « Ce Mac », Kind: "Any Kind", Folders, Documents, Images, Movies, "Music and Audio", PDFs, Apps; Date: "Any Date", Today, "Last 7 Days", "Last 30 Days", "This Year"; title "Searching “x”" / « Recherche de « x » »; "Show in Enclosing Folder" / « Afficher dans le dossier parent »
- Access: the scope bar's controls are standard pickers with labels; Return in the field searches, Escape clears
Acceptance:
- [unit] A search survives as a URL; its Spotlight query has every word, the kind and the date; walking a tree finds names in subfolders and honors Kind and Date.
- [self] Return after "notes" finds both notes.md in the folder and in Projects; Images with "o" leaves only pictures; Back returns to the folder in one step; Show in Enclosing Folder opens Projects with notes.md selected.
Status: done
Built: Return in the search field searches this folder and its subfolders with Spotlight. The results are a place (a kamiro:search URL), shown in the window like a folder with a scope bar above them: This Mac or the folder, Kind (folders, documents, images, movies, music and audio, PDFs, apps) and Date (today, 7 days, 30 days, this year). Changing the scope or a filter replaces the results without a new Back step, so Back returns to the folder in one step. The address bar reads "Search › “notes”", the status bar adds the selected result's folder, and Show in Enclosing Folder (File menu and right-click) opens its folder with it selected. Test runs walk the /tmp tree with the same rules, since Spotlight doesn't index /tmp. Results stop at 2,000.

## M5 Tabs and shortcuts (0.5.0)

### S-030 Use tabs
As the user, I open folders in tabs (⌘T, ⌘-double-click) and drag a tab out to a new window.
Screens: tabs
Depends: S-001
Acceptance:
- [self] ⌘T is File › New Tab and opens a tab in front, in the same window; ⌘-double-click on a folder opens it in a new tab, twice gives two tabs, and the first tab stays where it was; a tab moves out to a window of its own.
- [snap] The tab bar is the system's, under the toolbar, with its + button.
- [manual] Dragging a tab out of the bar makes a window; Window › Merge All Windows puts it back.
Status: done
Built: Tabs are the system's window tabs. File › New Tab (⌘T) and the tab bar's + open the start folder in a tab; ⌘-double-click a folder, or File › Open in New Tab (⌃⌘O), opens it in a tab of this window, and ⌥-double-click still opens a window. Each tab has its own history and view, and a second tab on a folder opens even when another tab already shows it. Show Tab Bar, Move Tab to New Window and Merge All Windows come from the system.

### S-031 Start from Home
As the user, the Home page shows my pinned folders, recent files and volumes with free space.
Screens: home
Depends: S-032
Status: done
Built: Home is a place (kamiro:home) at the top of the sidebar and in Go › Home (⇧⌘F); new windows open on it. Recent files are Spotlight's last-used files in the home folder (30 days, 10 shown; the sample tree in test runs). Volumes show free of total space with a bar.

### S-032 Pin folders to the sidebar
As the user, I drag a folder to the sidebar or choose Pin to Sidebar; I reorder and unpin pins; I hide sidebar sections I don't use.
Screens: browse
Depends: S-001
Status: done
Built: File › Pin to Sidebar (⌃⌘T) and the right-click menu pin selected folders (or the current folder); a folder dragged between pins is pinned there, one dropped on a pin moves into it. Drag pins to reorder; right-click a pin to Unpin. Settings › General › Show in Sidebar hides Home, Pinned, Locations or Tags. The home folder moved to Locations, as the glossary says.

### S-033 Right-click for everything
As the user, one right-click menu holds what I need: Open, Open With, Cut, Copy, Paste, Rename, Duplicate, New, Compress, Copy Path, Open in Terminal, Tags, Quick Look, Properties, Move to Trash.
Reference: PowerClick (docs/research/context-menu.md).
Screens: context-item, context-empty, context-image
Depends: S-011, S-015
Acceptance:
- [self] The menu follows the selection: empty space shows New and Paste; a file shows Open, Copy and Copy To; images and media add Convert; actions that don't apply are left out, not dimmed.
- [snap] Groups are separated, one level of submenus at most; no "Show more options".
Status: done
Built: One right-click menu that follows what's under the pointer. Items get Open, Open With (default app first, then the others, then Other…), Open in New Tab (folders), Quick Look, Cut, Copy, Copy Path, Paste, Duplicate (⌘D), Rename (one item), Move to Trash, Tags, Pin to Sidebar, Open in Terminal (one folder), Eject (a disk in /Volumes) and Properties; empty space gets Paste, New Folder, New File, Open in Terminal, Copy Path and Properties. Disks on the Home page and in the sidebar right-click to Open, Open in New Tab, Open in Terminal, Rename… (when the disk allows it), Copy Path, Properties and Eject (not the startup disk); a disk's Properties shows its format, capacity, available and used space without walking it. Pins and recent files on Home get their own menus. Copy To and Convert come with S-046 and S-045; Compress with S-035; more terminals and the Copy submenu with S-034.

### S-034 Copy a path and open a terminal here
As the user, I copy an item's path (⌥⌘C), or from a Copy submenu its name, name without extension, extension or parent folder path; and I open the current folder in Terminal (or Ghostty, iTerm) or the selection in my code editor (VS Code, Cursor, Zed, Xcode).
Depends: S-033
Status: done
Built: Copy Path is Edit › Copy Path (⌥⌘C) too, for the selection or, with nothing selected, the folder on screen; the right-click menu shows the shortcut. A Copy Info submenu beside it copies the name, the name without extension, the extension or the parent folder's path, one line per item; the extension choices are left out for items that have none. Open in Editor: the code editor picked in Settings › General › Code Editor (VS Code and its forks VSCodium, Cursor and Windsurf; Zed, Sublime Text, Nova, BBEdit, TextMate, CotEditor, MacVim, Emacs; Xcode, the JetBrains IDEs and Android Studio; among those installed, the first installed until one is picked) opens folders and text files from the right-click menu, and empty space gets Open Folder in <editor>. The terminal part came with S-059.

### S-035 Compress and extract
As the user, I compress items to a zip and extract a zip next to it.
Depends: S-012
Status: done
Built: Right-click (or File) › Compress “name” / Compress N Items makes “name.zip” (“report.zip” for “report.pdf”: a file's extension is dropped, a folder keeps its whole name) or “Archive.zip” next to the items, numbered when taken, with ditto like the Finder. A zip offers Extract Here: a lone top-level item comes out as itself, several in a folder named after the archive, never over an existing name. Both run in the transfers popover with a moving bar and Stop, build in a staging folder on the same disk so a stopped or failed job leaves nothing, select what they made, and Undo takes it away.

### S-036 Open with another app
As the user, I pick an app from Open With, or Other…, and can make it the default for that kind.
Depends: S-033
Status: done
Built: Open With came with S-033. Holding ⌥ in the right-click menu turns it into Always Open With: the app picked opens the files and becomes the default for their kinds. Other… has an Always Open With checkbox. Properties › Opens With is a picker of the apps for that file, with Change All…, which asks “Open every “JPEG image” file with Preview?” before making it the default for the whole Mac, Finder included.

### S-037 Eject volumes and connect to a server
As the user, I eject a volume from the sidebar and connect to an SMB or AFP server (⌘K).
Screens: connect-server
Depends: S-001
Status: done
Built: Disks that can be ejected show ⏏ at the end of their sidebar row (Eject was already in their right-click menu, S-033). Go › Connect to Server… (⌘K) opens a sheet: an address (a bare name means smb://; afp://, nfs://, https:// for WebDAV, ftp:// and a Windows \\server\share work too), the last ten servers (right-click to remove one), and Connect. macOS asks for the name and password itself (NetFS, keychain), and the share opens in the window once mounted; failures say so in the sheet and the log.

### S-044 New file from the clipboard
As the user, I choose New File from Clipboard and get a file whose type follows the clipboard: text, JSON, a table as CSV, a link as .webloc, an image as PNG.
Reference: PowerClick (docs/research/context-menu.md).
Depends: S-015
Status: done
Built: New File from Clipboard is in File, the toolbar's + menu, and the right-click menu on empty space when the clipboard holds something it can use. A table copied from Numbers or Excel (or tab-separated text) becomes CSV, an image becomes PNG, a lone web link a .webloc, JSON a .json, any other text a .txt; files on the clipboard are left to Paste. The file is named “untitled” (numbered when taken), ready to rename, and Undo takes it away.

### S-045 Convert files
As the user, I right-click images to convert them (JPEG, PNG, HEIC, WebP, TIFF, GIF, ICNS), videos to MP4, GIF or audio, and images or PDFs to a smaller size for email; the result lands next to the original as a transfer with progress.
Reference: PowerClick (docs/research/context-menu.md).
Depends: S-033, S-012
Acceptance:
- [unit] Each image format round-trips with ImageIO; a video converts with AVFoundation; nothing leaves the Mac.
- [unit] Converted files never overwrite: "photo.png" becomes "photo.jpg", or "photo 2.jpg" if taken.
Status: done
Built: Right-click › Convert lists what fits the whole selection. Pictures: JPEG, PNG, HEIC, TIFF, GIF and Icon (ICNS), leaving out the format they're already in (WebP is read but only offered where ImageIO can write it, which macOS 26 can't), and Smaller for Email (1600 pixels, JPEG). Videos: MP4 Video, Animated GIF (the first 30 seconds, 10 frames a second, 480 pixels) and Audio Only (M4A). PDFs, alone or with pictures: Smaller for Email (images as JPEG, optimized for screen). Each file is a job in the transfers popover with Stop, made in a staging folder so a stopped one leaves nothing, lands next to the original as “photo.jpg” (“photo 2.jpg” when taken) or “Guide (smaller).pdf”, gets selected, and Undo takes it away. ImageIO, AVFoundation and PDFKit only: nothing leaves the Mac.

### S-046 Copy To and Move To
As the user, I copy or move the selection to a folder chosen from my pinned and recent folders, or Other….
Reference: PowerClick (docs/research/context-menu.md).
Depends: S-033, S-032
Status: done
Built: Right-click › Copy To and Move To list the pinned folders, then Recent Folders (the last eight folders anything was pasted, dropped, copied or moved into), then Other… (a folder panel starting here, with New Folder, and Copy Here / Move Here). The folder the items are already in, the items themselves and folders inside them are left out, and so are folders that are gone. They run as transfers: same-name questions, progress, Stop and Undo like a paste.

### S-047 Choose what the right-click menu shows
As the user, Settings › Menu lets me hide the actions and New File templates I never use.
Reference: PowerClick (docs/research/context-menu.md).
Depends: S-033, S-040
Status: todo

### S-048 More native formats
As the user, Convert also offers the formats macOS writes on its own: AVIF, JPEG 2000, BMP and ICO (Windows icon), so the common cases need nothing installed.
Depends: S-045
Acceptance:
- [unit] Each new format round-trips with ImageIO; ICO keeps 16 to 256 pixels; formats this Mac can't write are left out, not shown dimmed.
Status: done
Built: Convert on pictures also offers AVIF, JPEG 2000, BMP and Windows Icon (ICO, 16 to 256 pixels in one file), in the order JPEG, PNG, HEIC, AVIF, WebP, JPEG 2000, TIFF, GIF, BMP, Icon (ICNS), Windows Icon (ICO). Each shows only where ImageIO on this Mac can write it; macOS 26 writes all four.

### S-049 Optional tools
As the user, Settings › Tools lists the free command-line tools Kamiro can use (cwebp, ffmpeg, ImageMagick), shows which are installed with their version, and for the others the Homebrew line to copy. Native first: nothing here is needed, nothing is bundled or downloaded by Kamiro, and a tool's actions appear only once it is installed.
Depends: S-045
Acceptance:
- [unit] A tool is found in /opt/homebrew/bin, /usr/local/bin or /opt/local/bin (an app's PATH has none of them); a missing or broken tool counts as not installed.
- [self] With no tools, Settings › Tools shows three “brew install …” lines with Copy, and Convert has no tool-only formats.
Status: done
Built: Settings › Tools lists cwebp, FFmpeg and ImageMagick with what each adds. A tool found in /opt/homebrew/bin, /usr/local/bin or /opt/local/bin that answers its version question shows a check and its version (its path on hover); a missing or broken one shows its “brew install …” line with Copy. Tools are looked for at launch and when the tab opens, and Check Again looks again. A footer says they're optional and Kamiro never downloads one, with a link to Homebrew. Conversions can now name the tool they need, and Convert leaves them out until it's found; none needs one yet (S-050 to S-052). Test runs look in /tmp/Kamiro-tools.

### S-050 WebP with cwebp
As the user, with cwebp installed (brew install webp), Convert › WebP turns pictures into WebP, and an animated GIF into an animated WebP (gif2webp).
Depends: S-049
Acceptance:
- [unit] With a fake cwebp in a test folder, the arguments are right and the result lands as “photo.webp”, or “photo 2.webp” when taken; Stop ends the tool and leaves nothing.
Status: done
Built: Once cwebp is found, Convert on pictures offers WebP (macOS reads WebP but can't write it). The picture is drawn the way it's shown, then cwebp writes it at quality 90; an animated GIF goes through gif2webp, installed with it, and stays animated. Like every conversion it's made in a staging folder: Stop ends the tool and leaves nothing, and a tool that fails says why in the transfers popover (its last line).

### S-051 Any video with ffmpeg
As the user, with ffmpeg installed, Convert also takes videos macOS can't open (WebM, MKV, AVI, FLV), offers WebM as a target, and makes animated GIFs with ffmpeg's palette for better colors, with a progress bar from its time readout.
Depends: S-049
Acceptance:
- [unit] ffmpeg's "time=" lines become a fraction of the length; without ffmpeg, WebM and MKV get no Convert.
Status: done
Built: With FFmpeg found, Convert also takes WebM, MKV, AVI, FLV, WMV, OGV and any other movie AVFoundation can't open (AVI counts as one: the codecs inside rarely play on macOS), to MP4 (H.264 and AAC), Animated GIF and Audio Only, and offers WebM Video (VP9 and Opus) for every video. Animated GIFs come from FFmpeg whenever it's there, with a palette made from the video, the same first 30 seconds at 10 frames a second and 480 pixels. MP4 and Audio Only of what macOS plays stay with AVFoundation. FFmpeg jobs show a real progress bar and the time left, from its Duration and time= readouts.

### S-052 More pictures with ImageMagick
As the user, with ImageMagick installed, Convert also takes pictures macOS can't open (SVG, XCF, EPS and other rare formats) and turns them into the usual ones.
Depends: S-049
Acceptance:
- [unit] An SVG becomes a PNG of its own size with magick; formats ImageIO reads stay native even when ImageMagick is there.
Status: done
Built: With ImageMagick found, Convert also takes SVG, XCF (layers merged), EPS, AI, PCX, XPM, XBM, SGI, Sun raster, MNG, MIFF and DPX pictures: magick draws the first page at its own size on a transparent background, then every picture conversion runs on that as usual (WebP too, with cwebp). EPS and AI also need Ghostscript (brew install ghostscript); without it the conversion fails and says so.

### S-053 Compress to a name and place
As the user, with several items selected, I choose Compress To… and name the archive and pick its folder.
Depends: S-035
Acceptance:
- [unit] The archive gets the chosen name and folder; one already there (the save panel asked) goes to the Trash.
Status: done
Built: Right-click › Compress To… (with two or more items) opens a save panel on the items' folder with “Archive.zip” ready to rename; the archive builds like Compress, with progress, Stop and Undo.

### S-054 Network in the sidebar
As the user, the sidebar's Network section shows the servers I'm connected to, the file servers on my network, and Connect to Server….
Depends: S-037, S-032
Acceptance:
- [unit] Servers found with Bonjour (SMB and AFP) merge by name, SMB first, and become addresses NetFS mounts, accents and spaces included.
- [self] Network is a sidebar part that Settings › General › Show in Sidebar can hide; hidden, mounted servers go back under Locations.
Status: done
Built: Network sits between Locations and Tags: mounted servers (with ⏏), servers found nearby with Bonjour (macOS asks once for local network access; test runs never look), then Connect to Server…. Clicking a found server connects to it like ⌘K (smb://Name._smb._tcp.local) and opens it.

### S-055 Browse a server like \\server on Windows
As the user, I click a server and see its shares as folders; opening one mounts it and goes in. The sidebar lists servers, not their shares, unless I ask for them.
Depends: S-054
Acceptance:
- [unit] smbutil's list keeps Disk shares only (no IPC$ or admin shares ending in $); a mounted share is found by its server under any spelling (Bonjour name, .local, bare name).
- [self] smb://server opens a page of its shares as folders, named after the server; a share not mounted yet only offers Open.
Status: done
Built: Clicking a server under Network, or typing smb://server or \\server in the address bar, opens its page: its shares as folders, listed with macOS's smbutil as guest or with the keychain's password (never asking). Opening a share mounts it with NetFS (macOS asks for a password when needed) and goes in; mounted shares open at once, and their size is never measured across the network. A server that won't list its shares shows Connect As… (macOS's own dialogs) and Try Again. Network lists servers only: found nearby, or connected by address; ⏏ on a server disconnects all its shares. Settings › General › Show in Sidebar › Connected Shares lists them under their server again. Opening a server connects all its shares in the background (Settings › General › Servers, on by default): only the first may ask for a password, the others use the keychain's. Listing retries on a fresh session, then as guest, since right after a disconnect the old session refuses.

### S-056 Pick an icon for a server or disk
As the user, I right-click a server or disk in the sidebar and pick its icon (network, server, NAS, PC, Mac, laptop, cloud, disk), so my cloud mounts and my Windows PC look like what they are.
Depends: S-054
Acceptance:
- [unit] WebDAV shares and cloud storage mounted by a tool (macFUSE, FUSE-T, rclone's local NFS) show a cloud on their own; a picked icon is kept for a server under any spelling and for a share wherever it mounts; Automatic forgets the pick.
- [self] A picked icon shows on the row and survives a reload; Automatic brings back the usual one.
Status: done
Built: Right-click a server, share or disk in the sidebar › Icon: Automatic (named after the icon it would show), then Network, Server, NAS, PC, Mac, Laptop, Cloud, Internal Disk and External Disk. Servers keep their pick by name, shares by server and share, disks by UUID. Servers got a right-click menu (Open, Icon, Disconnect). Shares no SMB or AFP server owns (WebDAV, NFS, cloud mounts) now list under Network on their own; before, they showed nowhere in the sidebar.

### S-057 iCloud Drive and sync folders
As the user, I open iCloud Drive and my sync apps' folders (Google Drive, OneDrive, Dropbox…) from the sidebar and see them like the Finder shows them: iCloud Drive at the top of its path, with each app's folder named after its app.
Depends: S-032
Acceptance:
- [unit] iCloud Drive and each folder in ~/Library/CloudStorage are a top of their path; an app's folder (its container's Documents) is inside iCloud Drive, named after the app; only apps that keep documents there show; sync folders are named after their app ("GoogleDrive-name@example.com" is Google Drive).
- [self] iCloud Drive and Google Drive show in the sidebar on the test home (under Cloud since S-060); Go › iCloud Drive is ⇧⌘I; iCloud Drive lists its items and the apps' folders; Up from an app's folder goes to iCloud Drive; an app's folder can't be cut, renamed or trashed.
- Surface: sidebar rows under Cloud (S-060), the Go menu, the path
Status: done
Built: Locations lists iCloud Drive (when it's on) and each sync app's folder after the home folder; Go › iCloud Drive (⇧⌘I). iCloud Drive's page adds each app's folder that holds documents (Numbers, Obsidian…), named by macOS; the path reads "iCloud Drive › Numbers", Up goes from an app's folder to iCloud Drive, and iCloud Drive and sync folders are a top like a disk. App folders leave out Cut, Duplicate, Move To, Rename and Move to Trash, as in the Finder. Test runs use a home in /tmp/Kamiro-home (tools/seed-tree.sh).

### S-058 Cloud status and downloads
As the user, I see which files in iCloud Drive or a sync folder are only in the cloud, downloading or uploading, and I download them or remove their download from the right-click menu.
Depends: S-057
Acceptance:
- [unit] A conflict shows first, then downloading, uploading, only in the cloud, else downloaded; a cloud folder never changed shows the Cloud Status column after Name.
- [self] The test home's statuses (from an attribute) show in the column; Download Now and Remove Download follow the status and change it; folders outside the cloud read no status.
- Performance: the status keys cost about 1 ms an item (a plain listing 0.01 ms), so they are read only in cloud folders, after the list shows, 100 at a time.
Status: done
Built: In iCloud Drive and sync folders, a narrow Cloud Status column (a cloud header) after Name shows the Finder's icons: only in the cloud, downloading, uploading, conflict; downloaded shows none. The icon view puts the same badge at the icon's corner, and the inspector has a Cloud Status row. Right-click › Download Now and Remove Download, on files by their status and on folders always. While something moves, statuses are read again every 2 seconds. Not in the column view yet.

### S-060 A Cloud section in the sidebar
As the user, I find iCloud Drive, my sync apps' folders (Google Drive, OneDrive, Dropbox…) and cloud storage mounted as a disk (WebDAV, rclone) together under their own Cloud heading, apart from my disks.
Depends: S-057, S-056
Acceptance:
- [unit] Cloud disks go under Cloud, servers under Network, the rest under Locations; a hidden part's rows go to Locations.
- Surface: the sidebar's Cloud section between Locations and Network; Settings › General › Show in Sidebar › Cloud
Status: done
Built: Cloud lists iCloud Drive, each sync app's folder by name, then cloud disks (a WebDAV server moves there from Network). Hidden in Settings, they go back under Locations. The section is left out when there is nothing in it.

### S-061 Convert sound files
As the user, I right-click songs and recordings to convert them to M4A, MP3, WAV, FLAC, AIFF or Apple Lossless, and turn a video into a QuickTime movie or an MP3 of its sound.
Depends: S-045, S-051
Acceptance:
- [unit] WAV, AIFF, FLAC and Apple Lossless keep the source's rate, channels and depth (24 bits stays 24); AAC and Apple Lossless .m4a files are told apart by their codec; MP3, and sound files macOS can't open (WMA, APE, Opus…), take FFmpeg, which keeps the tags.
- [self] A WAV's Convert offers M4A (AAC), FLAC, AIFF and Apple Lossless, and no MP3 without FFmpeg; Convert › FLAC makes “Tone.flac” beside it.
Status: done
Built: Right-click › Convert on sound files offers M4A (AAC), MP3, WAV, FLAC, AIFF and Apple Lossless (ALAC), leaving out the one they're already in. macOS makes M4A (AVFoundation, 256 kbps-class AAC, tags kept) and WAV, AIFF, FLAC and ALAC (Core Audio, with a progress bar). With FFmpeg found, MP3 (LAME, VBR quality 2) shows, sound files macOS can't open (WMA, APE, Opus, Ogg, WavPack, DSD…) convert too, and WAV, FLAC, AIFF and ALAC go through FFmpeg so the tags and cover art come along. Videos add QuickTime Movie, and Audio Only (MP3) with FFmpeg, after a separator under Audio Only (M4A). Movies and sound files with no type on this Mac (MKV or WMA with no app that declares them) are still recognized by their extension.

## M6 System and polish (1.0.0)

### S-038 Make Kamiro the default file browser
As the user, I turn on Settings › General › "Use Kamiro to reveal files", so "Show in Finder" in other apps opens Kamiro.
Screens: settings-general
Acceptance:
- [manual] After turning it on, "Show in Finder" from Safari's downloads opens Kamiro with the file selected; turning it off restores Finder.
Status: todo

### S-039 Open Kamiro from the terminal
As the user, I run `kamiro .` or `kamiro ~/file.txt` to open a folder or reveal a file; Settings installs the command.
Status: done
Built: Settings › General › Other Apps › Command Line installs a small zsh script as /usr/local/bin/kamiro (macOS asks for an administrator's password when that folder isn't writable), updates one written for another copy of Kamiro, removes it, and leaves alone a kamiro it didn't write. `kamiro` with no path opens the folder you're in; each folder opens in a new window, each file shows selected in its folder, and a path that doesn't exist is named on stderr with exit 1. The same path serves any folder or file another app sends (Open With, a drop on the Dock icon): launched for it, Kamiro uses its first window instead of opening a second.

### S-040 Settings
As the user, Settings has General (new window opens at, Return opens items, default browser, terminal app, code editor), Views (default view, columns, folders first), Sidebar and Menu.
Screens: settings-general, settings-views, settings-sidebar
Status: todo
Progress (2026-11-21): Sidebar has its own tab (parts to show, Connected Shares, connect all shares). General has Folders (new windows open on Home, the home folder, Desktop, Documents, Downloads or a folder chosen with Other…, new tabs too, a folder that's gone opens Home; new folders open as Details, Icons or Columns; Recent Files on Home), Keyboard, Open With (Terminal, Code Editor) and Language. Still to do: default browser (S-038), a Views tab once columns and folders first join the default view, Menu.

### S-041 French
As the user, every screen reads in French when the Mac is in French, with a language choice in Settings.
Status: done

### S-042 App icon
As the user, Kamiro has its own Liquid Glass icon, distinct from Finder's.
Status: done

### S-043 Release 1.0
As the user, I download a notarized Kamiro from its public GitHub release (MIT, free) and it updates itself with Sparkle.
Acceptance:
- [live] The DMG from the GitHub release opens without a Gatekeeper warning; Sparkle finds the next version.
- [manual] README.md and README.fr.md name explorer-macos and PowerClick as inspirations (docs/INSPIRATIONS.md); LICENSE is MIT.
Status: done

### S-059 Choose the terminal
As the user, I pick which terminal Open in Terminal uses (Terminal, Ghostty, iTerm, Warp, Hyper, kitty, Alacritty, WezTerm), among those installed.
Acceptance:
- [unit] Apple's Terminal is always offered; a chosen terminal that was removed falls back to it; terminals that take a folder on their command line get it there.
Status: done
Built: Settings › General › Terminal, a picker with each installed terminal's icon. Terminal, Ghostty, iTerm, Warp and Hyper open the folder like a document; kitty, Alacritty and WezTerm start a new instance with the folder as an argument. The menus name the chosen app: "Open in Ghostty" on a folder, pin or disk, "Open Ghostty Here" on empty space.

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
