#!/bin/bash
# Launches a Debug build on sample data and captures every screen.
# Usage: scripts/screenshots.sh <Spacewise.app> <output dir>
set -uo pipefail
APP="$1"; OUT="$2"
BIN="$APP/Contents/MacOS/Spacewise"
DEMO="$HOME/SpacewiseDemo/Users/alex"
mkdir -p "$OUT"
scripts/make-demo-data.sh "$DEMO"
swiftc -O scripts/capture-window.swift -o /tmp/findwindow
system_profiler SPDisplaysDataType | grep -i resolution || true

shoot() { # shoot <name> <seconds> <extra args...>
  local name="$1" wait="$2"; shift 2
  pkill -x Spacewise 2>/dev/null; sleep 1
  "$BIN" -SpacewiseHome "$DEMO" -SpacewiseWindowSize 1280x800 \
         -ApplePersistenceIgnoreState YES -NSQuitAlwaysKeepsWindows NO "$@" > "$OUT/$name.log" 2>&1 &
  local pid=$!
  sleep "$wait"
  if ! kill -0 $pid 2>/dev/null; then echo "::error::Spacewise exited early on $name"; cat "$OUT/$name.log"; return 1; fi
  osascript -e 'tell application "System Events" to set frontmost of (first process whose unix id is '$pid') to true' 2>/dev/null || true
  sleep 1
  local id; id=$(/tmp/findwindow Spacewise) || { screencapture -x "$OUT/$name-fullscreen.png"; echo "::warning::no window for $name"; return 1; }
  screencapture -x -o -l"$id" "$OUT/$name.png" && echo "captured $name"
}

fail=0
shoot 01-overview-empty 6 || fail=1
shoot 02-overview      10 -SpacewiseScan "$DEMO" -SpacewiseTab overview || fail=1
shoot 03-explore       10 -SpacewiseScan "$DEMO" -SpacewiseTab explore || fail=1
shoot 04-explore-folder 10 -SpacewiseScan "$DEMO" -SpacewiseTab explore -SpacewiseFocus "$DEMO/Library" || fail=1
shoot 05-large-files   10 -SpacewiseScan "$DEMO" -SpacewiseTab largeFiles || fail=1
shoot 06-file-types    10 -SpacewiseScan "$DEMO" -SpacewiseTab fileTypes || fail=1
shoot 07-cleanup       10 -SpacewiseScan "$DEMO" -SpacewiseTab cleanup -SpacewiseCollectSafe YES || fail=1
shoot 08-duplicates    16 -SpacewiseScan "$DEMO" -SpacewiseTab duplicates || fail=1
shoot 09-organize      8  -SpacewiseTab organize -SpacewiseOrganize "$DEMO/Downloads" || fail=1
shoot 10-explore-dark  10 -SpacewiseScan "$DEMO" -SpacewiseTab explore -AppleInterfaceStyle Dark || fail=1
shoot 11-cleanup-dark  10 -SpacewiseScan "$DEMO" -SpacewiseTab cleanup -AppleInterfaceStyle Dark || fail=1
pkill -x Spacewise 2>/dev/null
ls -la "$OUT"
exit $fail
