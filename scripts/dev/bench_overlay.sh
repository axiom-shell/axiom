#!/usr/bin/env bash
#
# Times the live overlay: opening it, then switching to each page given, in
# order. For each step it prints how long the IPC call blocked (what was
# built synchronously; a no-op call is ~25 ms) and the pages built during
# it and the wait after, as the overlay logs them (OverlayPage: "Overlay page
# N built in X ms"; a streamed grid; and anything BuildQueueManager built
# that alone took over a frame), then closes the overlay.
#
# Usage: scripts/dev/bench_overlay.sh [-w SECONDS] [-n CYCLES] [-p PID] [--mem] [PAGE...]
#   PAGE      a view type or a page's name, as `axiom ipc overlay page` takes
#             (default: just open and close)
#   -w        seconds to wait after each step (default 1.5)
#   -n        run the open, pages, close cycle this many times (default 1)
#   -p        the qs to drive and read (a nested one: scripts/dev/nested.sh),
#             through its own daemon (the AXIOM_SOCKET and AXIOM_DAEMON_PID
#             in its environment); default the live shell
#   --mem     the memory reading (scripts/dev/mem.sh) before the first cycle
#             and after each; needs -p

set -euo pipefail

wait_s=1.5
cycles=1
pid=''
mem=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  -w)
    wait_s="$2"
    shift
    ;;
  -n)
    cycles="$2"
    shift
    ;;
  -p)
    pid="$2"
    shift
    ;;
  --mem) mem=1 ;;
  *) break ;;
  esac
  shift
done
if [[ $mem -eq 1 && -z "$pid" ]]; then
  echo "--mem needs -p PID (measure a nested shell: docs/dev/core/memory.md)" >&2
  exit 2
fi
repo="$(cd "$(dirname "$0")/../.." && pwd)"
export LC_ALL=C.UTF-8
axiom=(axiom)
if [[ -n "$pid" ]]; then
  env_of() { tr '\0' '\n' <"/proc/$pid/environ" | sed -n "s/^$1=//p"; }
  axiom=("/proc/$(env_of AXIOM_DAEMON_PID)/exe" --socket "$(env_of AXIOM_SOCKET)")
fi

pattern='Overlay (page [0-9]+ built|modules streamed) in|Built .* in [0-9]+ ms'
built() {
  if [[ -n "$pid" ]]; then
    qs log --pid "$pid" 2>/dev/null | grep -E --color=never "$pattern" | sed 's/^.*qml: //' || true
  else
    "$repo/scripts/log.sh" --debug -g "$pattern" | sed 's/^.*qml: //'
  fi
}
overlay() {
  "${axiom[@]}" ipc overlay "$@" >/dev/null 2>&1
}

step() {
  local before after start end
  before=$(built | wc -l)
  start=$(date +%s%N)
  overlay "$@"
  end=$(date +%s%N)
  sleep "$wait_s"
  after=$(built)
  printf '%-28s ipc %5d ms\n' "$*" $(((end - start) / 1000000))
  tail -n +"$((before + 1))" <<<"$after" | sed 's/^/    /'
}

if [[ $mem -eq 1 ]]; then
  "$repo/scripts/dev/mem.sh" -H "$pid" | sed '1s/^/memory        /; 2s/^/before        /'
fi
for ((cycle = 1; cycle <= cycles; cycle++)); do
  step open
  for page in "$@"; do
    step page "$page"
  done
  step close
  if [[ $mem -eq 1 ]]; then
    printf '%-14s%s\n' "cycle $cycle" "$("$repo/scripts/dev/mem.sh" "$pid")"
  fi
done
