#!/usr/bin/env bash
#
# Description: the scripts behind the Custom widgets page's templates (New,
#              Interactive card): each template's poll script and its
#              actions' commands in one, so a template works the moment it is
#              added.
#                demo.sh TEMPLATE VERB [ARG]
#                  toggle  show | on | off
#                  slider  show | set N      (N: a number, cut to a whole 0-100)
#                  list    show              (the mounted disks; the row's
#                                             action opens one: xdg-open)
#                  media   show | prev | toggle | next    (three fixed tracks)
#                  status  show | break | fix
#              `show` prints the widget's output (JSON); the others change the
#              state and print nothing. The state is a few small files in
#                ${XDG_STATE_HOME:-$HOME/.local/state}/axiom/custom-widgets-demo/
#              (each written as a temp file and moved in). A bad template,
#              verb or value exits 2 with a `demo: ...` line on stderr.

set -u

state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/axiom/custom-widgets-demo

die() {
  echo "demo: $*" >&2
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

# The state file `$1`'s first line ("" when there is none)
read_state() {
  local line=""
  [ ! -r "$state_dir/$1" ] || IFS= read -r line <"$state_dir/$1" || true
  printf '%s' "$line"
}

# Writes `$2` as the state file `$1`
write_state() {
  mkdir -p "$state_dir" 2>/dev/null || die "can't make $state_dir"
  [ -w "$state_dir" ] || die "can't write $state_dir"
  printf '%s\n' "$2" >"$state_dir/$1.new" || die "can't write $state_dir"
  mv -f "$state_dir/$1.new" "$state_dir/$1" || die "can't write $state_dir"
}

# Toggle: on | off (off at first)
toggle() {
  local now
  now=$(read_state toggle)
  [ "$now" = on ] || now=off
  case "$1" in
  show) printf '{"text":"Focus mode","state":"%s"}\n' "$now" ;;
  on | off) write_state toggle "$1" ;;
  *) die "unknown verb for toggle: $1" ;;
  esac
}

# Slider: 0 to 100 (50 at first)
slider() {
  local now neg="" whole
  now=$(read_state slider)
  [[ $now =~ ^[0-9]+$ ]] || now=50
  case "$1" in
  show) printf '{"text":"Desk lamp","value":%s,"min":0,"max":100,"unit":"%%"}\n' "$now" ;;
  set)
    local arg=${2:-}
    [[ $arg =~ ^-?([0-9]+(\.[0-9]*)?|\.[0-9]+)$ ]] || die "not a number: $arg"
    case "$arg" in -*)
      neg=1
      arg=${arg#-}
      ;;
    esac
    whole=${arg%%.*}
    whole=${whole:-0}
    if [ -n "$neg" ]; then
      whole=0
    elif [ "${#whole}" -gt 9 ]; then
      whole=100
    else
      whole=$((10#$whole))
      [ "$whole" -le 100 ] || whole=100
    fi
    write_state slider "$whole"
    ;;
  *) die "unknown verb for slider: $1" ;;
  esac
}

# List: the mounted disks, one row each
list() {
  [ "$1" = show ] || die "unknown verb for list: $1"
  local _fs _size _used avail cap mount n=0 items="" free state
  while read -r _fs _size _used avail cap mount; do
    [ -n "$mount" ] || continue
    n=$((n + 1))
    cap=${cap%\%}
    [[ $cap =~ ^[0-9]+$ ]] || cap=0
    [[ $avail =~ ^[0-9]+$ ]] || avail=0
    if [ "$avail" -ge 1073741824 ]; then
      free="$((avail / 1073741824)).$((avail % 1073741824 * 10 / 1073741824)) TB"
    elif [ "$avail" -ge 1048576 ]; then
      free="$((avail / 1048576)) GB"
    else
      free="$((avail / 1024)) MB"
    fi
    state=ok
    [ "$cap" -lt 90 ] || state=full
    [ -z "$items" ] || items+=","
    items+="{\"id\":$(json_str "$mount"),\"text\":$(json_str "$mount"),\"subtext\":\"$free free\",\"value\":$cap,\"max\":100,\"state\":\"$state\"}"
  done < <(df -P -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null | tail -n +2)
  printf '{"text":"%s disk%s","items":[%s]}\n' "$n" "$([ "$n" = 1 ] || echo s)" "$items"
}

titles=("Blue Hour" "Night Drive" "Last Train Home")
artists=("The Lanterns" "Velvet Static" "Paper Moons")

# Media: a track (0-2) and playing | paused | stopped ("1 playing" at first)
media() {
  local now idx status
  now=$(read_state media)
  idx=${now%% *}
  status=${now#* }
  if [[ ! $idx =~ ^[0-2]$ ]] || [[ $status != playing && $status != paused && $status != stopped ]]; then
    idx=1
    status=playing
  fi
  case "$1" in
  show)
    if [ "$status" = stopped ]; then
      printf '{"state":"stopped","text":"","subtext":"","icon":"play_arrow"}\n'
    else
      printf '{"state":"%s","text":%s,"subtext":%s,"icon":"%s"}\n' "$status" "$(json_str "${titles[idx]}")" "$(json_str "${artists[idx]}")" "$([ "$status" = playing ] && echo pause || echo play_arrow)"
    fi
    ;;
  toggle)
    case "$status" in
    playing) status=paused ;;
    *) status=playing ;;
    esac
    write_state media "$idx $status"
    ;;
  next)
    if [ "$status" = stopped ]; then
      idx=0
      status=playing
    elif [ "$idx" -ge 2 ]; then
      idx=0
      status=stopped
    else
      idx=$((idx + 1))
    fi
    write_state media "$idx $status"
    ;;
  prev)
    if [ "$status" = stopped ]; then
      idx=2
    elif [ "$idx" -gt 0 ]; then
      idx=$((idx - 1))
    fi
    status=playing
    write_state media "$idx $status"
    ;;
  *) die "unknown verb for media: $1" ;;
  esac
}

# Status: ok | down (ok at first). Down prints an `error`, still exit 0: the
# widget fails by its output, so its actions stay on to fix it
status() {
  local now
  now=$(read_state status)
  [ "$now" = down ] || now=ok
  case "$1" in
  show)
    if [ "$now" = down ]; then
      printf '{"error":"The demo service is down","state":"down"}\n'
    else
      printf '{"text":"All good","subtext":"Checked at %s","state":"ok"}\n' "$(date +%H:%M)"
    fi
    ;;
  break) write_state status down ;;
  fix) write_state status ok ;;
  *) die "unknown verb for status: $1" ;;
  esac
}

verb=${2:-}
[ -n "$verb" ] || die "usage: demo.sh TEMPLATE VERB [ARG]"
case "${1:-}" in
toggle) toggle "$verb" ;;
slider) slider "$verb" "${3:-}" ;;
list) list "$verb" ;;
media) media "$verb" ;;
status) status "$verb" ;;
*) die "unknown template: ${1:-}" ;;
esac
