#!/bin/bash
# Runs the checks from docs/DIRECTION.md §5 and prints one line per check:
#   node   the JavaScript tests (Tests/*.test.cjs)
#   swift  the pure Swift sources listed below compiled with Tests/*.swift, then run
#   build  the Debug simulator build (CODE_SIGNING_ALLOWED=NO); any compiler warning fails it
# Usage: Tools/check.sh [--no-build]
# Scratch output (logs, module cache, derived data) goes to $CHECK_TMP, default $TMPDIR/ig-check.
# Exits non-zero when any check fails. Needs only node, swiftc and xcodebuild.
set -u
cd "$(dirname "$0")/.." || exit 2

# The one place the Swift check's source list lives: app sources without UIKit/WebKit
# dependencies that Tests/*.swift exercise.
SWIFT_CHECK_SOURCES=(
  Sources/Filter/FollowingPolicy.swift
  Sources/Navigation/RouteClassifier.swift
  Sources/Navigation/RouteDecision.swift
  Sources/Support/SVGPath.swift
)

TMP="${CHECK_TMP:-${TMPDIR:-/tmp}/ig-check}"
mkdir -p "$TMP" || exit 2
BUILD=1
for arg in "$@"; do
  case "$arg" in
    --no-build) BUILD=0 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

failed=0
# report NAME STATUS DETAIL
report() {
  printf '%-6s %-4s %s\n' "$1" "$2" "$3"
  if [ "$2" != ok ] && [ "$2" != skip ]; then failed=1; fi
}
# node --test ends with "ℹ tests N", "ℹ pass N", "ℹ fail N" (older versions: "# tests N").
node_summary() { grep -E '^(ℹ|#) (tests|pass|fail) ' "$1" | sed -E 's/^(ℹ|#) //' | tr '\n' ' ' | sed 's/ $//'; }

# 1. Node tests
if node --test Tests/*.test.cjs >"$TMP/node.log" 2>&1; then
  report node ok "$(node_summary "$TMP/node.log")"
else
  report node FAIL "$(node_summary "$TMP/node.log") (log: $TMP/node.log)"
fi

# 2. Swift checks
if swiftc -module-cache-path "$TMP/module-cache" "${SWIFT_CHECK_SOURCES[@]}" Tests/*.swift \
     -o "$TMP/swift-checks" >"$TMP/swiftc.log" 2>&1 \
   && "$TMP/swift-checks" >"$TMP/swift-run.log" 2>&1; then
  warnings=$(grep -c 'warning:' "$TMP/swiftc.log")
  if [ "$warnings" -eq 0 ]; then
    report swift ok "$(tail -n 1 "$TMP/swift-run.log")"
  else
    report swift FAIL "$warnings warning(s) (log: $TMP/swiftc.log)"
  fi
else
  report swift FAIL "compile or run failed (logs: $TMP/swiftc.log, $TMP/swift-run.log)"
fi

# 3. Debug simulator build
if [ "$BUILD" -eq 1 ]; then
  if xcodebuild -project Following.xcodeproj -scheme Following -configuration Debug -sdk iphonesimulator \
       -destination 'generic/platform=iOS Simulator' -derivedDataPath "$TMP/derived-data" \
       CODE_SIGNING_ALLOWED=NO build >"$TMP/build.log" 2>&1; then
    warnings=$(grep -E ': warning:' "$TMP/build.log" | sort -u | wc -l | tr -d ' ')
    if [ "$warnings" -eq 0 ]; then
      report build ok "Debug simulator build, 0 warnings"
    else
      report build FAIL "$warnings warning(s) (log: $TMP/build.log)"
    fi
  else
    report build FAIL "$(grep -m 1 'error:' "$TMP/build.log") (log: $TMP/build.log)"
  fi
else
  report build skip "--no-build"
fi

exit "$failed"
