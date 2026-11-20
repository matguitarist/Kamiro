#!/bin/zsh
# Builds the sample folder tree that snapshots and the self-test browse: /tmp/Kamiro-seed.
# Mixed files with fixed dates, folders, an app package, a hidden file, an empty folder,
# a folder Kamiro can't open, and a folder of 10,000 files.
set -eu
root=/tmp/Kamiro-seed
[[ -d $root/Locked ]] && chmod 755 $root/Locked
rm -rf $root
mkdir -p $root/{Projects/Kamiro/Sources,Projects/Website,Photos,Music,Empty,Locked,10k,Sample.app/Contents/MacOS}
cd $root
stamp() { touch -t "$1" "${@:2}" }
for n in 1 2 3 10 11 20; do mkfile -n $(( n * 37 ))k "Track $n.m4a"; done
for n in 1 2 12; do mkfile -n $(( n * 120 ))k "Invoice $n.pdf"; done
mkfile -n 2400k report.pdf
mkfile -n 5100k Song.m4a
mkfile -n 18m "Holiday Video.mov"
print "# Notes\n\nA folder tree for Kamiro's snapshots." > notes.md
print '{"name": "Kamiro", "version": 1}' > data.json
print "item,price\napples,3\npears,4" > budget.csv
print "Kamiro sample" > "A file with a very long name that does not fit in the name column at all.txt"
print "secret" > .hidden-notes
print "<plist version=\"1.0\"><dict/></plist>" > Sample.app/Contents/Info.plist
print "readme" > Projects/Kamiro/README.md
print "# Notes\n\nAn older copy." > Projects/notes.md
print "print(1)" > Projects/Kamiro/Sources/main.swift
mkfile -n 300k Photos/Beach.jpg Photos/Mountain.jpg
stamp 202611190930 Track*.m4a notes.md data.json
stamp 202611181415 Invoice*.pdf budget.csv
stamp 202611021000 report.pdf Song.m4a "Holiday Video.mov" A\ file*
stamp 202609010900 Projects/notes.md
stamp 202610150800 Projects Photos Music Empty Sample.app
python3 -I -c "
import os
os.chdir('10k')
for i in range(1, 10001): open(f'Photo {i}.jpg', 'w').close()
"
chmod 000 Locked
print "seeded $root"
