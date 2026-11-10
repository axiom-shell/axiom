# shellcheck shell=bash
# Named check steps for verify.sh, check_all.sh and check_go.sh (sourced,
# not run). Quiet by default, so a reader sees only problems:
#
#   a passing step      `✓ <name>`
#   a failing step      `✗ <name>`, then its output (the first 80 lines)
#
# AXIOM_VERBOSE=1 (the scripts' -v / --verbose) prints every step's whole
# output under a `── <name>` heading. Under GitHub Actions each step's
# output folds into a group, whole, as it always did.
#
#   source "$root/scripts/lib/steps.sh"
#   failed=()
#   step "name" command args…          appends to failed on failure
#   [[ ${#failed[@]} -eq 0 ]] || …

step() {
  local name="$1"
  shift
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    # Groups don't nest: an inner script (check_go.sh) gets a plain heading
    if [[ -n "${AXIOM_IN_GROUP:-}" ]]; then
      echo "── $name"
      "$@" || failed+=("$name")
    else
      echo "::group::$name"
      AXIOM_IN_GROUP=1 "$@" || failed+=("$name")
      echo "::endgroup::"
    fi
    return 0
  fi
  if [[ -n "${AXIOM_VERBOSE:-}" ]]; then
    echo "── $name"
    "$@" || failed+=("$name")
    return 0
  fi
  local out status=0 lines
  out="$("$@" 2>&1)" || status=$?
  if [[ $status -eq 0 ]]; then
    echo "✓ $name"
    return 0
  fi
  failed+=("$name")
  echo "✗ $name"
  # The inner script's own passing steps are no news
  out="$(grep -v '^✓ ' <<<"$out")"
  lines=$(wc -l <<<"$out")
  head -n 80 <<<"$out"
  [[ $lines -gt 80 ]] && echo "(… $((lines - 80)) more lines: -v for all)"
  return 0
}
