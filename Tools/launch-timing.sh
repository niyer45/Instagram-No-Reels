#!/bin/bash
# Measures launch-to-ready on a simulator with the DEBUG launch marks from
# Sources/Support/Diagnostics.swift (Caches/launch-timing.json, ms since didFinishLaunching;
# "process" is how long the process existed before that, large when iOS pre-warmed it).
# Usage: Tools/launch-timing.sh <simulator-udid> [warm-runs]
# Installs the Debug build from Tools/check.sh ($CHECK_TMP/derived-data, default
# $TMPDIR/ig-check) after uninstalling the app, so the first launch is a fresh-install cold
# launch; then relaunches warm-runs times (default 3). Prints one line per launch.
set -u
cd "$(dirname "$0")/.." || exit 2
UDID="${1:?usage: Tools/launch-timing.sh <simulator-udid> [warm-runs]}"
RUNS="${2:-3}"
BUNDLE=com.local.following
TMP="${CHECK_TMP:-${TMPDIR:-/tmp}/ig-check}"
APP="${APP:-$TMP/derived-data/Build/Products/Debug-iphonesimulator/Following.app}"
[ -d "$APP" ] || { echo "no Debug build at $APP; run Tools/check.sh first" >&2; exit 2; }

xcrun simctl bootstatus "$UDID" -b >/dev/null || exit 2
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
xcrun simctl uninstall "$UDID" "$BUNDLE" >/dev/null 2>&1
xcrun simctl install "$UDID" "$APP" || exit 1
DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data) || exit 1
FILE="$DATA/Library/Caches/launch-timing.json"

# launch LABEL: launches the app, waits up to 30 s for Home to be ready, prints the marks.
launch() {
  rm -f "$FILE"
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null || return 1
  for _ in $(seq 1 120); do
    if [ -f "$FILE" ] && grep -q 'home-ready' "$FILE"; then break; fi
    sleep 0.25
  done
  sleep 1.5 # let later marks (splash) land
  if [ -f "$FILE" ]; then
    # {"marks":[{"ms":12,"name":"scene"},...]} -> scene=12  ...
    printf '%-6s %s\n' "$1" "$(tr -d '{}[]"' <"$FILE" | sed -e 's/^marks://' -e 's/ms:\([0-9]*\),name:\([a-z-]*\)/\2=\1/g' -e 's/,/  /g')"
  else
    printf '%-6s %s\n' "$1" "no launch marks after 30 s"
  fi
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
  sleep 1
}

launch cold
for i in $(seq 1 "$RUNS"); do launch "warm$i"; done
