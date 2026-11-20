# Kamiro

Your files, the Finder way, with the habits of Windows File Explorer. Kamiro is a native Mac file manager that keeps Finder's macOS 26 look and adds what switchers miss: real cut and paste, an address bar you can type in, details columns, folder sizes, Properties, and a full right-click menu.

**Status:** early. Version 0.1.0 is the empty app; browsing comes in the next milestone. See [the stories](docs/STORIES.md).

[Download the latest version](https://github.com/matguitarist/Kamiro/releases/latest/download/Kamiro.dmg) (macOS 26 or later).

Lire en [français](README.fr.md).

## Build

```zsh
./build.sh --open     # builds, signs and installs ~/Applications/Kamiro.app, then opens it
swift test            # unit tests
```

## Credits

Kamiro takes ideas and some code from [explorer-macos](https://github.com/preslav-panayotov/explorer-macos) by Preslav Panayotov (MIT); see [docs/BORROWED.md](docs/BORROWED.md) and [LICENSES/explorer-macos.txt](LICENSES/explorer-macos.txt). Its right-click menu takes ideas from [PowerClick](https://powerclick.kilicov.dev/).

## License

[MIT](LICENSE).
