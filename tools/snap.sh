#!/bin/zsh
# Snapshots of every page in light and dark, with seed data, on a fresh test store.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=all,settings tools/snap.sh
#        APP_LANGUAGE=en tools/snap.sh   (default: the Mac's language)
set -u
app=~/Applications/Kamiro.app/Contents/MacOS/Kamiro
# Test runs (the smallest-size shots especially) must not change the real window's saved size.
frameKey="NSWindow Frame browser-AppWindow-1"
savedFrame=$(defaults read com.mathieuares.kamiro "$frameKey" 2>/dev/null)
restoreFrame() {
  if [[ -n $savedFrame ]]; then defaults write com.mathieuares.kamiro "$frameKey" -string "$savedFrame"
  else defaults delete com.mathieuares.kamiro "$frameKey" 2>/dev/null; fi
}
trap restoreFrame EXIT
store=/tmp/Kamiro-test.json
shots=/tmp/Kamiro-shots
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/com.mathieuares.kamiro.savedState
"${0:A:h}/seed-tree.sh" >/dev/null
# Seed data only fills an empty store, so start from nothing.
rm -f $store ${store:r}.log ${store:r}.views.json
rm -rf $shots
lang=()
[[ -n ${APP_LANGUAGE:-} ]] && lang=(-AppleLanguages "($APP_LANGUAGE)")
APP_STORE=$store APP_SEED=1 APP_SNAPSHOT=$shots $app $lang
