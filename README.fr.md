# Kamiro

Vos fichiers, à la manière du Finder, avec les habitudes de l’Explorateur de fichiers de Windows. Kamiro est un gestionnaire de fichiers natif pour Mac qui garde l’apparence du Finder de macOS 26 et ajoute ce qui manque à ceux qui viennent de Windows : un vrai couper-coller, une barre d’adresse où saisir un chemin, des colonnes de détails, la taille des dossiers, les Propriétés et un menu contextuel complet.

**État :** débuts. La version 0.1.0 est l’application vide ; la navigation arrive à la prochaine étape. Voir [les récits](docs/STORIES.md) (en anglais).

[Télécharger la dernière version](https://github.com/matguitarist/Kamiro/releases/latest/download/Kamiro.dmg) (macOS 26 ou plus récent).

Read in [English](README.md).

## Compiler

```zsh
./build.sh --open     # compile, signe et installe ~/Applications/Kamiro.app, puis l’ouvre
swift test            # tests unitaires
```

## Remerciements

Kamiro reprend des idées et du code d’[explorer-macos](https://github.com/preslav-panayotov/explorer-macos) de Preslav Panayotov (MIT) ; voir [docs/BORROWED.md](docs/BORROWED.md) et [LICENSES/explorer-macos.txt](LICENSES/explorer-macos.txt). Son menu contextuel s’inspire de [PowerClick](https://powerclick.kilicov.dev/).

## Licence

[MIT](LICENSE).
