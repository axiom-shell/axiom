#!/usr/bin/env bash
# Run the QML unit tests (tests/tst_*.qml) with qmltestrunner, outside qs.
#
# The tests cover qml/components/methods/ (pure by the layering rule), imported
# from a module tree of the shell's Quickshell-free files
# (scripts/qml_modules.py --pure). tests-layout/ holds the layout harness: the
# pieces (reusable/, forms/) at scale, font and density settings, over stubs
# for what imports Quickshell or the services (scripts/qml_modules.py
# --layout); a sibling of tests/, since qmltestrunner scans its -input folder
# recursively.
#
#   scripts/run_tests.sh             every test, the pure ones then the layout ones
#   scripts/run_tests.sh NAME...     only tests/tst_NAME.qml, else tests-layout/tst_NAME.qml
#   scripts/run_tests.sh -q ...      only what failed (FAIL and its message,
#                                    XPASS) and the Totals line
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/qt_paths.sh
source "$root/scripts/lib/qt_paths.sh"
tree="$(mktemp -d)"
layout_tree="$tree/layout"
trap 'rm -rf "$tree"' EXIT

quiet=0
if [ "${1:-}" = "-q" ]; then
  quiet=1
  shift
fi

python3 "$root/scripts/qml_modules.py" --pure "$tree/pure"
python3 "$root/scripts/qml_modules.py" --layout "$layout_tree"
# -maxwarnings 0: scripts/dev/fixtures.py records through the log, past
# qmltestrunner's default cap of 2000 messages a test.
# qmltestrunner takes one -input (a later one replaces it), so named tests
# run one at a time
inputs=() trees=()
if [ $# -eq 0 ]; then
  inputs=("$root/tests" "$root/tests-layout")
  trees=("$tree/pure" "$layout_tree")
else
  for name in "$@"; do
    if [ -f "$root/tests/tst_$name.qml" ]; then
      inputs+=("$root/tests/tst_$name.qml") trees+=("$tree/pure")
    else
      inputs+=("$root/tests-layout/tst_$name.qml") trees+=("$layout_tree")
    fi
  done
fi

status=0
for i in "${!inputs[@]}"; do
  input="${inputs[$i]}"
  import="${trees[$i]}"
  if [ $quiet -eq 1 ]; then
    # FAIL! with the lines under it (Actual, Expected, Loc), XPASS, Totals
    log="$tree/run.log"
    QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen \
      "$qt_bin/qmltestrunner" -maxwarnings 0 -import "$import" -input "$input" >"$log" 2>&1 || status=$?
    grep -E -A3 --no-group-separator '^(FAIL|XPASS)' "$log" || true
    grep '^Totals' "$log" || true
  else
    QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen \
      "$qt_bin/qmltestrunner" -maxwarnings 0 -import "$import" -input "$input" || status=$?
  fi
done

exit "$status"
