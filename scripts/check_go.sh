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
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root/backend" || exit 1

fix=0 ci=0
for arg in "$@"; do
  case "$arg" in
  --fix) fix=1 ;;
  --ci) ci=1 ;;
  *)
    sed -n '2,13p' "$0" >&2
    exit 2
    ;;
  esac
done

if ! command -v go >/dev/null; then
  echo "go is not installed (needed for backend/)" >&2
  exit 1
fi

failed=()
step() {
  local name="$1"
  shift
  echo "── go: $name"
  "$@" || failed+=("go $name")
}

generated() {
  "$root/scripts/generate.sh" --fixtures || return 1
  go generate ./... || return 1
  [[ $fix -eq 1 ]] && return 0
  # Generated code (committed, unlike the embedded copies) must match its
  # sources
  local stale
  stale="$(git -C "$root" status --porcelain -- backend | grep -E 'zz_generated_' || true)"
  if [[ -n "$stale" && $ci -eq 1 ]]; then
    echo "generated files are stale; run scripts/check_go.sh --fix:"
    echo "$stale"
    return 1
  fi
  return 0
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

tests() {
  # -race needs cgo and a C compiler; without them run the plain tests
  if CGO_ENABLED=1 go env CC >/dev/null 2>&1 && command -v "$(go env CC)" >/dev/null; then
    CGO_ENABLED=1 go test -race -count=1 ./...
  else
    go test -count=1 ./...
  fi
}

step "generated files" generated
step "gofmt" formatted
step "vet" go vet ./...
step "staticcheck" go tool staticcheck ./...
tidy() {
  if [[ $fix -eq 1 ]]; then go mod tidy; else go mod tidy -diff; fi
}
step "mod tidy" tidy
step "tests" tests
step "schema built from config/schema/" go run ./cmd/axiom schema check --tree ..
if [[ $ci -eq 1 ]]; then
  step "govulncheck" go tool govulncheck ./...
fi

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "failed: ${failed[*]}"
  exit 1
fi
echo "go checks passed"
