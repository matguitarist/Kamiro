# Borrowed from explorer-macos

Kamiro takes ideas and some code from [explorer-macos](https://github.com/preslav-panayotov/explorer-macos) by Preslav Panayotov, MIT licensed. Any file that copies or adapts its code keeps this notice in a header comment, and the app's About window and README credit it.

```
MIT License — Copyright (c) Preslav Panayotov
Permission is hereby granted, free of charge, … (full text in LICENSES/explorer-macos.txt)
```

| Kamiro part | From explorer-macos | How |
| --- | --- | --- |
| Transfer engine (S-012) | TransferEngine.swift: copyfile with CLONE, COPYFILE_QUIT cancel | Adapt; add pre-counted bytes, queue, conflict prompt, cleanup on cancel |
| Cut and paste (S-011) | ExplorerState.swift clipboard; "name - Copy" naming | Adapt; Mac naming "name copy", "name copy 2" like Finder |
| Undo (S-017) | ExplorerState.swift undo stack (rename, move, copy, delete, create) | Adapt onto UndoManager |
| New file templates (S-015) | FileActions.swift New menu (Text, RTF, Markdown, HTML) | Adapt |
| Compress / extract (S-035) | FileActions.swift | Adapt |
| Right-click menus (S-033) | ContextMenus.swift item list | Ideas only; one full menu, no "Show more options" |
| Terminal command (S-039) | Resources/explorermac, CLIInstaller.swift | Adapt as `kamiro` |
| Tests | Tests/ExplorerTests (file ops, undo, grouping) | Port the cases |
| Feature list | docs/FEATURES.md | Checklist for parity |

Not taken: the Windows 11 palette and icons, LazyVStack lists (slow on big folders), the single-folder DispatchSource watcher, ad-hoc signing.
