#!/usr/bin/env bash
#
# Reads one qs's memory, in MB: RSS, Private_Dirty, Anonymous and
# AnonHugePages (/proc/<pid>/smaps_rollup), the JS heap at its last GC
# (chunk memory, and what was live after the collection), and its threads,
# with the render threads (one QSGRenderThread per window that has drawn)
# counted apart, and gpu: the window buffers, layers and captures the PID
# holds in VRAM/GTT, which RSS doesn't see (a cost is rss + gpu). Baseline
# and how to run it: docs/dev/core/memory.md.
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
  printf '%6s %6s %6s %6s %6s %6s %5s %5s %6s\n' rss dirty anon huge js js_live thr render gpu
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

# GPU memory (DRM fdinfo, kB as MB): per DRM descriptor drm-total-vram +
# drm-total-gtt (amdgpu), or every drm-total-* region for a driver with
# neither (i915/xe); a client's dup'd descriptors repeat its totals, so each
# drm-pdev + drm-client-id counts once. "-" when the PID has no DRM descriptor.
gpu=$({ cat /proc/"$pid"/fdinfo/* 2>/dev/null || true; } | awk '
  function flush() {
    if (drv != "" && !((pdev SUBSEP cid) in seen)) {
      seen[pdev SUBSEP cid] = 1
      found = 1
      total += (hasvg ? vg : other)
    }
    drv = pdev = cid = ""; vg = other = hasvg = 0
  }
  /^pos:/ { flush() }
  /^drm-driver:/ { drv = $2 }
  /^drm-pdev:/ { pdev = $2 }
  /^drm-client-id:/ { cid = $2 }
  /^drm-total-(vram|gtt)/ { vg += $2; hasvg = 1 }
  /^drm-total-/ { other += $2 }
  END { flush(); if (found) printf "%d\n", total / 1024; else print "-" }')

printf '%6s %6s %6s %6s %6s %6s %5s %5s %6s\n' "$rss" "$dirty" "$anon" "$huge" "$js" "$live" "$threads" "$render" "$gpu"
