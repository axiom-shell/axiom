#!/usr/bin/env bash
# Run the QML unit tests (tests/tst_*.qml) with qmltestrunner, outside qs.
#
# The tests cover qml/components/methods/ (pure by the layering rule), imported
# from a module tree of the shell's Quickshell-free files
# (scripts/qml_modules.py --pure).
#
#   scripts/run_tests.sh             every test
#   scripts/run_tests.sh NAME...     only tests/tst_NAME.qml
#   scripts/run_tests.sh -q ...      only what failed (FAIL and its message,
#                                    XPASS) and the Totals line
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/qt_paths.sh
source "$root/scripts/lib/qt_paths.sh"
tree="$(mktemp -d)"
trap 'rm -rf "$tree"' EXIT

quiet=0
if [ "${1:-}" = "-q" ]; then
  quiet=1
  shift
fi

python3 "$root/scripts/qml_modules.py" --pure "$tree"
# -maxwarnings 0: scripts/dev/fixtures.py records through the log, past
# qmltestrunner's default cap of 2000 messages a test.
# qmltestrunner takes one -input (a later one replaces it), so named tests
# run one at a time
inputs=()
if [ $# -eq 0 ]; then
  inputs=("$root/tests")
else
  for name in "$@"; do inputs+=("$root/tests/tst_$name.qml"); done
fi

status=0
for input in "${inputs[@]}"; do
  if [ $quiet -eq 1 ]; then
    # FAIL! with the lines under it (Actual, Expected, Loc), XPASS, Totals
    log="$tree/run.log"
    QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen \
      "$qt_bin/qmltestrunner" -maxwarnings 0 -import "$tree" -input "$input" >"$log" 2>&1 || status=$?
    grep -E -A3 --no-group-separator '^(FAIL|XPASS)' "$log" || true
    grep '^Totals' "$log" || true
  else
    QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen \
      "$qt_bin/qmltestrunner" -maxwarnings 0 -import "$tree" -input "$input" || status=$?
  fi
done

exit "$status"
