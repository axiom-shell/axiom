#!/usr/bin/env bash
# Read the axiom shell's log without the noise: `axiom log`, trimmed.
#
# By default: only warnings/errors (and INFO lines) since the last config
# reload, with colour codes stripped. A clean reload prints just the
# "Reloading configuration..." / "Configuration Loaded" pair.
#
#   scripts/log.sh            since last reload, no debug output
#   scripts/log.sh --debug    include console.log/debug output
#   scripts/log.sh --all      whole log, not just since the last reload
#   scripts/log.sh -f         follow live (combine with --debug)
#   scripts/log.sh -g PATTERN only lines matching PATTERN (grep -E)
#   scripts/log.sh --problems only WARN/ERROR messages (a continuation line
#                             joined to its message), identical ones
#                             collapsed with a count: `(×12)`
#
# The binary is $AXIOM_BIN (set in the shell), else `axiom` on PATH, else
# ~/.local/bin/axiom; `axiom log` picks the shell the daemon runs.

set -euo pipefail

axiom=${AXIOM_BIN:-$(command -v axiom || echo "${XDG_BIN_HOME:-$HOME/.local/bin}/axiom")}
args=(log)
since_reload=1
follow=0
pattern=''
problems=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  -d | --debug) args+=(--debug) ;;
  -a | --all) since_reload=0 ;;
  -f | --follow) follow=1 ;;
  -p | --problems) problems=1 ;;
  -g | --grep)
    pattern="$2"
    shift
    ;;
  -h | --help)
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "unknown option: $1" >&2
    exit 1
    ;;
  esac
  shift
done

strip() { sed -u 's/\x1b\[[0-9;]*m//g'; }
filter() { if [[ -n "$pattern" ]]; then grep -E --color=never --line-buffered -- "$pattern" || true; else command cat; fi; }

if [[ $follow -eq 1 ]]; then
  "$axiom" "${args[@]}" -f 2>&1 | strip | filter
  exit 0
fi

out=$(timeout 5 "$axiom" "${args[@]}" 2>&1 | strip || true)
if [[ $since_reload -eq 1 ]]; then
  last=$(grep -n 'Reloading configuration' <<<"$out" | tail -1 | cut -d: -f1 || true)
  [[ -n "$last" ]] && out=$(tail -n +"$last" <<<"$out")
fi
if [[ $problems -eq 1 ]]; then
  # A message starts at a level word; the lines after it, up to the next
  # level word, belong to it
  awk '
    function flush() { if (level == "WARN" || level == "ERROR") { if (!(msg in n)) order[++k] = msg; n[msg]++ } }
    /^ *(INFO|WARN|ERROR|DEBUG)/ { flush(); line = $0; sub(/^ */, "", line); level = line; sub(/[ :].*/, "", level); msg = line; next }
    { if (level != "") { line = $0; sub(/^ */, "", line); msg = msg " | " line } }
    END { flush(); for (i = 1; i <= k; i++) print "  " order[i] (n[order[i]] > 1 ? " (×" n[order[i]] ")" : "") }
  ' <<<"$out"
  exit 0
fi
filter <<<"$out"
