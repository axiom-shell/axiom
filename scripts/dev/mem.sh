#!/usr/bin/env bash
#
# Reads one qs's memory, in MB: RSS, Private_Dirty, Anonymous and
# AnonHugePages (/proc/<pid>/smaps_rollup), the JS heap at its last GC
# (chunk memory, and what was live after the collection), and its threads,
# with the render threads (one QSGRenderThread per window that has drawn)
# counted apart. Baseline and how to run it: docs/dev/core/memory.md.
#
# The JS heap is only known when the shell logs its collections: start it
# with QT_LOGGING_RULES=qt.qml.gc.allocatorStats.debug=true in its
# environment (scripts/dev/nested.sh passes the environment through);
# otherwise those columns are "-".
#
# Usage: scripts/dev/mem.sh [-H] PID
#   PID   the qs process (pgrep -af 'qs -p'; a nested one is the newer)
#   -H    print the column names first

set -euo pipefail

header=0
if [[ "${1:-}" == "-H" ]]; then
  header=1
  shift
fi
pid="${1:-}"
if [[ ! "$pid" =~ ^[0-9]+$ || ! -r "/proc/$pid/smaps_rollup" ]]; then
  echo "usage: $0 [-H] PID  (a running qs: pgrep -af 'qs -p')" >&2
  exit 2
fi

if [[ $header -eq 1 ]]; then
  printf '%6s %6s %6s %6s %6s %6s %5s %5s\n' rss dirty anon huge js js_live thr render
fi

# smaps_rollup's kB values, as MB
read -r rss dirty anon huge < <(awk '
  /^Rss:/ { r = $2 } /^Private_Dirty:/ { d = $2 }
  /^Anonymous:/ { a = $2 } /^AnonHugePages:/ { h = $2 }
  END { printf "%d %d %d %d\n", r / 1024, d / 1024, a / 1024, h / 1024 }' "/proc/$pid/smaps_rollup")

threads=0 render=0
for comm in /proc/"$pid"/task/*/comm; do
  threads=$((threads + 1))
  [[ "$(<"$comm")" == QSGRenderThread ]] && render=$((render + 1))
done

# The last GC's "Allocated N bytes in M chunks" and "Regular item memory
# after GC: N", from the instance's log
read -r js live < <(qs log --pid "$pid" -r 'qt.qml.gc.allocatorStats.debug=true' 2>/dev/null |
  awk '
    /Allocated [0-9]+ bytes in/ { for (i = 1; i < NF; i++) if ($i == "Allocated") js = $(i + 1) }
    /Regular item memory after GC:/ { live = $NF }
    END {
      if (js == "") print "- -"
      else printf "%d %d\n", js / 1048576, live / 1048576
    }')

printf '%6s %6s %6s %6s %6s %6s %5s %5s\n' "$rss" "$dirty" "$anon" "$huge" "$js" "$live" "$threads" "$render"
