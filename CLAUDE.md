# Kamiro

A native macOS file manager in SwiftUI that looks like Finder on macOS 26 and works like
Windows File Explorer: cut and paste, an address bar you can type in, details columns,
folder sizes, Properties, and a full right-click menu. Brief in docs/BRIEF.md, stories in
docs/STORIES.md (the source for the "Kamiro Roadmap" project in Thimble).

Shared rules for my Mac apps (build and check, design rules, skills, git):
@~/.claude/mac-app-conventions.md

Shared rules for how every project is laid out and named:
@~/.claude/project-layout.md

## Layout

- `Sources/Kamiro/` the app. `App.swift` has the window, menus, and the database location.
- `Sources/KamiroKit/` rules and data logic with no SwiftUI. Tests in `Tests/KamiroKitTests/`.
- `Package.swift` a Swift package. There is no Xcode project.
- `build.sh` builds, signs, and installs `~/Applications/Kamiro.app`.
- Release: `tools/release.sh <version>` (settings in `release.conf`, version in `Info.plist.in`). Use the mac-release skill.
- `Icon/AppIcon.icon` the app icon, an Icon Composer file (JSON plus SVG layers). `build.sh` compiles it with `tools/make_icon.sh`; `tools/icon_review.sh` renders every look into one PNG.
- `docs/` the brief, research, glossary, user stories, and INSPIRATIONS.md (explorer-macos, PowerClick: ideas only, no code; if code is ever adapted, follow its Rule).

## Checks specific to this app

- `APP_SNAPSHOT_MIN=1 tools/snap.sh` shoots the window at its smallest size.
- Never test against the real settings in `~/Library/Application Support/Kamiro/`, and never move, rename or delete real files from a test: file operations run on a folder tree in /tmp.
