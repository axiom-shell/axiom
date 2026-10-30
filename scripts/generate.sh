#!/usr/bin/env bash
# Builds the generated files the shell, the checks and the tests read, all
# of them on every run except the fixtures (rebuilt only when what they're
# recorded from changed). None of them is committed (.gitignore); a fresh
# clone runs this once (verify.sh, check_all.sh, check_go.sh and CI run it
# first):
#   - backend/internal/assets/data/, the repo files compiled into the binary,
#     the schema among them, and config/json/config.schema.json, the schema
#     built from its YAML source config/schema/ (`go generate`,
#     backend/tools/syncassets, a small program: with --no-docs nothing
#     compiles the whole binary); the binary doesn't compile without data/
#   - docs/dev/config/ and docs/dev/generated/, the reference docs made from
#     the code and the schema (scripts/gen_docs.py, which also fails when the
#     shell calls a daemon method or push the daemon doesn't define, or on
#     unread settings and unused reader members), after
#     docs/dev/generated/rpc-shapes.json, the daemon's methods, pushes and
#     topics with their fields (backend/tools/rpcshapes, through go run); a
#     developer check, so --no-docs skips it: install.sh and the AUR
#     packages pass it, since a failed check mustn't stop an install, and
#     check_all.sh without the checks job, which alone needs it
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
    sed -n '2,24p' "$0" >&2
    exit 2
    ;;
  esac
done

if ! command -v go >/dev/null; then
  echo "generate: go isn't installed (it builds config/json/config.schema.json)" >&2
  exit 1
fi
# The embedded copies and the tree's schema (the binary needs the first to
# compile; the docs and the fixtures are made from the second)
(cd "$root/backend" && go generate ./internal/assets)
if [[ $docs -eq 1 ]]; then
  mkdir -p "$root/docs/dev/generated"
  (cd "$root/backend" && go run ./tools/rpcshapes >"$root/docs/dev/generated/rpc-shapes.json.new")
  mv -f "$root/docs/dev/generated/rpc-shapes.json.new" "$root/docs/dev/generated/rpc-shapes.json"
  python3 "$root/scripts/gen_docs.py"
fi
if [[ $fixtures -eq 1 ]]; then
  python3 "$root/scripts/dev/fixtures.py" ensure
fi
