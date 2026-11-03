#!/usr/bin/env bash
# Read the axiom shell's log without the noise.
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

set -euo pipefail

# The shell this checkout runs: qs names an instance by its QML folder
qml="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/qml"
rules='*.debug=false'
since_reload=1
follow=0
pattern=''

while [[ $# -gt 0 ]]; do
  case "$1" in
  -d | --debug) rules='' ;;
  -a | --all) since_reload=0 ;;
  -f | --follow) follow=1 ;;
  -g | --grep)
    pattern="$2"
    shift
    ;;
  -h | --help)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "unknown option: $1" >&2
    exit 1
    ;;
  esac
  shift
done

args=(log -p "$qml")
[[ -n "$rules" ]] && args+=(-r "$rules")

strip() { sed -u 's/\x1b\[[0-9;]*m//g'; }
filter() { if [[ -n "$pattern" ]]; then grep -E --color=never --line-buffered -- "$pattern" || true; else command cat; fi; }

if [[ $follow -eq 1 ]]; then
  qs "${args[@]}" -f 2>&1 | strip | filter
  exit 0
fi

out=$(timeout 5 qs "${args[@]}" 2>&1 | strip || true)
if [[ $since_reload -eq 1 ]]; then
  last=$(grep -n 'Reloading configuration' <<<"$out" | tail -1 | cut -d: -f1 || true)
  [[ -n "$last" ]] && out=$(tail -n +"$last" <<<"$out")
fi
filter <<<"$out"
