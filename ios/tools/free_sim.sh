#!/bin/bash
# Prints the UDID of an iPhone simulator nobody else is using, and boots it.
# Several worktrees may run tests at once; sharing a booted simulator makes their runs collide.
# Prefers the given model (default "iPhone 17 Pro"), then any other iPhone. Claiming = booting:
# `simctl boot` fails if another session booted the same device first, so we just try the next one.
set -euo pipefail

preferred="${1:-iPhone 17 Pro}"

candidates=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
preferred = sys.argv[1]
devices = [d for runtime, ds in json.load(sys.stdin)["devices"].items()
           if "iOS" in runtime for d in ds
           if d["state"] == "Shutdown" and d["name"].startswith("iPhone")]
devices.sort(key=lambda d: d["name"] != preferred)
print("\n".join(d["udid"] for d in devices))
' "$preferred")

for udid in $candidates; do
  if xcrun simctl boot "$udid" 2>/dev/null; then
    echo "$udid"
    exit 0
  fi
done

echo "No free iPhone simulator; create one with: xcrun simctl create 'Turbulence spare' 'iPhone 17 Pro'" >&2
exit 1
