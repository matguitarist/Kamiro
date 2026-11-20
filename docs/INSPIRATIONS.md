# Inspirations

Kamiro is its own code. It is inspired by these projects; none of their code is copied or adapted.

- [explorer-macos](https://github.com/preslav-panayotov/explorer-macos) (MIT): Windows File Explorer habits on the Mac (cut and paste, an address bar you type in, New menu templates, Properties, compress and extract, a command to open a folder from the terminal).
- [PowerClick](https://powerclick.kilicov.dev/): the right-click menu (docs/research/context-menu.md).
- The Finder on macOS 26 for the look, and Windows 11 File Explorer for the habits (docs/research/file-managers.md).

## Checked 2026-11-20

Kamiro 1.0.1 was compared line by line with explorer-macos at 93ff69a (2026-10-07): 21 of about
1,370 lines match, all one-line SwiftUI and Foundation idioms (`CommandGroup(replacing: .newItem) {`,
`try? await Task.sleep(…)`). Where both do the same job, they do it differently: explorer-macos copies
with one recursive `copyfile` call and a progress callback, Kamiro walks the tree and copies file by
file with its own cancel and conflict answers; explorer-macos names copies "name - Copy", Kamiro
"name copy 2" like the Finder; the New File templates differ.

## Rule

Build features from their behaviour, not from their source. If code from another project is ever
copied or adapted, its licence goes in LICENSES/, its notice in a header comment of each file that
uses it, and a line here saying what and where.
