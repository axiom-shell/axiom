#!/usr/bin/env bash
# The Go checks for backend/ (the axiom binary), run by verify.sh,
# check_all.sh and CI's go job. The tools are pinned in backend/go.mod
# (`go tool staticcheck`, `go tool govulncheck`).
#
# The generated files (scripts/generate.sh --fixtures: the embedded copies,
# the schema, the shared fixtures) are built first.
#
#   scripts/check_go.sh           generated code fresh, gofmt, vet, staticcheck,
#                                 go mod tidy, tests (with -race when cgo works)
#   scripts/check_go.sh --fix     rewrite instead of failing: go generate, gofmt -w
#   scripts/check_go.sh --ci      also govulncheck (the release cross-builds
#                                 are release.yml's)
#   scripts/check_go.sh -v        every step's whole output (default: a line
#                                 per passing step, the output of a failing one)
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root/backend" || exit 1

fix=0 ci=0
for arg in "$@"; do
  case "$arg" in
  --fix) fix=1 ;;
  --ci) ci=1 ;;
  -v | --verbose) export AXIOM_VERBOSE=1 ;;
  *)
    sed -n '2,15p' "$0" >&2
    exit 2
    ;;
  esac
done

if ! command -v go >/dev/null; then
  echo "go is not installed (needed for backend/)" >&2
  exit 1
fi

failed=()
# shellcheck source=lib/steps.sh
source "$root/scripts/lib/steps.sh"

generated() {
  "$root/scripts/generate.sh" --fixtures || return 1
  # Generated code (committed, unlike the embedded copies) must match its
  # sources: go generate changing it means it was stale
  local before
  before="$(find . -name 'zz_generated_*' -exec sha256sum {} + | sort)"
  go generate ./... || return 1
  [[ $fix -eq 1 || "$before" == "$(find . -name 'zz_generated_*' -exec sha256sum {} + | sort)" ]] && return 0
  echo "generated files were stale (now rewritten; commit them):"
  git -C "$root" status --porcelain -- backend | grep -E 'zz_generated_'
  return 1
}

formatted() {
  local unformatted
  unformatted="$(gofmt -l .)"
  [[ -z "$unformatted" ]] && return 0
  if [[ $fix -eq 1 ]]; then
    gofmt -w .
    echo "formatted: $unformatted"
    return 0
  fi
  echo "not gofmt'd (scripts/check_go.sh --fix):"
  echo "$unformatted"
  return 1
}

# Without -v go prints a line per package: only the failures matter
go_test() {
  local out status=0
  out="$(go test "$@" -count=1 ./... 2>&1)" || status=$?
  if [[ -n "${AXIOM_VERBOSE:-}${GITHUB_ACTIONS:-}" ]]; then
    echo "$out"
  else
    grep -Ev '^ok |no test files' <<<"$out" || true
  fi
  return $status
}

tests() {
  # -race needs cgo and a C compiler; without them run the plain tests
  if CGO_ENABLED=1 go env CC >/dev/null 2>&1 && command -v "$(go env CC)" >/dev/null; then
    go_test -race
  else
    go_test
  fi
}

step "go: generated files" generated
step "go: gofmt" formatted
step "go: vet" go vet ./...
step "go: staticcheck" go tool staticcheck ./...
tidy() {
  if [[ $fix -eq 1 ]]; then go mod tidy; else go mod tidy -diff; fi
}
step "go: mod tidy" tidy
step "go: tests" tests
step "go: schema built from qml/config/schema/" go run ./cmd/axiom schema check --tree ..
if [[ $ci -eq 1 ]]; then
  step "go: govulncheck" go tool govulncheck ./...
fi

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "failed: ${failed[*]}"
  exit 1
fi
echo "go checks passed"
