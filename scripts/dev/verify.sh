#!/usr/bin/env bash
# The loop to run after changing anything: checks what changed against HEAD
# (plus new files), the way CI will, and shows what the live shell logged.
#
#   0. builds the generated files (scripts/generate.sh: the schema from
#      config/schema/, the binary's embedded copies, the reference docs in
#      docs/dev/config and docs/dev/generated, and the shared fixtures when a
#      change touches what they're recorded from)
#   1. formats changed QML with Qt 6's qmlformat, writing in place so the
#      file keeps its inode and the running shell still reloads it
#   2. check_structure, check_sizes, check_docs, check_packages, qmllint, the
#      unit tests the change touches (QML, and the test_scripts.py classes of
#      a changed script), the Go checks (backend/:
#      go generate, gofmt, vet, staticcheck, tests), shellcheck, i18n
#   3. the shell's log since its last reload, lines issues.md already
#      covers marked (known: …)
#   4. warnings: the docs describing the changed files (check_doc_drift.py),
#      and a missing pre-commit hook
#
#   scripts/dev/verify.sh             what changed since HEAD
#   scripts/dev/verify.sh --all       every check on everything (check_all.sh)
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root" || exit 1
# shellcheck source=../lib/qt_paths.sh
source "$root/scripts/lib/qt_paths.sh"

all=0
for arg in "$@"; do
  case "$arg" in
  --all) all=1 ;;
  *)
    sed -n '2,21p' "$0" >&2
    exit 2
    ;;
  esac
done
[[ $all -eq 1 ]] && exec scripts/check_all.sh

mapfile -t changed < <({
  git diff --name-only HEAD
  git ls-files -o --exclude-standard
} | sort -u | while read -r f; do [[ -f "$f" ]] && echo "$f"; done)

