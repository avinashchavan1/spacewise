# Spacewise

A native macOS app that shows what is using your disk space and helps you clean it up.

- **Overview** – every disk with used and free space, one-click scans of Home, Downloads, Documents and more, and a summary after each scan.
- **Explore** – a treemap of any folder next to a sorted list of its contents. Double-click a block to go inside it.
- **Large Files** – the biggest files on the disk, with type and size filters and search.
- **File Types** – a chart of space by type (videos, images, apps, archives, code…) and the largest files of each.
- **Duplicates** – exact copies, confirmed by comparing file contents (SHA-256), never by name.
- **Cleanup** – caches, logs, Xcode build data, simulators, package-manager caches, `node_modules`/`Pods`/`target` folders, old installers and old downloads, each marked *Safe* or *Review*.
- **Organize** – sort the loose files of a folder (e.g. Downloads) into subfolders by type, month, year or extension, with a preview first and Undo afterwards.

Everything you pick lands on one cleanup list shown at the bottom of the window. Removing sends items to the Trash, so nothing is deleted outright (except items that are already in the Trash).

## Requirements

- macOS 14 Sonoma or later
- Xcode 16 or later to build

## Build and run

1. Open `Spacewise.xcodeproj` in Xcode.
2. Select the **Spacewise** target → *Signing & Capabilities* → choose your Team, and change the bundle identifier from `com.example.Spacewise` to your own.
3. Press ⌘R.

Engine tests (scanner, treemap, duplicates, cleanup rules, organizer) run without Xcode:

```bash
swift test
```

## Performance

The scanner reads directories with `readdir` + `fstatat` on up to 8 threads instead of `FileManager` enumeration, and stores each item in a compact node. On a test machine it scanned 188,000 files in 0.2 s (about 900,000 files per second); analysis of the result takes about 0.15 s and a treemap layout about 1 ms. It counts allocated blocks (like the Finder's “size on disk”), counts hard links once, does not follow symbolic links, and does not download iCloud placeholders.

Lists are capped (largest 3,000 files, 1,000 rows per folder, 9,000 treemap blocks) so the interface stays responsive on disks with millions of files.

## Permissions and the App Store

The app is sandboxed (`Spacewise/Spacewise.entitlements`), which the Mac App Store requires:

- The user picks each folder or disk in an open panel; Spacewise stores a security-scoped bookmark so the folder appears under *Recent* and can be rescanned later.
- macOS-protected folders (Mail, Messages, Safari…) are only readable after the user grants **Full Disk Access** in System Settings → Privacy & Security. The app links there from the Overview and Settings.
- Folders that cannot be read are counted and reported, never silently treated as empty.

If you distribute outside the App Store instead (notarized download), you can remove the sandbox entitlement; the app then scans any location directly without asking. Keep Hardened Runtime on for notarization.

### Before publishing

- Set your bundle identifier, Team, version and copyright (target → *General* / *Build Settings*).
- Replace the placeholder app icon in `Spacewise/Assets.xcassets/AppIcon.appiconset` if you want your own.
- Test a full scan of Macintosh HD on a real Mac, including with Full Disk Access turned on and off.
- App Review asks apps that delete files to make removal clear and reversible: Spacewise confirms before removing (on by default in Settings) and uses the Trash.

## Project layout

```
Spacewise/
  App/        App entry point, menus and keyboard shortcuts
  Core/       Platform-independent engine: scanner, tree, analysis, treemap,
              duplicate finder, cleanup rules, organizer (covered by tests)
  Model/      App state (AppModel), volumes, folder organizing on disk
  Support/    Formatting, file icons, sandbox file access, category colours
  Views/      SwiftUI screens
Tests/        Engine tests (swift test)
Package.swift Swift package used only to build and test Core
```
