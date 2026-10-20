#!/bin/bash
# Installs the Debug build on a booted simulator and captures screenshots through the DEBUG
# launch hooks (Sources/Support/DebugLaunchOptions.swift): every tab live and on its skeleton,
# a pushed page, the failure state and the offline banner.
# Usage: Tools/simshots.sh <simulator-udid> [output-dir]
# The build comes from Tools/check.sh ($CHECK_TMP/derived-data, default $TMPDIR/ig-check) or $APP.
# WAIT (seconds, default 12) is how long live pages get to load before each capture.
set -u
cd "$(dirname "$0")/.." || exit 2
UDID="${1:?usage: Tools/simshots.sh <simulator-udid> [output-dir]}"
TMP="${CHECK_TMP:-${TMPDIR:-/tmp}/ig-check}"
OUT="${2:-$TMP/simshots}"
APP="${APP:-$TMP/derived-data/Build/Products/Debug-iphonesimulator/Following.app}"
WAIT="${WAIT:-12}"
BUNDLE=com.local.following
PUSHED_URL="https://www.instagram.com/instagram/"
[ -d "$APP" ] || { echo "no Debug build at $APP; run Tools/check.sh first" >&2; exit 2; }
mkdir -p "$OUT" || exit 2

xcrun simctl bootstatus "$UDID" -b >/dev/null || exit 2
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
xcrun simctl install "$UDID" "$APP" || exit 1

# shot NAME SECONDS [VAR=value ...]: launches with the given SHELL_* variables, waits, captures.
shot() {
  local name="$1" wait="$2"; shift 2
  local vars=()
  for pair in "$@"; do vars+=("SIMCTL_CHILD_$pair"); done
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
  env "${vars[@]}" xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null || { echo "launch failed: $name" >&2; return 1; }
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1 && echo "$OUT/$name.png"
}

for tab in home search activity profile; do
  shot "skeleton-$tab" 6 SHELL_TAB=$tab SHELL_SKELETON_PREVIEW=1
done
for tab in home search activity profile; do
  shot "tab-$tab" "$WAIT" SHELL_TAB=$tab
done
shot pushed-profile "$WAIT" SHELL_OPEN_URL="$PUSHED_URL"
shot failure-home 6 SHELL_FAILURE_PREVIEW=1
shot failure-pushed 7 SHELL_FAILURE_PREVIEW=1 SHELL_OPEN_URL="$PUSHED_URL"
shot offline-banner 6 SHELL_OFFLINE=60 SHELL_TAB=activity SHELL_SKELETON_PREVIEW=1
shot offline-banner-home 6 SHELL_OFFLINE=60 SHELL_SKELETON_PREVIEW=1
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
