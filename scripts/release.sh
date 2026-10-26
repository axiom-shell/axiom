#!/usr/bin/env bash
#
# Description: Tags and pushes an axiom release. Releases are annotated `v*`
#              tags on main; self_update.sh moves clones between them and
#              shows the tag message as the release notes (Settings → Updates
#              and the "axiom updated" notification), so its first line
#              should be a short summary.
# Usage:       scripts/release.sh <version> [--dry-run]
#              version is X.Y.Z (a leading v is optional) and must be higher
#              than the latest tag. Checks for a clean main that matches
#              origin, runs the same checks as CI, opens git's editor on notes
#              prefilled with the commits since the last tag, then tags and
#              pushes. The tag starts .github/workflows/release.yml, which
#              publishes the GitHub release (the binaries and SHA256SUMS) and
#              the AUR packages: nothing to commit afterwards. --dry-run stops
#              before tagging.

set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf ':: %s\n' "$*"; }

version="" dry_run=false
for arg in "$@"; do
  case "$arg" in
  --dry-run) dry_run=true ;;
  -h | --help) sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  -*) die "unknown option $arg" ;;
  *) version=$arg ;;
  esac
done
[[ -n "$version" ]] || die "usage: $0 <version> [--dry-run]"
version=${version#v}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be X.Y.Z, not $version"
tag="v$version"

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# ─── The commit ──────────────────────────────────────────────────────────────

[[ "$(git symbolic-ref --quiet --short HEAD || true)" == "main" ]] || die "not on main"
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || die "main has uncommitted changes"

info "Fetching origin"
git fetch --quiet origin main 'refs/tags/v*:refs/tags/v*'
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] ||
  die "main doesn't match origin/main (push or pull first)"

git rev-parse --quiet --verify "refs/tags/$tag" >/dev/null && die "$tag already exists"

last=$(git tag -l 'v*' --sort=-v:refname | head -n 1)
if [[ -n "$last" ]]; then
  newest=$(printf '%s\n%s\n' "$last" "$tag" | sort -V | tail -n 1)
  [[ "$newest" == "$tag" ]] || die "$tag isn't higher than $last"
  # Every release must contain the one before, or clones at it read as diverged
  git merge-base --is-ancestor "$last" HEAD || die "$last isn't in main's history"
  [[ "$(git rev-parse HEAD)" != "$(git rev-parse "$last^{commit}")" ]] || die "nothing since $last"
  range="$last..HEAD"
else
  range="HEAD"
fi

# ─── Checks (as in .github/workflows/checks.yml) ─────────────────────────────

info "Running checks"
python3 scripts/check_structure.py
python3 scripts/check_packages.py
git ls-files -z '*.json' | xargs -0 -n1 python3 -m json.tool --no-ensure-ascii >/dev/null
for f in install.sh scripts/*.sh scripts/lib/*.sh; do bash -n "$f"; done
python3 -m py_compile scripts/*.py
python3 scripts/check_i18n.py >/dev/null || info "check_i18n.py reported missing translations (not blocking)"

# Checks run on pull requests, not on main: a release asks for a full run
# on the commit it tags (gh workflow run checks.yml --ref main)
if command -v gh >/dev/null; then
  ci=$(gh run list --commit "$(git rev-parse HEAD)" --workflow checks.yml --json status,conclusion \
    --jq '.[0] | if . == null then "none" elif .status != "completed" then "pending" else .conclusion end' 2>/dev/null || echo unknown)
  case "$ci" in
  success) info "CI passed on this commit" ;;
  failure | cancelled) die "CI $ci on this commit" ;;
  none) die "CI hasn't run on this commit: gh workflow run checks.yml --ref main, then release once it passes" ;;
  *) info "CI status: $ci" ;;
  esac
fi

# ─── Notes ───────────────────────────────────────────────────────────────────

notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
{
  printf 'axiom %s\n\n' "$version"
  git log --no-merges --format='- %s' "$range"
  printf '\n# The first line is the summary shown in the update notification.\n'
  printf '# Lines starting with # are dropped. An empty message aborts.\n'
  printf '# %s: %s commits since %s\n' "$tag" "$(git rev-list --count "$range")" "${last:-the start}"
} >"$notes"

# The editor git would use for a tag message (GIT_EDITOR, core.editor, VISUAL, EDITOR)
sh -c "$(git var GIT_EDITOR) \"\$@\"" editor "$notes"
sed -i '/^#/d' "$notes"
[[ -n "$(tr -d '[:space:]' <"$notes")" ]] || die "empty notes, nothing tagged"

if $dry_run; then
  info "Dry run: would tag $(git rev-parse --short HEAD) as $tag with these notes:"
  command cat "$notes"
  exit 0
fi

# ─── Tag and push ────────────────────────────────────────────────────────────

git tag -a "$tag" -F "$notes" --cleanup=strip
git push origin "$tag" || die "push failed; $tag exists locally only (retry: git push origin $tag)"
info "Released $tag"

info "CI publishes the release and the AUR packages: $(git remote get-url origin | sed -E 's#^git@github.com:#https://github.com/#; s#\.git$##')/actions/workflows/release.yml"
