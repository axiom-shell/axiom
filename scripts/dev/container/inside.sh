#!/usr/bin/env bash
# What runs in the container (scripts/dev/container-test.sh): builds the
# tree's axiom and runs the container tests against it.
set -euo pipefail

cp -r /src ~/axiom
cd ~/axiom
scripts/generate.sh
mkdir -p ~/bin
(cd backend && go build -o ~/bin/axiom ./cmd/axiom)
cd backend
AXIOM_BIN=~/bin/axiom AXIOM_SRC=~/axiom AXIOM_CTR_OUT=/out \
	go test -tags container -count=1 -v -run "${1:-.}" ./internal/containertest/
