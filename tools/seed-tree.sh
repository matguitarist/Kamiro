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
print "flagged" > "Flagged Hidden.txt"
chflags hidden "Flagged Hidden.txt"
print "<plist version=\"1.0\"><dict/></plist>" > Sample.app/Contents/Info.plist
print "readme" > Projects/Kamiro/README.md
print "# Notes\n\nAn older copy." > Projects/notes.md
print "print(1)" > Projects/Kamiro/Sources/main.swift
# Real pictures and a PDF, so the icon view has thumbnails to show (S-019).
pics="/Library/User Pictures"
picture() { if [[ -f "$pics/$1" ]]; then sips -s format $3 -Z 512 "$pics/$1" --out "$2" >/dev/null; else mkfile -n 300k "$2"; fi }
picture Animals/Parrot.heic Photos/Beach.jpg jpeg
picture Animals/Zebra.heic Photos/Mountain.jpg jpeg
picture Animals/Owl.heic Owl.jpg jpeg
picture Flowers/Lotus.heic Lotus.png png
python3 -I -c "
text = b'BT /F1 28 Tf 72 700 Td (Kamiro Guide) Tj ET'
objs = [b'<< /Type /Catalog /Pages 2 0 R >>', b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
        b'<< /Length %d >>stream\n' % len(text) + text + b'\nendstream',
        b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>']
out, offsets = b'%PDF-1.4\n', []
for i, o in enumerate(objs, 1):
    offsets.append(len(out)); out += b'%d 0 obj\n' % i + o + b'\nendobj\n'
xref = len(out)
out += b'xref\n0 %d\n0000000000 65535 f \n' % (len(objs) + 1) + b''.join(b'%010d 00000 n \n' % o for o in offsets)
out += b'trailer << /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (len(objs) + 1, xref)
open('Guide.pdf', 'wb').write(out)
"
stamp 202611190930 Track*.m4a notes.md data.json
stamp 202611181415 Invoice*.pdf budget.csv
stamp 202611021000 report.pdf Song.m4a "Holiday Video.mov" A\ file*
stamp 202609010900 Projects/notes.md
stamp 202611171200 Owl.jpg Lotus.png Guide.pdf Photos/*.jpg
stamp 202610150800 Projects Photos Music Empty Sample.app
python3 -I -c "
import os
os.chdir('10k')
for i in range(1, 10001): open(f'Photo {i}.jpg', 'w').close()
"
chmod 000 Locked
# A home with iCloud Drive, two apps' folders, an app folder with nothing in it, and a sync app's
# folder (S-057, S-058). Test runs read each item's cloud status from its com.mathieuares.kamiro.cloud
# attribute, since nothing here is really in the cloud; no attribute means downloaded.
home=/tmp/Kamiro-home
rm -rf $home
lib=$home/Library
md="$lib/Mobile Documents"
drive="$md/com~apple~CloudDocs"
mkdir -p "$drive/Projects" "$md/com~apple~Numbers/Documents" "$md/iCloud~md~obsidian/Documents/Vault" \
  "$md/com~apple~mail/Documents" "$lib/CloudStorage/GoogleDrive-someone@example.com/My Drive"
print "Milk, eggs" > "$drive/Shopping.txt"
mkfile -n 2400k "$drive/Scan.pdf"
mkfile -n 900k "$drive/Slides.key"
print "# Plan" > "$drive/Projects/Plan.md"
mkfile -n 300k "$md/com~apple~Numbers/Documents/Budget.numbers"
print "# Vault" > "$md/iCloud~md~obsidian/Documents/Vault/Index.md"
print "Shared notes" > "$lib/CloudStorage/GoogleDrive-someone@example.com/My Drive/Notes.txt"
xattr -w com.mathieuares.kamiro.cloud notDownloaded "$drive/Scan.pdf"
xattr -w com.mathieuares.kamiro.cloud uploading "$drive/Slides.key"
xattr -w com.mathieuares.kamiro.cloud notDownloaded "$lib/CloudStorage/GoogleDrive-someone@example.com/My Drive/Notes.txt"
stamp 202611181415 "$drive"/*(N) "$drive/Projects/Plan.md"
print "seeded $root and $home"
