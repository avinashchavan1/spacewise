#!/bin/bash
# Creates a realistic sample home folder for automated screenshots.
# Usage: scripts/make-demo-data.sh <directory>
set -euo pipefail
H="$1"
rm -rf "$H"
mk() { # mk <path> <megabytes>
  mkdir -p "$(dirname "$H/$1")"
  head -c $(( $2 * 1024 * 1024 )) /dev/urandom > "$H/$1"
}
old() { touch -t 202501150930 "$H/$1"; }

# Media
mk "Movies/Iceland Road Trip.mov" 420
mk "Movies/Wedding Highlights.mp4" 310
mk "Movies/Screen Recordings/Keynote rehearsal.mov" 160
mk "Movies/Screen Recordings/Bug repro.mov" 48
for i in $(seq 1 14); do mk "Pictures/2026 Summer/IMG_$((4100 + i)).HEIC" $(( 3 + i % 5 )); done
for i in $(seq 1 8); do mk "Pictures/Portfolio/Shot_$i.jpg" $(( 6 + i % 4 )); done
mk "Pictures/Portfolio/Poster final.psd" 140
mk "Music/Recordings/Podcast episode 12.wav" 95
mk "Music/Recordings/Demo vocals.aiff" 60
for i in $(seq 1 6); do mk "Music/Albums/Track $i.m4a" $(( 7 + i )); done

# Documents
mk "Documents/Taxes 2025.pdf" 4
mk "Documents/Thesis/Thesis draft.docx" 12
mk "Documents/Thesis/Dataset.csv" 85
mk "Documents/Presentations/Q3 Review.key" 70
mk "Documents/Budget.numbers" 3
mk "Documents/Backups/Photos export.zip" 230

# Downloads: installers, old files, loose files for Organize, and duplicates
mk "Downloads/Xcode_16.4.xip" 380
mk "Downloads/Docker.dmg" 160
mk "Downloads/Figma-installer.dmg" 85
mk "Downloads/conference-talk.mp4" 120; old "Downloads/conference-talk.mp4"
mk "Downloads/old-project-assets.zip" 140; old "Downloads/old-project-assets.zip"
mk "Downloads/invoice-0423.pdf" 1
mk "Downloads/boarding-pass.pdf" 1
mk "Downloads/team-photo.jpg" 5
mk "Downloads/notes.txt" 1
mk "Downloads/song-preview.mp3" 8
cp "$H/Movies/Wedding Highlights.mp4" "$H/Downloads/Wedding Highlights (1).mp4"
cp "$H/Movies/Wedding Highlights.mp4" "$H/Desktop/Wedding Highlights copy.mp4" 2>/dev/null || { mkdir -p "$H/Desktop"; cp "$H/Movies/Wedding Highlights.mp4" "$H/Desktop/Wedding Highlights copy.mp4"; }
cp "$H/Pictures/Portfolio/Poster final.psd" "$H/Desktop/Poster final.psd"
mk "Desktop/Screenshot 2026-11-02.png" 4

# Caches, logs, developer data
mk "Library/Caches/com.apple.Safari/Cache.db" 210
mk "Library/Caches/com.spotify.client/Data/storage" 340
mk "Library/Caches/com.tinyspeck.slackmacgap/Cache/data" 120
mk "Library/Logs/DiagnosticReports/archive.log" 40
mk "Library/Developer/Xcode/DerivedData/Spacewise-abcdef/Build/index" 520
mk "Library/Developer/Xcode/iOS DeviceSupport/iPhone16,1 18.5/Symbols/dyld" 260
mk "Library/Developer/CoreSimulator/Devices/7F3A-iPhone-16/data/container" 300
mk ".npm/_cacache/content-v2/sha512/blob" 150
mk "Library/Application Support/Notes/NoteStore.sqlite" 30

# Code projects with dependency folders
mk "Developer/web-app/package.json" 1
mk "Developer/web-app/src/index.ts" 1
mk "Developer/web-app/node_modules/next/dist/bundle.js" 180
mk "Developer/web-app/node_modules/react-dom/cjs/react-dom.js" 40
mk "Developer/ios-app/Podfile" 1
mk "Developer/ios-app/Pods/Firebase/Firebase.framework.bin" 210
mk "Developer/cli-tool/Cargo.toml" 1
mk "Developer/cli-tool/target/debug/cli-tool" 260

mk ".Trash/Old export.mov" 190
echo "Demo home ready: $(du -sh "$H" | cut -f1)"
