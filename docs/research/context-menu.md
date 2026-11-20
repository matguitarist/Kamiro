# Right-click menu reference: PowerClick

Research for Kamiro, S-033 and the stories around it. Done 2026-11-19. Owner's pick as the reference for Kamiro's right-click menu.
Source: [V](https://powerclick.kilicov.dev/) and [V](https://powerclick.kilicov.dev/macos-right-click-menu). Ideas only: no text, icons or code taken.

PowerClick is a Finder Sync extension ($9.99 once, Mac App Store) that adds a submenu to Finder's right-click menu. Kamiro owns its menu, so these go straight into it, grouped, with no submenu for the app's name.

## What it offers
- **New File** (Basic, Data, Web, Code): Empty File, Text, Rich Text, Markdown, JSON, XML, YAML, CSV, HTML, CSS, JavaScript, TypeScript, Python, Shell Script, Swift.
- **New File from Clipboard**: the type follows the clipboard (JSON → .json, table → .csv, link → .webloc, image → .png).
- **Convert**: images (JPEG, PNG, HEIC, AVIF, TIFF, GIF, BMP, WebP, ICO, ICNS), video (MP4, GIF, audio only), audio (AAC, ALAC, FLAC, WAV), documents and PDF, Markdown.
- **Compress for**: Email (25 MB), Discord (10 MB), Half Size.
- **Copy info**: Path, Name, Name Without Extension, Extension, Parent Folder Path, Size, Dates, Image Dimensions.
- **Copy To, Move To**, cut and move here.
- **Batch Rename**: prefix, suffix, replace spaces, case changes (lower, UPPER, Title, kebab, snake), date prefix, sequence, trim, remove special characters.
- **Open in Editor**: VS Code, Cursor, Zed, any installed editor.
- **Read QR and barcodes** in images and PDFs (with a link check); **Transcribe** audio and video on device (macOS 26).
- **Undo** last move or trash.
- Menu Editor: show only the actions you use. Actions the Mac can't run are hidden, not dimmed.
- Context-aware: empty space → New File; a file → Copy Path, Open in Editor, Copy To, Move To; media → Convert, Compress; several files → Batch Rename.

## Decisions for Kamiro
1. One right-click menu, context-aware like PowerClick: actions that don't apply to the selection are left out, not dimmed (S-033).
2. New File templates in four groups, code included (S-015 grows from 4 templates to PowerClick's set), plus New File from Clipboard (S-044).
3. Copy submenu with path, name, name without extension, parent path and the like (S-034).
4. Open in Editor beside Open in Terminal, with the editor picked in Settings (S-034, S-040).
5. Convert images with ImageIO and video/audio with AVFoundation, all on device (S-045); Compress for Email in the same story.
6. Copy To / Move To with a folder picker of recent and pinned folders (S-046).
7. Menu editor in Settings › Menu to hide actions (S-047).
8. Batch Rename stays in Later; QR reading and transcription go to Later.
