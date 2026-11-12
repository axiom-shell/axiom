#!/usr/bin/env bash
# Container tests: real compositors (headless), the real daemon and a fake
# shell, run in a docker container (docs/dev/testing.md › Container tests).
# Dev-only; never run on CI or inside a container.
#
#   scripts/dev/container-test.sh [--rebuild] [--keep] [--shell] [-run REGEX]
#
#   --rebuild  build the image again
#   --keep     keep the snapshot of the tree
#   --shell    a bash in the container instead of the tests
#   -run RE    only the tests matching RE (go test -run)
#
# The exit code is the tests'. Logs are in <snapshot>.out/<TestName>/.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
rebuild=0 keep=0 shell=0 run=.
while [ $# -gt 0 ]; do
	case $1 in
	--rebuild) rebuild=1 ;;
	--keep) keep=1 ;;
	--shell) shell=1 ;;
	-run)
		[ $# -ge 2 ] || { echo "container-test: -run needs a regex" >&2; exit 2; }
		run=$2
		shift
		;;
	-h | --help)
		sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		echo "container-test: unknown argument $1" >&2
		exit 2
		;;
	esac
	shift
done

if [ -e /.dockerenv ]; then
	echo "container-test: refusing to run inside a container" >&2
	exit 2
fi
command -v docker >/dev/null || { echo "container-test: docker isn't installed" >&2; exit 2; }

dockerfile=$root/scripts/dev/container/Dockerfile
image=axiom-ctr:$(sha256sum "$dockerfile" | cut -c1-12)
if [ "$rebuild" = 1 ] || ! docker image inspect "$image" >/dev/null 2>&1; then
	docker build -t "$image" -f "$dockerfile" "$root/scripts/dev/container"
fi

snap=$(mktemp -d "${TMPDIR:-/tmp}/axiom-ctr.XXXXXX")
out=$snap.out
mkdir -p "$out"
cleanup() {
	if [ "$keep" = 1 ]; then
		echo "container-test: snapshot kept in $snap"
	else
		rm -rf "$snap"
	fi
	echo "container-test: logs in $out"
}
trap cleanup EXIT

(cd "$root" && git ls-files -co --exclude-standard -z | tar --null -T - -c) | tar -x -C "$snap"
# The container's tester must read and write them (a mount is its own uid)
chmod -R a+rX "$snap"
chmod a+rwx "$out"

cmd=(/src/scripts/dev/container/inside.sh "$run")
[ "$shell" = 1 ] && cmd=(bash)
tty=()
[ "$shell" = 1 ] && tty=(-it)

set +e
docker run --rm --init "${tty[@]}" --user tester -e HOME=/home/tester -e AXIOM_TEST_WAIT_FACTOR=3 \
	-v "$snap:/src:ro" -v "$out:/out" -v axiom-ctr-cache:/home/tester/.cache \
	"$image" "${cmd[@]}"
code=$?
set -e
exit "$code"
