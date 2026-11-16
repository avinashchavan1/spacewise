#!/bin/bash
# shoot <name> <wait> <args...>
W="$(cd "$(dirname "$0")" && pwd)"; APP="$W/dd/Build/Products/Debug/Spacewise.app/Contents/MacOS/Spacewise"; DEMO="$W/demo/Users/alex"
name="$1"; wait="$2"; shift 2; mkdir -p "$W/shots"
"$APP" -SpacewiseHome "$DEMO" -SpacewiseWindowSize 1280x800 -SpacewiseAppearance dark -ApplePersistenceIgnoreState YES -NSQuitAlwaysKeepsWindows NO "$@" > "$W/shots/$name.log" 2>&1 &
pid=$!; sleep "$wait"
id=$("$W/winpid" $pid) && screencapture -x -o -l"$id" "$W/shots/$name.png" && echo "captured $name $(sips -g pixelWidth -g pixelHeight "$W/shots/$name.png" | tail -2 | awk '{print $2}' | tr '\n' 'x')" || echo "FAILED $name"
kill $pid 2>/dev/null; wait $pid 2>/dev/null
