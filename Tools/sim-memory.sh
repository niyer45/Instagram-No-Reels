#!/bin/bash
# Prints the resident memory of the app and its WebKit processes on one simulator, with a total:
# one line per process ("Following", "WebContent", "Networking", "GPU"), RSS in MB.
# Usage: Tools/sim-memory.sh <simulator-udid>
# Simulator processes are host processes, so this is RSS as macOS sees it, not iOS's footprint
# (no jetsam limits apply); compare runs on the same machine only.
set -u
UDID="${1:?usage: Tools/sim-memory.sh <simulator-udid>}"
LAUNCHD=$(ps -A -o pid=,command= | grep "launchd_sim .*/Devices/$UDID/" | grep -v grep | awk '{print $1}' | head -n 1)
[ -n "$LAUNCHD" ] || { echo "simulator $UDID is not booted" >&2; exit 2; }
ps -A -o ppid=,rss=,command= | awk -v parent="$LAUNCHD" '
  $1 == parent && ($0 ~ /Following\.app\/Following/ || $0 ~ /com\.apple\.WebKit\./) {
    if ($0 ~ /Following\.app/) name = "Following"
    else { match($0, /com\.apple\.WebKit\.[A-Za-z]+/); name = substr($0, RSTART + 17, RLENGTH - 17) }
    printf "%-11s %7.1f MB\n", name, $2 / 1024; total += $2; count++
  }
  END { printf "%-11s %7.1f MB (%d processes)\n", "total", total / 1024, count }'
