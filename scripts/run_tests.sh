#!/usr/bin/env bash
# Run the QML unit tests (tests/tst_*.qml) with qmltestrunner, outside qs.
#
# The tests cover qml/components/methods/ (pure by the layering rule) and the
# services/core parts that import only QtQuick (loaded from their files), with
# imports from a module tree of the shell's Quickshell-free files
# (scripts/qml_modules.py --pure). tests-layout/ holds the layout harness: the
# pieces (reusable/, forms/) at scale, font and density settings, and the service
# files a test needs over stand-ins (LAYOUT_SERVICES), over stubs
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
marker="$root/tests/.recording"
trap 'rm -rf "$tree" "$marker"' EXIT
# scripts/dev/fixtures.py passes the kind it records in AXIOM_RECORDING; any
# other run removes a marker that a killed recording left.
if [ -n "${AXIOM_RECORDING:-}" ]; then printf '%s\n' "$AXIOM_RECORDING" >"$marker"; else rm -f "$marker"; fi

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

# One run of `input` (its module tree `import`), at the device pixel ratio the
# environment sets. The composite's pixel test (tst_ChromeComposite) runs under
# xvfb with llvmpipe where installed: a GPU-backed scene graph, which draws the
# shader and a clipped Shape as the shell's does; the offscreen platform's
# software one doesn't (the test skips what it can't read there)
run_one() {
  local input="$1" import="$2" wrap=() composite=0
  if [ "$(basename "$input")" = tst_ChromeComposite.qml ] || [ "$input" = "$root/tests-layout" ]; then
    composite=1
    if command -v xvfb-run >/dev/null; then
      wrap=(env LIBGL_ALWAYS_SOFTWARE=1 QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl QT_QPA_PLATFORM=xcb xvfb-run -a -s "-screen 0 1280x1024x24 +extension GLX")
    elif [ -n "${GITHUB_ACTIONS:-}" ]; then
      # CI must not skip the composite's GPU rows
      echo "error    xvfb-run not found: tst_ChromeComposite's GPU rows need it (xorg-server-xvfb, mesa)" >&2
      status=1
      return
    fi
  fi
  log="$tree/run.log"
  if [ $quiet -eq 1 ]; then
    # FAIL! with the lines under it (Actual, Expected, Loc), XPASS, Totals
    QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen "${wrap[@]}" \
      "$qt_bin/qmltestrunner" -maxwarnings 0 -import "$import" -input "$input" >"$log" 2>&1 || status=$?
    grep -E -A3 --no-group-separator '^(FAIL|XPASS)' "$log" || true
    grep '^Totals' "$log" || true
  else
    QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen "${wrap[@]}" \
      "$qt_bin/qmltestrunner" -maxwarnings 0 -import "$import" -input "$input" 2>&1 | tee "$log" || status=1
  fi
  # llvmpipe not loading shows as a software-graph skip: a failure in CI
  if [ $composite -eq 1 ] && [ -n "${GITHUB_ACTIONS:-}" ] && grep -q 'software scene graph:' "$log"; then
    echo "error    tst_ChromeComposite skipped rows on the software scene graph: llvmpipe did not load" >&2
    status=1
  fi
}

status=0
for i in "${!inputs[@]}"; do
  run_one "${inputs[$i]}" "${trees[$i]}"
done
# The composite's pixel rows name the scale they run at (tst_ChromeComposite):
# the file runs once more at a fractional scale, where the whole test folder or
# the file by name was asked for
if [ $# -eq 0 ] || printf '%s\n' "$@" | grep -qx ChromeComposite; then
  QT_SCALE_FACTOR=1.25 run_one "$root/tests-layout/tst_ChromeComposite.qml" "$layout_tree"
fi

exit "$status"
