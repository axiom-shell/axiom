#!/usr/bin/env bash
#
# Description: the "Daily habits" custom widget's script (a starter: the
#              Custom widgets page, From a preset, Daily habits). A poll script
#              and its action command in one:
#                habits.sh show                 print the widget's output (JSON)
#                habits.sh do ACTION [VALUE]    run an action, print nothing:
#                  check ID     mark habit ID done today (streaks count days in a row)
#                  add NAME     add a habit
#                  remove ID    delete a habit
#                  undo         put the habits back as before the last change
#              The habits are a file, so they outlive the shell:
#                ${XDG_STATE_HOME:-$HOME/.local/state}/axiom/habits.tsv
#                (id, name, last day done, streak: tab separated; "-" for never)
#              and habits.tsv.prev, what undo goes back to. A bad id or name
#              exits 2 with a line on stderr.

set -u

state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/axiom
tsv=$state_dir/habits.tsv
prev=$tsv.prev
lock=$tsv.lock

die() {
  echo "habits: $*" >&2
  exit 2
}

# A string as a JSON string: control characters become spaces
json_str() {
  local s=$1
  s=${s//[[:cntrl:]]/ }
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  printf '"%s"' "$s"
}

today=$(date +%F)
yesterday=$(date -d yesterday +%F)

# Runs with the file locked (a directory, so it is atomic and needs nothing
# installed): the changing actions never overlap. A lock left behind
# (killed mid-change) is broken after 5 s, far longer than a change takes;
# after 10 s of waiting it gives up
lock_file() {
  local tries=0
  while ! mkdir "$lock" 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -lt 100 ] || die "can't lock $tsv"
    [ "$tries" -ne 50 ] || rmdir "$lock" 2>/dev/null
    sleep 0.1
  done
  trap 'rmdir "$lock" 2>/dev/null' EXIT
}

show() {
  local id name last streak total=0 done_count=0 items="" shown state icon status
  if [ -r "$tsv" ]; then
    while IFS=$'\t' read -r id name last streak || [ -n "${id:-}" ]; do
      [ -n "$id" ] || continue
      total=$((total + 1))
      shown=0
      if [ "$last" = "$today" ] || [ "$last" = "$yesterday" ]; then
        shown=$streak
      fi
      if [ "$last" = "$today" ]; then
        done_count=$((done_count + 1))
        status="done"
        icon=check_circle
      else
        status=open
        icon=radio_button_unchecked
      fi
      [ -z "$items" ] || items+=","
      items+="{\"id\":$(json_str "$id"),\"text\":$(json_str "$name"),\"icon\":\"$icon\",\"subtext\":\"$shown day$([ "$shown" = 1 ] || echo s)\",\"state\":\"$status\"}"
    done <"$tsv"
  fi
  if [ "$total" -eq 0 ]; then
    state=empty
  elif [ "$done_count" -eq "$total" ]; then
    state="done"
  else
    state=open
  fi
  local actions='"add":{}'
  [ "$total" -eq 0 ] || actions+=',"check":{}'
  [ "$total" -eq 0 ] || actions+=',"remove":{}'
  [ ! -e "$prev" ] || actions+=',"undo":{}'
  printf '{"state":"%s","text":"%s/%s","value":%s,"min":0,"max":%s,"items":[%s],"actions":{%s}}\n' \
    "$state" "$done_count" "$total" "$done_count" "$total" "$items" "$actions"
}

# Whether habit `id` is in the file
has_habit() {
  [ -r "$tsv" ] && grep -q -P "^$1\t" "$tsv"
}

# Keeps the file as it is for undo, and puts the new one ($tsv.new) in its place
commit() {
  [ ! -e "$tsv" ] || cp -f "$tsv" "$prev"
  mv -f "$tsv.new" "$tsv"
}

do_action() {
  local action=${1:-} value=${2:-} id name last streak next=0
  mkdir -p "$state_dir" 2>/dev/null || die "can't make $state_dir"
  [ -w "$state_dir" ] || die "can't make $state_dir"
  lock_file
  case "$action" in
  check)
    [[ $value =~ ^[0-9]+$ ]] || die "not a habit id: $value"
    has_habit "$value" || die "no habit $value"
    while IFS=$'\t' read -r id name last streak || [ -n "${id:-}" ]; do
      if [ "$id" = "$value" ] && [ "$last" != "$today" ]; then
        if [ "$last" = "$yesterday" ]; then
          streak=$((streak + 1))
        else
          streak=1
        fi
        last=$today
      fi
      printf '%s\t%s\t%s\t%s\n' "$id" "$name" "$last" "$streak"
    done <"$tsv" >"$tsv.new"
    commit
    ;;
  add)
    name=${value//[[:cntrl:]]/ }
    name=${name#"${name%%[![:space:]]*}"}
    name=${name%"${name##*[![:space:]]}"}
    [ -n "$name" ] || die "a habit needs a name"
    name=${name:0:80}
    if [ -r "$tsv" ]; then
      while IFS=$'\t' read -r id _ || [ -n "${id:-}" ]; do
        [ "$id" -gt "$next" ] 2>/dev/null && next=$id
      done <"$tsv"
    fi
    {
      [ ! -r "$tsv" ] || sed '$a\' "$tsv"
      printf '%s\t%s\t-\t0\n' $((next + 1)) "$name"
    } >"$tsv.new"
    commit
    ;;
  remove)
    [[ $value =~ ^[0-9]+$ ]] || die "not a habit id: $value"
    has_habit "$value" || die "no habit $value"
    grep -v -P "^$value\t" "$tsv" >"$tsv.new"
    commit
    ;;
  undo)
    [ -e "$prev" ] || die "nothing to undo"
    mv -f "$prev" "$tsv"
    ;;
  *)
    die "unknown action: $action"
    ;;
  esac
}

case "${1:-}" in
show) show ;;
do) do_action "${2:-}" "${3:-}" ;;
*) die "usage: habits.sh show | do ACTION [VALUE]" ;;
esac
