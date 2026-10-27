#!/bin/sh
#
# Description: greetd's greeter command, as axiom greeter-install points
#              default_session at it (run as greetd's user, from the
#              installed copy):
#                greeter-session.sh         axiom's greeter in a compositor
#                                           of its own: sway (sway.conf
#                                           beside this), else Hyprland
#                                           (hyprland.lua), also when sway
#                                           can't start; if neither can,
#                                           greetd's text greeter, agreety,
#                                           so a login is always possible
#                greeter-session.sh shell   (from that compositor) the
#                                           greeter itself (axiom greeter:
#                                           it loads the bundle and runs
#                                           greeter.qml on it), its log in the
#                                           greeter's state folder
#                                           (greeter.log); if it fails
#                                           without starting a session, once
#                                           more on its fallback config
#                                           only; then the compositor exits,
#                                           and greetd starts the session or
#                                           the greeter again (agreety
#                                           instead, when the second try
#                                           failed too)

here=$(dirname "$(readlink -f "$0")")
install=$(cd "$here/../.." && pwd)
copy=$install
# A packaged axiom (axiom greeter-install's package source): the code is the
# package's own, root's like this folder, which holds only these scripts
# and the fallback snapshot
if [ -f "$install/.greeter-source" ]; then
  read -r kind dir <"$install/.greeter-source"
  [ "$kind" = package ] && [ -f "$dir/greeter.qml" ] && copy=$dir
fi
# Where axiom greeter and ThemeManager find that snapshot
export AXIOM_GREETER_FALLBACK="$install/fallback/"
# The axiom binary: the install's own copy (root's), else a packaged one
axiom="$install/bin/axiom"
[ -x "$axiom" ] || axiom=$(command -v axiom) || axiom=false
# Left by `shell` when the greeter failed twice: in greetd's user's own
# folders (its runtime dir, else the greeter's state folder), never a
# shared one another user could plant it in
failed="${XDG_RUNTIME_DIR:-/var/lib/axiom-greeter/state}/axiom-greeter-failed"
# greetd's user has / for a home, which it can't write: caches (the
# compositor's, Quickshell's QML cache) go to the greeter's own state folder
state=/var/lib/axiom-greeter/state
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$state/cache}"

case "${1:-}" in
shell)
  # The greeter's log, kept past its session (greetd's user's runtime dir,
  # where qs keeps its own, goes with it): this start's only
  log="$state/greeter.log"
  true 2>/dev/null >"$log" || log=/dev/null
  if ! "$axiom" greeter --tree "$copy" 2>>"$log"; then
    echo "axiom greeter: failed, trying its fallback config" >>"$log"
    "$axiom" greeter --tree "$copy" --safe 2>>"$log" || : >"$failed"
  fi
  if [ -n "${SWAYSOCK:-}" ]; then
    swaymsg exit >/dev/null
  else
    hyprctl dispatch 'hl.dsp.exit()' >/dev/null
  fi
  ;;
*)
  rm -f "$failed"
  # sway first: it exits 0 once the greeter is done, non-zero when it
  # couldn't start at all (then Hyprland is tried). NVIDIA's driver needs
  # sway told it's fine.
  if command -v sway >/dev/null; then
    gpu=""
    [ -d /sys/module/nvidia ] && gpu=--unsupported-gpu
    # Its log beside the greeter's (nowhere, if that can't be written)
    clog="$state/compositor.log"
    true 2>/dev/null >"$clog" || clog=/dev/null
    # shellcheck disable=SC2086
    if sway $gpu --config "$here/sway.conf" 2>>"$clog"; then
      [ ! -e "$failed" ] && exit 0
    elif [ ! -e "$failed" ] && command -v start-hyprland >/dev/null; then
      echo "axiom greeter: sway didn't start, trying Hyprland" >&2
      start-hyprland -- --config "$here/hyprland.lua" && [ ! -e "$failed" ] && exit 0
    fi
  elif command -v start-hyprland >/dev/null; then
    start-hyprland -- --config "$here/hyprland.lua" && [ ! -e "$failed" ] && exit 0
  fi
  rm -f "$failed"
  echo "axiom greeter: didn't start, falling back to agreety" >&2
  # greetd runs the command through sh in the new session, where SHELL
  # is the login shell of whoever logs in (not greetd's user's)
  # shellcheck disable=SC2016
  exec agreety --cmd '${SHELL:-/bin/sh}'
  ;;
esac
