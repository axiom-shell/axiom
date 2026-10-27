#!/usr/bin/env bash
#
# Description: Builds the official axiom binaries, as a v* release
#              (.github/workflows/release.yml) and the edge prerelease
#              (edge.yml) publish them: static axiom-linux-amd64 and
#              axiom-linux-arm64 stamped with the version, checked to report
#              it and HEAD's commit, plus COMMIT (HEAD's full hash) and a
#              SHA256SUMS listing all three, as sha256sum writes it (the
#              greeter install, self-update and install.sh check against it:
#              docs/dev/packaging.md › Releases). Run from the repo root after
#              scripts/generate.sh (the binary embeds what it generates).
# Usage:       scripts/build_binaries.sh <version> <dist>
#              version is what `axiom version` reports (vX.Y.Z, edge-<short
#              commit>); dist is made and gets the files.

set -euo pipefail

[[ $# -eq 2 ]] || { echo "usage: $0 <version> <dist>" >&2; exit 2; }
version=$1
dist=$(mkdir -p "$2" && cd "$2" && pwd)
commit=$(git rev-parse HEAD)

for arch in amd64 arm64; do
  CGO_ENABLED=0 GOOS=linux GOARCH=$arch go -C backend build -trimpath \
    -ldflags "-s -w -X github.com/axiom-shell/axiom/backend/internal/buildinfo.version=$version" \
    -o "$dist/axiom-linux-$arch" ./cmd/axiom
done

"$dist/axiom-linux-amd64" version | tee /dev/stderr | grep -qF "axiom $version " ||
  { echo "::error::the binary doesn't report $version"; exit 1; }
"$dist/axiom-linux-amd64" version --json | grep -qF "\"commit\": \"$commit\"" ||
  { echo "::error::the binary doesn't name $commit as its commit"; exit 1; }

echo "$commit" >"$dist/COMMIT"
(cd "$dist" && sha256sum axiom-linux-* COMMIT >SHA256SUMS && cat SHA256SUMS)
