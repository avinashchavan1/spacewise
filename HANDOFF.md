# Spacewise — handoff

Read this first if you are picking up the project, human or Claude.

## What it is
A native macOS storage analyzer (SwiftUI, macOS 14+). It scans a disk or folder, shows where the space goes, and helps delete or organize files. The owner intends to publish it on the Mac App Store.

## State (as of 2026-11-15)
- Feature-complete v1.0. All screens work: Overview, Explore (treemap), Large Files, File Types, Duplicates, Cleanup, Organize, Settings.
- Verified on a real Mac by CI (`.github/workflows/build.yml`, runner `macos-15`, Xcode 16.4):
  - `swift test`: 19 engine tests pass.
  - The Release build compiles with **zero warnings**.
  - The `screenshots` job launches a Debug build, scans generated sample data and screenshots every screen in light and dark mode. Every screen renders correctly.
- **Not done yet:** it has never been installed or run on the owner's own Mac. That is the next step (see "Install locally").
- Not signed with a Developer ID or App Store certificate. The bundle id is still the placeholder `com.example.Spacewise`.

## Repo layout
```
Spacewise.xcodeproj        Xcode 16 project (file-system synchronized groups: new files in Spacewise/ are picked up automatically)
Spacewise/
  App/SpacewiseApp.swift   App entry, Window + Settings scenes, menu commands and shortcuts
  Core/                    Platform-independent engine, unit tested, no UI imports
    DiskScanner.swift      Multithreaded readdir+fstatat scanner (~900k files/s); hard links counted once; no symlink follow; skips iCloud placeholders
    FSNode.swift           Compact tree node; path is computed from parents; teardown() frees the tree
    ScanAnalysis.swift     One-pass totals per category plus largest files (heap)
    FileCategory.swift     Extension → category; location-aware (~/Library, caches → System & Caches)
    Treemap.swift          Squarified treemap layout and hit testing
    DuplicateFinder.swift  size → head/tail hash → full SHA-256
    CleanupRules.swift     Cleanup suggestions (caches, logs, Xcode, simulators, node_modules, installers, old downloads…)
    Organizer.swift        Plans "sort folder by type/month/year/extension" moves
  Model/AppModel.swift     @Observable @MainActor app state: scanning, cleanup list, trash, duplicates
  Model/FolderOrganizer.swift  Applies and undoes Organizer plans on disk
  Model/Volumes.swift      Mounted volumes and free space
  Support/                 Formatting, Finder icons cache, sandbox/bookmark access, category colours
  Support/DemoLaunch.swift DEBUG-only launch arguments used by the screenshot job (compiled out of Release)
  Views/                   SwiftUI screens
  Spacewise.entitlements   App Sandbox + user-selected read/write + app-scoped bookmarks
Tests/SpacewiseCoreTests   Engine tests (run with `swift test`, also works on Linux)
Package.swift              Only used to build and test Core/
scripts/                   Demo data, window capture, screenshot runner (used by CI)
AppStore/listing.md        App Store name, subtitle, description, keywords, privacy answers, review notes
docs/privacy.html          Privacy policy page (to be served by GitHub Pages)
```

## Build, test and install on a Mac
Needs Xcode 16 or later (`xcodebuild -version`).

```bash
swift test
xcodebuild -project Spacewise.xcodeproj -scheme Spacewise -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
rm -rf /Applications/Spacewise.app
cp -R build/Build/Products/Release/Spacewise.app /Applications/
open /Applications/Spacewise.app
```
This is an ad-hoc signed build. It runs on the machine that built it without Gatekeeper prompts.

Without Xcode, download the CI build instead: `gh run download --repo avinashchavan1/spacewise --name Spacewise-macOS`, then `ditto -xk Spacewise-macOS.zip /Applications && xattr -dr com.apple.quarantine /Applications/Spacewise.app`.

## Behaviour to know before "fixing" things
- **Sandboxed:** the app can only read folders the user picks in an open panel. "Scan Home Folder" therefore shows a panel first. This is intended (Mac App Store rule), not a bug. Picked folders are remembered as security-scoped bookmarks under *Recent*.
- Mail, Messages, Safari and similar folders need **Full Disk Access** (System Settings → Privacy & Security). The app links there.
- Removing files sends them to the Trash (items already in the Trash are deleted). A confirmation is on by default (Settings).
- Scanning `/` crosses onto the Data volume on purpose (it is firmlinked) and excludes `/System/Volumes`, `/Volumes`, `/dev`, `/net`.
- Screenshot/demo hooks: in a Debug build, `-SpacewiseScan <path> -SpacewiseTab <overview|explore|largeFiles|fileTypes|duplicates|cleanup|organize> -SpacewiseHome <path> -SpacewiseAppearance dark -SpacewiseWindowSize 1280x800`. See `scripts/screenshots.sh`.

## Remaining work, in order
1. Install and run on the owner's Mac (commands above). Scan Home and the whole disk (Macintosh HD), and try Full Disk Access on and off. Fix anything that misbehaves on real data.
2. GitHub Pages: repo Settings → Pages → Deploy from branch `main`, folder `/docs`. Privacy URL: `https://avinashchavan1.github.io/spacewise/privacy.html`.
3. Apple Developer Program ($99/yr), then in Xcode set the Team and a real bundle id (replace `com.example.Spacewise`), version and copyright.
4. App Store screenshots at 1280×800 or 2880×1800. CI shots are 1280×684 because the runner's screen is short, so use them only as drafts. Take real ones on the Mac with demo data: run `scripts/make-demo-data.sh ~/SpacewiseDemo/Users/alex`, then launch the Debug build with the flags above.
5. Product → Archive → Distribute App → App Store Connect. Paste `AppStore/listing.md`, then submit.

## Ideas not started
Menu bar extra with free-space glance; "scan whole disk" on first launch; exclude list in Settings; localized strings; Sparkle updates for a direct-download edition (remove the sandbox entitlement there).
