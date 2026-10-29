#!/usr/bin/env bash
# Every check CI runs, grouped by CI's jobs: each job of
# .github/workflows/checks.yml runs `scripts/check_all.sh --ci <job>`, so a
# new check is added here only (verify.sh --all runs all of it; its plain
# run picks from the same checks by what changed, so a new check gets a
# trigger there too). Needs Qt 6's tools, go, shellcheck, luac and jq.
#
#   scripts/check_all.sh [--ci] [checks|qt|go|scripts …]   no job: all four
#   --ci   also govulncheck (check_go.sh --ci); under GitHub Actions each
#          check's output folds into a group
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1

ci=() jobs=()
for arg in "$@"; do
  case "$arg" in
  --ci) ci=(--ci) ;;
  checks | qt | go | scripts) jobs+=("$arg") ;;
  *)
    sed -n '2,10p' "$0" >&2
    exit 2
    ;;
  esac
done
[[ ${#jobs[@]} -eq 0 ]] && jobs=(checks qt go scripts)

failed=()
step() {
  local name="$1"
  shift
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::group::$name"
    "$@" || failed+=("$name")
    echo "::endgroup::"
  else
    echo "── $name"
    "$@" || failed+=("$name")
  fi
}

# The generated files the checks read (the schema, the reference docs, and
# for the qt job the shared fixtures), built once per run; check_go.sh
# builds its own
case " ${jobs[*]} " in
*" qt "*) step "generated files" scripts/generate.sh --fixtures ;;
*" checks "* | *" scripts "*) step "generated files" scripts/generate.sh ;;
esac

json() {
  git ls-files -z '*.json' | xargs -0 -n1 python3 -m json.tool --no-ensure-ascii >/dev/null
}

for job in "${jobs[@]}"; do
  case "$job" in
  checks)
    step "structure" python3 scripts/check_structure.py
    step "sizes" python3 scripts/check_sizes.py
    step "docs" python3 scripts/check_docs.py
    step "package lists" python3 scripts/check_packages.py
    step "json" json
    # Fails on what the pre-commit hook fixes; empty entries only warn
    step "translations" python3 scripts/check_i18n.py
    ;;
  qt)
    step "qmlformat" scripts/check_qmlformat.sh
    step "qmllint" python3 scripts/check_qmllint.py
    step "unit tests" scripts/run_tests.sh
    ;;
  go)
    step "go" scripts/check_go.sh "${ci[@]}"
    step "shared fixtures" python3 scripts/dev/fixtures.py check
    ;;
  scripts)
    step "shellcheck" shellcheck -x -S warning install.sh scripts/*.sh scripts/lib/*.sh scripts/greeter/*.sh scripts/dev/*.sh .githooks/pre-commit
    step "script tests" python3 tests/scripts/test_scripts.py
    step "guard tests" python3 tests/scripts/test_guard.py
    ;;
  esac
done

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "failed: ${failed[*]}"
  exit 1
fi
echo "all checks passed"
