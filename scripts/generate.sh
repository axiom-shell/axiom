#!/usr/bin/env bash
# Builds the generated files the shell, the checks and the tests read, all
# of them on every run except the fixtures (rebuilt only when what they're
# recorded from changed). None of them is committed (.gitignore); a fresh
# clone runs this once (verify.sh, check_all.sh, check_go.sh and CI run it
# first):
#   - backend/internal/assets/data/, the repo files compiled into the binary,
#     the schema among them (`go generate`, backend/tools/syncassets): the
#     binary doesn't compile without it
#   - config/json/config.schema.json, from its YAML source config/schema/
#     (`axiom schema build`, through go run)
#   - docs/dev/config/ and docs/dev/generated/, the reference docs made from
#     the code and the schema (scripts/gen_docs.py, which also fails when the
#     shell calls a daemon method or push the daemon doesn't define); a
#     developer check, so --no-docs skips it: install.sh, self_update.sh and
#     the AUR packages pass it, since a failed check mustn't stop an install
#   - with --fixtures: tests/fixtures/shared/, the cases SchemaValidation
#     and the binary share (scripts/dev/fixtures.py ensure: a few seconds
#     when stale; needs Qt 6's qmltestrunner)
#
#   scripts/generate.sh [--fixtures] [--no-docs]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixtures=0
docs=1
for arg in "$@"; do
  case "$arg" in
  --fixtures) fixtures=1 ;;
  --no-docs) docs=0 ;;
  *)
    sed -n '2,21p' "$0" >&2
    exit 2
    ;;
  esac
done

if ! command -v go >/dev/null; then
  echo "generate: go isn't installed (it builds config/json/config.schema.json)" >&2
  exit 1
fi
# The embedded copies first (the binary needs them to compile), then the
# tree's schema (the docs and the fixtures are made from it)
(cd "$root/backend" && go generate ./internal/assets)
(cd "$root/backend" && go run ./cmd/axiom schema build --tree .. >/dev/null)
if [[ $docs -eq 1 ]]; then
  python3 "$root/scripts/gen_docs.py"
fi
if [[ $fixtures -eq 1 ]]; then
  python3 "$root/scripts/dev/fixtures.py" ensure
fi