if [[ ${#changed[@]} -eq 0 ]]; then
  echo "nothing changed since HEAD"
  exit 0
fi

failed=()
step() {
  local name="$1"
  shift
  echo "── $name"
  "$@" || failed+=("$name")
}

qml=() tests=() shells=() script_tests=() schema=0 go=0 fixtures=0
for f in "${changed[@]}"; do
  case "$f" in
  *.qml) qml+=("$f") ;;
  *.sh) shells+=("$f") ;;
  esac
  case "$f" in
  components/methods/SchemaValidation.qml) schema=1 go=1 ;;
  config/schema/* | backend/internal/schema/*) schema=1 go=1 ;;
  # The bind merge (backend/internal/compositor/binds) reads its actions
  components/methods/BindActions.qml) go=1 ;;
  esac
  # backend/ and the repo files the binary embeds (backend/tools/syncassets)
  case "$f" in
  backend/* | config/json/backend.json | config/json/theme-defaults.json) go=1 ;;
  # The shared fixtures: both sides replay them (docs/dev/backend/README.md)
  tests/Shared.qml | scripts/dev/fixtures.py | scripts/generate.sh) go=1 fixtures=1 tests+=(Shared) ;;
  esac
  case "$f" in
  components/methods/*.qml)
    name="$(basename "$f" .qml)"
    [[ -f "tests/tst_$name.qml" ]] && tests+=("$name")
    ;;
  tests/tst_*.qml)
    name="$(basename "$f" .qml)"
    tests+=("${name#tst_}")
    ;;
  esac
  # tests/scripts/test_scripts.py's classes for each script (the whole
  # file takes ~15 s); a new script with tests gets a line here
  case "$f" in
  scripts/theme_*.sh | scripts/lib/theme_env.sh | scripts/templates/* | config/themes/* | config/json/theme-defaults.json | scripts/gen_theme_template.py)
    script_tests+=(Themes TerminalPalette ThemeIntegrations)
    ;;
  scripts/integration_hookup.py) script_tests+=(HookupScript) ;;
  scripts/self_update.sh) script_tests+=(SelfUpdate) ;;
  scripts/cursor_theme.py) script_tests+=(CursorTheme) ;;
  scripts/generate_theme.py) script_tests+=(GenerateTheme) ;;
  scripts/calendar_sync.py) script_tests+=(CalendarSync) ;;
  scripts/greeter/*) script_tests+=(GreeterInstall GreeterSession) ;;
  scripts/pick_path.py) script_tests+=(PickPath) ;;
  scripts/community_fetch.sh) script_tests+=(CommunityFetch) ;;
  scripts/dev/known_issues.py) script_tests+=(KnownIssues) ;;
  scripts/check_sizes.py) script_tests+=(CheckSizes) ;;
  scripts/gen_docs.py) script_tests+=(RpcShapes) ;;
  tests/scripts/test_scripts.py) script_tests+=(all) ;;
  esac
done
[[ $schema -eq 1 ]] && tests+=(Config)

reloads_before=$(scripts/log.sh --all 2>/dev/null | grep -c "Reloading configuration" || true)

# 1. Format in place (cat > keeps the inode; -i would replace the file)
if [[ ${#qml[@]} -gt 0 ]]; then
  echo "── qmlformat (${#qml[@]} changed QML files)"
  formatted=0
  for f in "${qml[@]}"; do
    out="$("$qt_bin/qmlformat" "$f")" || {
      failed+=("qmlformat $f")
      continue
    }
    if [[ "$out" != "$(cat "$f")" ]]; then
      printf '%s\n' "$out" >"$f"
      echo "formatted $f"
      formatted=1
    fi
  done
  [[ $formatted -eq 0 ]] && echo "already formatted"
fi

# 2. Checks (the generated files built first: the docs and checks read them)
if [[ $go -eq 1 || $fixtures -eq 1 || $schema -eq 1 ]]; then
  step "generated files" scripts/generate.sh --fixtures
else
  step "generated files" scripts/generate.sh
fi
step "structure" python3 scripts/check_structure.py
if [[ ${#qml[@]} -gt 0 ]]; then
  step "sizes" python3 scripts/check_sizes.py
fi
if printf '%s\n' "${changed[@]}" | grep -qE '\.(md|qml)$'; then
  step "doc citations" python3 scripts/check_docs.py
fi
if printf '%s\n' "${changed[@]}" | grep -qE '^(install\.sh|components/methods/Packages\.qml|packaging/|scripts/check_packages\.py)'; then
  step "package lists" python3 scripts/check_packages.py
fi
if [[ ${#qml[@]} -gt 0 ]]; then
  step "qmllint" python3 scripts/check_qmllint.py
fi
if [[ ${#tests[@]} -gt 0 ]]; then
  mapfile -t tests < <(printf '%s\n' "${tests[@]}" | sort -u)
  step "unit tests (${tests[*]})" bash -c 'scripts/run_tests.sh "$@" 2>&1 | grep -E "^(FAIL|Totals|XPASS)|error" ; exit "${PIPESTATUS[0]}"' _ "${tests[@]}"
fi
if [[ ${#script_tests[@]} -gt 0 ]]; then
  if printf '%s\n' "${script_tests[@]}" | grep -qx all; then
    step "script tests (all)" python3 tests/scripts/test_scripts.py
  else
    mapfile -t script_tests < <(printf '%s\n' "${script_tests[@]}" | sort -u)
    step "script tests (${script_tests[*]})" python3 tests/scripts/test_scripts.py "${script_tests[@]}"
  fi
fi
if printf '%s\n' "${changed[@]}" | grep -qE '^(\.claude/hooks/|tests/scripts/test_guard\.py)'; then
  step "guard tests" python3 tests/scripts/test_guard.py
fi
if [[ $fixtures -eq 1 ]]; then
  step "shared fixtures" python3 scripts/dev/fixtures.py check
fi
if [[ $go -eq 1 ]]; then
  step "go" scripts/check_go.sh --fix
fi
if [[ ${#shells[@]} -gt 0 ]]; then
  step "shellcheck" shellcheck -x -S warning "${shells[@]}"
fi
if [[ ${#qml[@]} -gt 0 || $schema -eq 1 ]]; then
  echo "── translations (warnings only)"
  python3 scripts/check_i18n.py 2>&1 | tail -n 15 || true
fi

# 3. The live shell: wait briefly for the reload a save (or the formatting)
# triggered, then show what it logged
if [[ ${#qml[@]} -gt 0 || $schema -eq 1 ]] && command -v qs >/dev/null; then
  echo "── shell log since the last reload"
  for _ in 1 2 3 4 5 6; do
    now=$(scripts/log.sh --all 2>/dev/null | grep -c "Reloading configuration" || true)
    [[ $now -gt $reloads_before ]] && break
    sleep 0.5
  done
  sleep 1
  scripts/log.sh | scripts/dev/known_issues.py || true
  echo "(no new reload since this script started is normal when the shell already reloaded on save;"
  echo " if the log looks stale, see docs/dev/testing.md › Reloads and logs)"
fi

# 4. Warnings, never failures
echo "── docs"
python3 scripts/check_doc_drift.py --changed "${changed[@]}"
if [[ "$(git config core.hooksPath)" != ".githooks" ]]; then
  echo "warning: the pre-commit hook isn't set up, so commits can carry stale translation files and theme template:"
  echo "  git config core.hooksPath .githooks"
fi

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "failed: ${failed[*]}"
  exit 1
fi
echo "verify ok"
