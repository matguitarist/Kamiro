#!/bin/zsh
# Runs the in-app self-test on the sample tree (tools/seed-tree.sh) with a fresh store in /tmp,
# in English and in French. Exit code 0 when every check passed in both.
# Usage: tools/selftest.sh          both languages
#        tools/selftest.sh fr       one language
set -u
here=${0:A:h}
app=~/Applications/Kamiro.app/Contents/MacOS/Kamiro
store=/tmp/Kamiro-self.json
result=0
langs=($@)
(( $#langs )) || langs=(en fr)
for lang in $langs; do
  rm -rf ~/Library/Saved\ Application\ State/com.mathieuares.kamiro.savedState
  "$here/seed-tree.sh" >/dev/null
  defaults delete com.mathieuares.kamiro.test >/dev/null 2>&1 || true
  rm -f $store ${store:r}.log ${store:r}.views.json
  print "== $lang"
  # A run that hangs counts as a failure after two minutes.
  APP_STORE=$store $app -ApplePersistenceIgnoreState YES -AppleLanguages "($lang)" --selftest &
  pid=$!
  ( sleep 120; kill $pid 2>/dev/null ) >/dev/null 2>&1 &
  watchdog=$!
  wait $pid || result=1
  kill $watchdog 2>/dev/null
done
exit $result
