#!/usr/bin/env bash
#
# Description: Checks for and applies axiom updates from the clone's remote,
#              following one of two channels:
#                tags  releases: `v*` tags, updating to the newest
#                main  the remote's main (or master) branch
#              An update only fast-forwards.
# Usage:       self_update.sh [--channel tags|main] check [dir]
#              self_update.sh [--channel tags|main] apply <target> [dir]
#              target is the `latest` a check reported. dir defaults to the
#              repo this script is in. Prints one JSON object: { channel,
#              current, commit, latest, state, ahead, behind, blocked, notes,
#              rebuilt, buildError, error }
#                latest  the newest tag, or main's short commit
#                state   "uptodate" | "available" | "diverged" | ""
#                blocked why it can't update: "dirty" (changed tracked
#                        files), "diverged" (local commits), "branch" (a
#                        branch other than main/master), "nogit", or ""
#                notes   the tag's message, or main's new commit subjects
#                rebuilt whether apply rebuilt the axiom binary ($AXIOM_BIN,
#                        which axiom run sets) from the updated clone: done
#                        when this user can replace it (not a package's)
#                buildError why that build failed (the update itself is in)
#              Never stashes, resets or forces: a blocked clone is left as
#              it is.

set -uo pipefail

command -v jq >/dev/null || { echo '{"error": "jq is not installed"}'; exit 1; }

channel=tags
if [[ "${1:-}" == "--channel" ]]; then
  channel=${2:-}
  shift 2
fi

action=${1:-check}
target=""
if [[ "$action" == "apply" ]]; then
  target=${2:-}
  dir=${3:-}
else
  dir=${2:-}
fi
dir=${dir:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}

# Never wait on a password or host-key prompt
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes"

g() { git -C "$dir" "$@"; }

emit() {
  jq -cn --arg channel "$channel" --arg current "${current:-}" --arg commit "${commit:-}" \
    --arg latest "${latest:-}" --arg state "${state:-}" --argjson ahead "${ahead:-false}" \
    --argjson behind "${behind:-0}" --arg blocked "${blocked:-}" --arg notes "${notes:-}" \
    --argjson rebuilt "${rebuilt:-false}" --arg buildError "${build_error:-}" --arg error "${1:-}" \
    '{channel: $channel, current: $current, commit: $commit, latest: $latest, state: $state,
      ahead: $ahead, behind: $behind, blocked: $blocked, notes: $notes, rebuilt: $rebuilt,
      buildError: $buildError, error: $error}'
}

# The binary the shell runs, built again from the updated clone, so the
# schema it embeds is the tree's (else the shell runs read-only). Built
# beside it, then swapped in; only one this user can replace
rebuild() {
  local bin=${AXIOM_BIN:-} out
  [[ -n "$bin" && -f "$bin" && -w "$bin" && -w "$(dirname "$bin")" ]] || return 0
  if ! command -v go >/dev/null; then
    build_error="go isn't installed"
    return
  fi
  if out=$("$dir/scripts/generate.sh" --no-docs 2>&1 && cd "$dir/backend" \
    && CGO_ENABLED=0 go build -trimpath -o "$bin.new" ./cmd/axiom 2>&1 && mv -f "$bin.new" "$bin"); then
    rebuilt=true
  else
    rm -f "$bin.new"
    build_error=$(printf '%s\n' "$out" | grep -m 1 . || echo "the build failed")
  fi
}

if [[ "$channel" != "tags" && "$channel" != "main" ]]; then
  emit "unknown channel: $channel"
  exit 2
fi

if ! g rev-parse --git-dir >/dev/null 2>&1; then
  blocked=nogit
  emit "$dir is not a git clone"
  exit 0
fi

branch=$(g symbolic-ref --quiet --short HEAD 2>/dev/null || true)
remote=$( [[ -n "$branch" ]] && g config "branch.$branch.remote" 2>/dev/null || true)
remote=${remote:-origin}
# The branch the main channel found on the remote, over a stale one
fetched=""

