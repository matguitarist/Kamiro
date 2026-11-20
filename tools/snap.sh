#!/bin/zsh
# Snapshots of every page in light and dark, with seed data, on a fresh test store.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=all,settings tools/snap.sh
set -u
app=~/Applications/Kamiro.app/Contents/MacOS/Kamiro
store=/tmp/Kamiro-test.json
shots=/tmp/Kamiro-shots
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/com.mathieuares.kamiro.savedState
"${0:A:h}/seed-tree.sh" >/dev/null
# Seed data only fills an empty store, so start from nothing.
rm -f $store ${store:r}.log
rm -rf $shots
APP_STORE=$store APP_SEED=1 APP_SNAPSHOT=$shots $app