fetch() {
  local err="" ok=false
  if [[ "$channel" == "tags" ]]; then
    err=$(timeout 60 git -C "$dir" fetch --quiet --force --no-tags "$remote" 'refs/tags/v*:refs/tags/v*' 2>&1) && ok=true
  else
    # Tags too, so the installed version still reads as one
    local b
    for b in main master; do
      if err=$(timeout 60 git -C "$dir" fetch --quiet --force --no-tags "$remote" 'refs/tags/v*:refs/tags/v*' \
        "+refs/heads/$b:refs/remotes/$remote/$b" 2>&1); then
        ok=true
        fetched=$b
        break
      fi
      grep -q "couldn't find remote ref" <<<"$err" || break
    done
  fi
  if ! $ok; then
    # Offline: still report the installed version, from the refs we have
    inspect
    emit "$(first_error "${err:-fetch from $remote timed out}")"
    exit 0
  fi
}

# git's reason, rather than its closing advice
first_error() {
  printf '%s\n' "$1" | grep -m 1 -E '^(fatal|error):' | sed -E 's/^(fatal|error): //' || printf '%s\n' "$1" | tail -n 1
}

# Fills current/commit/latest/state/ahead/behind/blocked/notes, and ref (what
# an update moves to)
inspect() {
  current=$(g describe --tags --abbrev=0 --match 'v*' HEAD 2>/dev/null || true)
  commit=$(g rev-parse --short HEAD)
  state="" ahead=false behind=0 blocked="" notes="" latest="" ref=""
  if [[ "$channel" == "tags" ]]; then
    latest=$(g tag -l 'v*' --sort=-v:refname | head -n 1)
    [[ -z "$latest" ]] && return
    ref=$latest
    notes=$(g tag -l --format='%(contents)' "$latest" | sed -e '/^-----BEGIN PGP SIGNATURE-----/,$d')
  else
    local b
    for b in ${fetched:-} main master; do
      if g rev-parse --quiet --verify "refs/remotes/$remote/$b" >/dev/null; then
        ref="refs/remotes/$remote/$b"
        break
      fi
    done
    [[ -z "$ref" ]] && return
    latest=$(g rev-parse --short "$ref")
  fi
  if g merge-base --is-ancestor "$ref" HEAD; then
    state=uptodate
    [[ "$(g rev-parse HEAD)" != "$(g rev-parse "$ref^{commit}")" ]] && ahead=true
    return
  fi
  if g merge-base --is-ancestor HEAD "$ref"; then
    state=available
    behind=$(g rev-list --count "HEAD..$ref")
    [[ "$channel" == "main" ]] && notes=$(g log --no-merges --format='- %s' -n 30 "HEAD..$ref")
  else
    state=diverged
    blocked=diverged
    return
  fi
  if [[ -n "$branch" && "$branch" != "main" && "$branch" != "master" ]]; then
    blocked=branch
  elif [[ -n "$(g status --porcelain --untracked-files=no)" ]]; then
    blocked=dirty
  fi
}

case "$action" in
check)
  fetch
  inspect
  emit
  ;;
apply)
  [[ -z "$target" ]] && { emit "no target given"; exit 1; }
  inspect
  if [[ "$state" != "available" || "$latest" != "$target" ]]; then
    emit "$target is not an available update"
    exit 1
  fi
  if [[ -n "$blocked" ]]; then
    emit "blocked: $blocked"
    exit 1
  fi
  if [[ -n "$branch" ]]; then
    out=$(g merge --ff-only --quiet "$ref" 2>&1)
  else
    out=$(g checkout --quiet --detach "$ref" 2>&1)
  fi
  status=$?
  inspect
  if [[ $status -ne 0 ]]; then
    emit "$(first_error "$out")"
    exit 1
  fi
  rebuild
  emit
  ;;
*)
  echo "Usage: $0 [--channel tags|main] check [dir] | apply <target> [dir]" >&2
  exit 2
  ;;
esac
