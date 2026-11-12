#!/usr/bin/env bash
#
# Description: Installs axiom on Arch Linux, Fedora, or a distribution based
#              on either (CachyOS, EndeavourOS, Manjaro, Nobara, …): a
#              compositor (Hyprland, sway or niri: the one you run or have,
#              else your pick), axiom's packages, the latest release in
#              ~/.local/share/axiom-shell, and (if you agree) the line in
#              the compositor's config that starts it; from a text console
#              it then offers to start the compositor. Everything after
#              that, keybinds included, is axiom's own Settings → Desktop →
#              Compositor.
# Usage:       curl -fsSL https://raw.githubusercontent.com/axiom-shell/axiom/main/install.sh | bash
#              ./install.sh [options]   (from a clone anywhere: it installs
#                the latest release all the same, then offers to make the
#                clone axiom's dev tree, `axiom dev set`)
#                --yes          answer yes to every question
#                --minimal      required packages only, and no other changes
#                --compositor hyprland|sway|niri|none
#                               the compositor to install and start axiom
#                               from, without asking (none: neither)
#                --dry-run      print every command it would run; change
#                               nothing
#                --uninstall    take axiom out again: `axiom uninstall` (it
#                               asks what to keep: your settings; notes,
#                               to-dos, themes, wallpapers and calendars;
#                               saved passwords: by default all), then the
#                               binary and the install (a clone with changes
#                               of your own is left). A package is removed
#                               with its package manager. With it: --yes
#                               --dry-run --purge-all (keep nothing)
#                               --restore-system (put back the default apps
#                               and input methods axiom set)
#                               --no-portal-restart --answers <file>
#              AXIOM_REPO and AXIOM_DIR override the install's source and
#              folder. Safe to run again: nothing is installed or added twice.
#              sudo runs only for the package manager (and on Fedora to
#              enable a COPR), each time after showing the command.

set -euo pipefail

# Wrapped in main so bash reads all of it before running any of it: under
# curl | bash, anything reading stdin would otherwise eat the rest
main() {
AXIOM_REPO=${AXIOM_REPO:-https://github.com/axiom-shell/axiom.git}
# The official builds (release.Official): a v* tag's release, or edge,
# main's newest build, each with a SHA256SUMS listing its files
AXIOM_RELEASES=${AXIOM_RELEASES:-https://github.com/axiom-shell/axiom/releases/download}
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
# The install, where `axiom run` looks first (tree.Installed)
AXIOM_DIR=${AXIOM_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/axiom-shell}
# An AUR (or other) package's copy, with the marker its PKGBUILD writes
PACKAGED_DIR=/usr/share/axiom-shell

# What installs each key (Packages.packages' keys, checked against it by
# scripts/check_packages.py): key|Arch|Fedora, each a package name,
# "owner/project:name" (from that COPR), "-" (nothing needed there) or
# "n/a" (not packaged there)
PACKAGES=(
  "git|git|git"
  "go|go|golang"
  "quickshell|quickshell|errornointernet/quickshell:quickshell"
  "curl|curl|curl"
  "hyprland|hyprland|nett00n/hyprland:hyprland"
  "sway|sway|sway"
  "niri|niri|niri"
  "secret-tool|libsecret|libsecret"
  "gio|glib2|glib2"
  "nmcli|networkmanager|NetworkManager"
  "nm-connection-editor|nm-connection-editor|nm-connection-editor"
  "checkupdates|pacman-contrib|-"
  "wf-recorder|wf-recorder|wf-recorder"
  "pactl|libpulse|pulseaudio-utils"
  "grim|grim|grim"
  "satty|satty|nett00n/hyprland:satty"
  "qalc|libqalculate|qalculate"
  "ddcutil|ddcutil|ddcutil"
  "wlsunset|wlsunset|wlsunset"
  "xwayland-satellite|xwayland-satellite|xwayland-satellite"
  "Xwayland|xorg-xwayland|xorg-x11-server-Xwayland"
  "powerprofilesctl|power-profiles-daemon|power-profiles-daemon"
  "udisksctl|udisks2|udisks2"
  "accountsservice|accountsservice|accountsservice"
  "xdg-desktop-portal-gtk|xdg-desktop-portal-gtk|xdg-desktop-portal-gtk"
  "xdg-desktop-portal-hyprland|xdg-desktop-portal-hyprland|nett00n/hyprland:xdg-desktop-portal-hyprland"
  "xdg-desktop-portal-wlr|xdg-desktop-portal-wlr|xdg-desktop-portal-wlr"
  "xdg-desktop-portal-gnome|xdg-desktop-portal-gnome|xdg-desktop-portal-gnome"
  "greetd|greetd|greetd"
  "agreety|greetd-agreety|greetd"
  "fcitx5|fcitx5|fcitx5"
  "ibus-daemon|ibus|ibus"
  "qt6-imageformats|qt6-imageformats|qt6-qtimageformats"
  "kimageformats|kimageformats|kf6-kimageformats"
  "libavif|libavif|-"
  "libjxl|libjxl|-"
)
# go isn't here: the axiom binary is downloaded (a package brings its own),
# and go is installed only to build it when there's no official build
REQUIRED=(git quickshell curl)
# "feature|keys|compositors" (none listed: any), offered one at a time;
# the AUR package's optdepends say the same
FEATURES=(
  "Calendar accounts and feeds|secret-tool|"
  "Moving deleted notes to the trash|gio|"
  "Wi-Fi menu and network widget|nmcli|"
  "Adding and editing VPNs (the VPN menu's edit button)|nm-connection-editor|"
  "Package update checks|checkupdates|"
  "Screen recording|wf-recorder|"
  "The system's sound in screen recordings|pactl|"
  "Screenshots under niri|grim|niri"
  "Annotating screenshots|satty|"
  "Launcher calculator|qalc|"
  "Brightness keys and OSD bar on external monitors (DDC/CI)|ddcutil|"
  "Night light|wlsunset|niri"
  "X11 apps under niri (Steam, games, older apps)|xwayland-satellite|niri"
  "X11 apps under sway (Steam, games, older apps)|Xwayland|sway"
  "Power profiles|powerprofilesctl|"
  "Removable drives (mount, open and eject USB sticks and memory cards)|udisksctl|"
  "Your picture on the login screen, and your real name in Settings|accountsservice|"
  "Browse buttons for folders and importing configs (the desktop's file picker)|xdg-desktop-portal-gtk|"
  "Screen sharing under Hyprland (calls, streams)|xdg-desktop-portal-hyprland|hyprland"
  "Screen sharing under sway (calls, streams)|xdg-desktop-portal-wlr|sway"
  "Screen sharing under niri (calls, streams)|xdg-desktop-portal-gnome|niri"
  # fcitx5 is Input.keyboard.method's default; ibus (in PACKAGES for the install
  # hints) is supported but not offered, so "all" doesn't take both
  "Typing Japanese, Chinese, Korean and more (the fcitx5 input method)|fcitx5|"
  "WebP wallpapers|qt6-imageformats|"
  "AVIF and JPEG XL wallpapers|kimageformats libavif libjxl|"
  # The login screen runs in a sway of its own, or in Hyprland where sway
  # isn't installed: with Hyprland, sway is offered on its own (recommended,
  # so "all" takes it) and declining it keeps the login screen. The first
  # entry matching a compositor wins, so Hyprland's come first
  "Axiom as the login screen (set up later from Settings → Login screen)|greetd agreety|hyprland"
  "sway for the login screen to run in (recommended; without it, it runs in Hyprland)|sway|hyprland"
  "Axiom as the login screen (set up later from Settings → Login screen)|greetd agreety sway|"
)
MIN_QS=0.3.2
MIN_HYPRLAND=0.55.0
# What axiom is checked against; older ones may lack something
TESTED_SWAY=1.12
TESTED_NIRI=26.04
# The text each *ConfigWriter's autostartTarget writes (the binary by its
# path: a compositor's PATH may not have it), and the `accept` pattern
# that finds a line already starting axiom (Paths.startPattern's): `axiom
# run`
autostart_line() {
  local start="'$AXIOM_BIN' run"
  case "$1" in
  hyprland) echo "hl.on(\"hyprland.start\", function() hl.exec_cmd(\"$start\") end) -- axiom" ;;
  sway) echo "exec $start" ;;
  niri) echo "spawn-sh-at-startup \"$start\"" ;;
  esac
}
STARTS_AXIOM="(^|[[:space:]'\"/])axiom['\"]? +run([^[:alnum:]_-]|\$)"

mode=ask dry_run=0 compositor_flag=""
uninstall=0 uninstall_args=() uninstall_only=()
while (($#)); do
  case "$1" in
  --yes | -y) mode=yes ;;
  --minimal) mode=minimal ;;
  --dry-run) dry_run=1 ;;
  --uninstall) uninstall=1 ;;
  --purge-all | --restore-system | --no-portal-restart)
    uninstall_args+=("$1")
    uninstall_only+=("$1")
    ;;
  --answers | --answers=*)
    uninstall_only+=("${1%%=*}")
    if [[ "$1" == *=* ]]; then
      uninstall_args+=("$1")
    else
      uninstall_args+=("$1" "${2:?--answers takes a file}")
      shift
    fi
    ;;
  --compositor | --compositor=*)
    if [[ "$1" == *=* ]]; then
      compositor_flag=${1#*=}
    else
      compositor_flag=${2:-}
      shift
    fi
    case "$compositor_flag" in
    hyprland | sway | niri | none) ;;
    *)
      echo "--compositor takes hyprland, sway, niri or none (not \"$compositor_flag\")" >&2
      exit 2
      ;;
    esac
    ;;
  --help | -h)
    sed -n '3,37p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "Unknown option: $1 (try --help)" >&2
    exit 2
    ;;
  esac
  shift
done

if ((!uninstall && ${#uninstall_only[@]})); then
  echo "${uninstall_only[0]} only goes with --uninstall (try --help)" >&2
  exit 2
fi

if [[ -t 1 ]]; then
  bold=$'\e[1m' blue=$'\e[34m' yellow=$'\e[33m' red=$'\e[31m' green=$'\e[32m' reset=$'\e[0m'
else
  bold="" blue="" yellow="" red="" green="" reset=""
fi
info() { printf '%s::%s %s\n' "$blue$bold" "$reset" "$*"; }
ok() { printf '%s::%s %s\n' "$green$bold" "$reset" "$*"; }
warn() { printf '%swarning:%s %s\n' "$yellow$bold" "$reset" "$*" >&2; }
die() {
  printf '%serror:%s %s\n' "$red$bold" "$reset" "$*" >&2
  exit 1
}
joined() {
  local IFS=,
  local text="$*"
  printf '%s' "${text//,/, }"
}

# Under curl | bash stdin is this script, so questions and the package
# manager read the terminal instead
if { : </dev/tty; } 2>/dev/null; then
  have_tty=1
else
  have_tty=0
fi
interactive() { [[ "$mode" == ask ]] && ((have_tty)); }

# ask "question" [default y|n]: in --yes mode yes, in --minimal mode or
# without a terminal no
ask() {
  local default=${2:-y} hint answer
  [[ "$mode" == yes ]] && return 0
  [[ "$mode" == minimal ]] && return 1
  # No terminal to ask on: change nothing unasked (--yes says otherwise)
  ((have_tty)) || return 1
  [[ "$default" == y ]] && hint="[Y/n]" || hint="[y/N]"
  printf '%s::%s %s %s ' "$blue$bold" "$reset" "$1" "$hint"
  read -r answer </dev/tty || answer=""
  answer=${answer:-$default}
  [[ "$answer" == [yY]* ]]
}

# run command...: runs it, or under --dry-run only prints it
run() {
  if ((dry_run)); then
    printf '   %swould run:%s %s\n' "$yellow" "$reset" "$*"
    return 0
  fi
  "$@"
}

# append_line file line: adds the line at the end of the file (a newline
# first if its last line has none)
append_line() {
  if ((dry_run)); then
    printf '   %swould add to %s:%s %s\n' "$yellow" "$1" "$reset" "$2"
    return 0
  fi
  [[ -s "$1" && -n "$(tail -c1 "$1")" ]] && echo >>"$1"
  printf '%s\n' "$2" >>"$1"
}

# version_at_least have want
version_at_least() {
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]
}

first_version() { grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1; }

is_axiom_clone() { [[ -f "$1/qml/shell.qml" && -f "$1/backend/go.mod" ]] && git -C "$1" rev-parse --git-dir >/dev/null 2>&1; }
same_dir() { [[ "$(readlink -f "$1" 2>/dev/null)" == "$(readlink -f "$2" 2>/dev/null)" ]]; }

# ─── Uninstall ───────────────────────────────────────────────────────────────

# --uninstall: `axiom uninstall` takes axiom's footprint out of your home and
# session (asking what to keep, unless --yes; docs/dev/backend/uninstall.md);
# then, unless axiom is a package, this takes away what only this script
# put there: the binary and the install. Nothing here needs a package
# manager, and nothing runs as root
do_uninstall() {
  ((EUID != 0)) || die "Run this as your own user, not root: axiom's files are in your home."
  local bin_home=${XDG_BIN_HOME:-$HOME/.local/bin}
  local script_dir="" default_dir=${XDG_DATA_HOME:-$HOME/.local/share}/axiom-shell
  [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]] && script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  local is_package=0
  [[ -f "$PACKAGED_DIR/.packaged" ]] && [[ ! -f "$AXIOM_DIR/qml/shell.qml" ]] && is_package=1
  local bin=$bin_home/axiom
  ((is_package)) && bin=/usr/bin/axiom
  [[ -x "$bin" ]] || bin=$(command -v axiom || true)
  [[ -n "$bin" ]] || die "axiom's binary isn't at $bin_home/axiom or on your PATH: there is nothing to run \`axiom uninstall\` with. Remove $AXIOM_DIR by hand."

  local args=(uninstall --stop)
  [[ "$mode" == yes ]] && args+=(--yes)
  ((dry_run)) && args+=(--dry-run)
  args+=("${uninstall_args[@]}")
  if ((dry_run)); then
    info "Running axiom uninstall --dry-run: nothing is changed"
  else
    info "Running axiom uninstall"
  fi
  # Its questions are asked on the terminal, also under curl | bash
  if [[ "$mode" != yes ]] && ((have_tty)); then
    "$bin" "${args[@]}" </dev/tty || die "axiom uninstall failed: nothing else was removed."
  else
    "$bin" "${args[@]}" || die "axiom uninstall failed: nothing else was removed."
  fi

  if ((is_package)); then
    info "Remove the package: sudo pacman -R axiom-shell (or axiom-shell-git)"
    return 0
  fi
  # The binary this script installed, when it is axiom's
  if [[ "$bin" == "$bin_home/axiom" && -e "$bin" ]]; then
    if "$bin" version 2>/dev/null | grep -q '^axiom '; then
      run rm -f -- "$bin"
      ((dry_run)) || ok "Removed $bin"
    fi
  fi
  # The install: its default folder, or the tree this runs from, when it is
  # a tree of axiom's (qml/shell.qml). A clone with changes of its own, or of
  # another repository, is never removed: the command is listed instead
  if [[ -f "$AXIOM_DIR/qml/shell.qml" ]]; then
    if { same_dir "$AXIOM_DIR" "$default_dir" || { [[ -n "$script_dir" ]] && same_dir "$AXIOM_DIR" "$script_dir"; }; }; then
      local why=""
      if git -C "$AXIOM_DIR" rev-parse --git-dir >/dev/null 2>&1; then
        if [[ -n "$(git -C "$AXIOM_DIR" status --porcelain 2>/dev/null)" ]]; then
          why="it has changes of your own"
        elif [[ "$(git -C "$AXIOM_DIR" remote get-url origin 2>/dev/null)" != "$AXIOM_REPO" ]]; then
          why="its origin isn't $AXIOM_REPO"
        fi
      fi
      if [[ -n "$why" ]]; then
        info "Left $AXIOM_DIR ($why). Remove it yourself when you're sure: rm -rf '$AXIOM_DIR'"
      else
        run rm -rf -- "$AXIOM_DIR"
        ((dry_run)) || ok "Removed $AXIOM_DIR"
      fi
    else
      info "Left $AXIOM_DIR: it isn't the install's default folder or the tree this runs from. Remove it yourself if you want: rm -rf '$AXIOM_DIR'"
    fi
  fi
  return 0
}

if ((uninstall)); then
  do_uninstall
  exit 0
fi

# ─── The distribution ────────────────────────────────────────────────────────

OS_RELEASE=/etc/os-release
[[ -f "$OS_RELEASE" ]] || OS_RELEASE=/usr/lib/os-release

# The family whose packages this is: its os-release ID, else the first of
# its ID_LIKE that's one (Packages.distroFamily's rule)
distro_family() {
  local id
  # shellcheck disable=SC1090 # os-release is KEY=value shell, by its spec
  for id in $(. "$OS_RELEASE" 2>/dev/null && echo "${ID:-}" "${ID_LIKE:-}"); do
    case "${id,,}" in
    arch | fedora)
      echo "${id,,}"
      return
      ;;
    esac
  done
  [[ -f /etc/arch-release ]] && echo arch
  return 0
}

# The distribution's name, for messages
os_name() {
  # shellcheck disable=SC1090
  ( . "$OS_RELEASE" && echo "${PRETTY_NAME:-${NAME:-${ID:?}}}") 2>/dev/null || echo "an unknown distribution"
}

distro=$(distro_family)
case "$distro" in
arch)
  command -v pacman >/dev/null || distro=""
  distro_name=Arch
  column=2
  ;;
fedora)
  command -v dnf >/dev/null || distro=""
  distro_name=Fedora
  column=3
  ;;
esac
[[ -n "$distro" ]] || die "This installer supports Arch Linux, Fedora and distributions based on them (this is $(os_name)). See docs/installation.md for installing by hand."
((EUID != 0)) || die "Run this as your own user, not root: it uses sudo for the package manager only."

# package_of key: what installs it here (a PACKAGES cell)
package_of() {
  local row
  for row in "${PACKAGES[@]}"; do
    if [[ "${row%%|*}" == "$1" ]]; then
      cut -d'|' -f"$column" <<<"$row"
      return
    fi
  done
  echo "$1"
}

# The package's own name, without its COPR
package_name() { echo "${1##*:}"; }
package_copr() { [[ "$1" == */*:* ]] && echo "${1%%:*}" || true; }

# Whether a package (a PACKAGES cell) is installed
installed() {
  case "$1" in
  - | n/a) return 0 ;;
  *)
    if [[ "$distro" == arch ]]; then
      [[ -z "$(pacman -T "$1" 2>/dev/null)" ]]
    else
      rpm -q --whatprovides "$(package_name "$1")" >/dev/null 2>&1
    fi
    ;;
  esac
}

# missing key...: the keys whose package isn't installed, one per line
missing() {
  local key
  for key in "$@"; do
    installed "$(package_of "$key")" || echo "$key"
  done
}

# unavailable key...: the keys with no package here, one per line
unavailable() {
  local key
  for key in "$@"; do
    [[ "$(package_of "$key")" == n/a ]] && echo "$key"
  done
  return 0
}

copr_enabled() {
  local owner=${1%%/*} project=${1#*/}
  compgen -G "/etc/yum.repos.d/_copr*:${owner}:${project}.repo" >/dev/null
}

axiom_running() { pgrep -f '(^|/)axiom run( |$)' >/dev/null; }

# ─── The compositor ──────────────────────────────────────────────────────────

compositor_label() {
  case "$1" in
  hyprland) echo Hyprland ;;
  sway) echo sway ;;
  niri) echo niri ;;
  esac
}

# Its binary, whose presence says it's installed
compositor_binary() {
  case "$1" in
  hyprland) echo Hyprland ;;
  *) echo "$1" ;;
  esac
}

compositor_config() {
  case "$1" in
  hyprland) echo "$CONFIG_HOME/hypr/hyprland.lua" ;;
  sway) echo "$CONFIG_HOME/sway/config" ;;
  niri) echo "$CONFIG_HOME/niri/config.kdl" ;;
  esac
}

# The compositor's own default config, seeding a config that doesn't exist
# yet, so its starter binds (terminal, close window, …) are there too;
# axiom skips taken keys
compositor_default_config() {
  local compositor=$1 file
  case "$compositor" in
  hyprland) set -- /usr/share/hypr/hyprland.lua ;;
  sway) set -- /etc/sway/config ;;
  niri) set -- /usr/share/doc/niri/default-config.kdl /usr/share/niri/default-config.kdl ;;
  esac
  for file in "$@"; do
    [[ -f "$file" ]] && echo "$file" && return
  done
  # A dry run didn't install the compositor that would bring it
  ((dry_run)) && [[ " ${to_install[*]} " == *" $compositor "* ]] && echo "$1"
  return 0
}

# What starts it from a text console
compositor_launcher() {
  case "$1" in
  hyprland) command -v start-hyprland >/dev/null && echo start-hyprland || echo Hyprland ;;
  sway) echo sway ;;
  niri) command -v niri-session >/dev/null && echo niri-session || echo "niri --session" ;;
  esac
}

running_compositor=""
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  running_compositor=hyprland
elif [[ -n "${NIRI_SOCKET:-}" ]]; then
  running_compositor=niri
elif [[ -n "${SWAYSOCK:-}" ]]; then
  running_compositor=sway
fi

installed_compositors=()
for name in hyprland sway niri; do
  command -v "$(compositor_binary "$name")" >/dev/null && installed_compositors+=("$name")
done

# Whether its config already has a line starting axiom (an earlier run, or
# the user's own)
starts_axiom() {
  local target
  target=$(readlink -f "$(compositor_config "$1")" 2>/dev/null) || return 1
  [[ -f "$target" ]] && grep -qE "$STARTS_AXIOM" "$target"
}

# The main compositor: picked (--compositor, or asked with none installed),
# else running, else the installed one already starting axiom, else asked
# among the installed ones. It's the one this session gets into; every
# installed one is offered the line that starts axiom too, each asked
# separately (the login screen's feature installs sway for itself, so sway
# being there doesn't make it the session's)
primary=""
if [[ -n "$compositor_flag" ]]; then
  [[ "$compositor_flag" != none ]] && primary=$compositor_flag
  compositor_how="from --compositor"
elif [[ -n "$running_compositor" ]]; then
  primary=$running_compositor
  compositor_how="running now"
elif ((${#installed_compositors[@]})); then
  compositor_how="installed"
  for name in "${installed_compositors[@]}"; do
    if starts_axiom "$name"; then
      primary=$name
      break
    fi
  done
  if [[ -z "$primary" ]]; then
    primary=${installed_compositors[0]}
    if ((${#installed_compositors[@]} > 1)) && interactive; then
      echo
      info "${bold}Several compositors are installed.${reset} Which one do you use?"
      i=0
      for name in "${installed_compositors[@]}"; do
        i=$((i + 1))
        echo "   $i. $(compositor_label "$name")"
      done
      printf '%s::%s Which one? [1-%s, default 1] ' "$blue$bold" "$reset" "$i"
      read -r answer </dev/tty || answer=""
      if [[ "$answer" =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= i)); then
        primary=${installed_compositors[answer - 1]}
      fi
    fi
  fi
else
  compositor_how="picked"
  primary=hyprland
  if interactive; then
    echo
    info "${bold}No compositor is installed yet.${reset} axiom runs under any of these:"
    cat <<'EOF'
   1. Hyprland (recommended): every feature. The login screen runs in sway
      (offered with it) or, without sway, in Hyprland.
   2. niri: windows in scrolling columns. No blur, no mouse binds, no
      Hyprland-only pages (Monitors, Keybinds' mouse binds, the switcher).
   3. sway: i3-style tiling. Plain sway has no blur or rounded corners;
      SwayFX adds them and replaces sway in place, but this script doesn't
      install it (Arch: the AUR's swayfx; Fedora: COPR swayfx/swayfx).
EOF
    printf '%s::%s Which one? [1/2/3, default 1] ' "$blue$bold" "$reset"
    read -r answer </dev/tty || answer=""
    case "$answer" in
    2 | niri) primary=niri ;;
    3 | sway) primary=sway ;;
    esac
  fi
fi

# The main one first, then the other installed ones (none with
# --compositor none)
compositors=()
if [[ -n "$primary" ]]; then
  compositors=("$primary")
  for name in "${installed_compositors[@]}"; do
    [[ "$name" != "$primary" ]] && compositors+=("$name")
  done
fi

# ─── The clone ───────────────────────────────────────────────────────────────

# Run from a clone (not curl | bash): the install is still a fresh clone of
# the latest release, and this one is offered as the dev tree (`axiom dev
# set`), unless it is the install itself
from_clone=0 clone_dir=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  if is_axiom_clone "$script_dir" && ! same_dir "$script_dir" "$AXIOM_DIR"; then
    clone_dir=$script_dir
    from_clone=1
  fi
fi

# Installed as a package (the AUR's axiom-shell): `axiom run` finds it in
# /usr/share (after ~/.local/share), so no install, unless this runs from a
# clone
packaged=0
[[ -f "$PACKAGED_DIR/.packaged" ]] && ((!from_clone)) && ! is_axiom_clone "$AXIOM_DIR" && packaged=1

# The axiom binary (the shell's parent: `axiom run`): the package's, else
# the install's release build (or built from it) into your home
if ((packaged)); then
  AXIOM_BIN=/usr/bin/axiom
else
  AXIOM_BIN=${XDG_BIN_HOME:-$HOME/.local/bin}/axiom
fi

# official_binary dir out: downloads the official build of dir's checkout
# into out (maintainer, 2026-10-27: "Download, build fallback
# (Recommended)"): its v* tag's release, else edge, main's newest build,
# when that's the commit checked out; each file checked against the
# release's SHA256SUMS. Fails (and says why) when there's none to take
official_binary() (
  # A subshell: its scratch folder goes with it
  dir=$1 out=$2
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) info "There's no official axiom binary for $(uname -m)."; return 1 ;;
  esac
  release=$(git -C "$dir" describe --tags --exact-match --match 'v*' HEAD 2>/dev/null) || release=edge
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  fetch() { curl -fsSL --max-time 300 -o "$tmp/$1" "$AXIOM_RELEASES/$release/$1" 2>/dev/null; }
  checked() { (cd "$tmp" && grep -E "^[0-9a-f]{64} [ *]$1\$" SHA256SUMS | sha256sum -c --status 2>/dev/null); }
  if ! fetch SHA256SUMS; then
    info "No official axiom build of $release to download (offline?)."
    return 1
  fi
  if [[ "$release" == edge ]]; then
    head=$(git -C "$dir" rev-parse HEAD)
    if ! fetch COMMIT || ! checked COMMIT; then
      warn "main's newest build doesn't match its SHA256SUMS."
      return 1
    fi
    if [[ "$(cat "$tmp/COMMIT")" != "$head" ]]; then
      info "main's newest build is of another commit than this clone's (${head:0:12})."
      return 1
    fi
  fi
  if ! fetch "axiom-linux-$arch"; then
    info "The $release build has no binary for this machine."
    return 1
  fi
  if ! checked "axiom-linux-$arch"; then
    warn "The $release build's binary doesn't match its SHA256SUMS."
    return 1
  fi
  chmod 755 "$tmp/axiom-linux-$arch"
  "$tmp/axiom-linux-$arch" version >/dev/null || { warn "The $release build's binary doesn't run here."; return 1; }
  mv -f "$tmp/axiom-linux-$arch" "$out"
  ok "Downloaded axiom's $release build (checked against its SHA256SUMS)"
)

# ─── The plan ────────────────────────────────────────────────────────────────

if ((packaged)); then
  clone_step="none: axiom is installed as a package, at $PACKAGED_DIR"
elif is_axiom_clone "$AXIOM_DIR"; then
  clone_step="none: axiom is installed at $AXIOM_DIR (left as it is)"
else
  clone_step="a clone of the latest release at $AXIOM_DIR"
fi
((from_clone)) && clone_step+=$'\n      (not this clone: it can be axiom\'s dev tree instead, asked at the end)'
if ((${#compositors[@]})); then
  compositor_step="$(compositor_label "$primary") ($compositor_how)"
  if ((${#compositors[@]} > 1)); then
    labels=()
    for name in "${compositors[@]:1}"; do labels+=("$(compositor_label "$name")"); done
    compositor_step+="; also installed: $(joined "${labels[@]}")"
  fi
  configs=()
  for name in "${compositors[@]}"; do configs+=("$(compositor_config "$name")"); done
  autostart_step="the line that starts axiom, at the end of $(joined "${configs[@]}") (asked for each)"
else
  compositor_step="none (--compositor none)"
  autostart_step="none: start \`'$AXIOM_BIN' run\` from your compositor yourself"
fi
if ((packaged)); then
  binary_step="none: the package's, at $AXIOM_BIN"
else
  binary_step="the axiom binary into $AXIOM_BIN: the release's official build, downloaded and checked, else built from the install (installing go)"
fi
if [[ "$distro" == arch ]]; then
  packages_step="packages from the official repositories, through sudo pacman"
else
  packages_step="packages from Fedora and from COPRs (asked first), through sudo dnf"
fi

echo
info "${bold}This installs axiom${reset} on $(os_name)$( ((dry_run)) && echo ", as a dry run: nothing is changed"):"
cat <<EOF
   compositor: $compositor_step
   1. $packages_step (you'll see the exact command first)
   2. $clone_step
   3. $binary_step
   4. $autostart_step
EOF
interactive && echo "   It asks before each step that changes anything."
echo

# ─── Packages ────────────────────────────────────────────────────────────────

required_keys=()
for key in "${REQUIRED[@]}" "${compositors[@]}"; do
  required_keys+=("$key")
done
mapfile -t need_required < <(missing "${required_keys[@]}")
mapfile -t no_package < <(unavailable "${need_required[@]}")
((${#no_package[@]})) && die "$(joined "${no_package[@]}") isn't packaged for $distro_name."
if ((${#need_required[@]})); then
  info "Required, not installed yet: $(joined "${need_required[@]}")"
else
  ok "The required packages are installed"
fi

# The features for these compositors: their keys here, "n/a" when one has
# no package here, and those whose packages are all there aren't asked about
offered=()
not_here=()
seen_features="|"
for entry in "${FEATURES[@]}"; do
  IFS='|' read -r feature keys only <<<"$entry"
  if [[ -n "$only" ]]; then
    matches=0
    for name in "${compositors[@]}"; do [[ " $only " == *" $name "* ]] && matches=1; done
    ((matches)) || continue
  fi
  [[ "$seen_features" == *"|$feature|"* ]] && continue
  seen_features+="$feature|"
  read -ra feature_keys <<<"$keys"
  if [[ -n "$(unavailable "${feature_keys[@]}")" ]]; then
    not_here+=("$feature")
    continue
  fi
  [[ -n "$(missing "${feature_keys[@]}")" ]] && offered+=("$feature|$keys")
done

wanted=()
skipped=()
if ((${#offered[@]})); then
  all=0
  if [[ "$mode" == yes ]]; then
    all=1
  elif interactive; then
    info "Optional features:"
    for entry in "${offered[@]}"; do
      read -ra feature_keys <<<"${entry#*|}"
      names=()
      for key in "${feature_keys[@]}"; do names+=("$(package_name "$(package_of "$key")")"); done
      printf '     %-40s %s\n' "${entry%%|*}" "${names[*]}"
    done
    echo
    ask "Install all of them? (recommended)" && all=1
  fi
  for entry in "${offered[@]}"; do
    feature=${entry%%|*}
    read -ra feature_keys <<<"${entry#*|}"
    if ((all)) || ask "$feature?"; then
      wanted+=("${feature_keys[@]}")
    else
      skipped+=("$feature")
    fi
  done
else
  ok "Every optional feature's packages are installed"
fi

# Every key to install (a key can be wanted twice), as packages, and the
# COPRs they need that aren't enabled yet
plan_packages() {
  mapfile -t to_install < <(missing "${need_required[@]}" "${wanted[@]}" | sort -u)
  packages=() coprs=()
  for key in "${to_install[@]}"; do
    cell=$(package_of "$key")
    case "$cell" in
    - | n/a) ;;
    *)
      packages+=("$(package_name "$cell")")
      copr=$(package_copr "$cell")
      [[ -n "$copr" ]] && ! copr_enabled "$copr" && [[ " ${coprs[*]} " != *" $copr "* ]] && coprs+=("$copr")
      ;;
    esac
  done
  mapfile -t packages < <(printf '%s\n' "${packages[@]}" | sed '/^$/d' | sort -u)
}
plan_packages

# root_notice "what": says what runs as root and why
root_notice() {
  local tool=$1
  cat <<EOF
   $tool writes to /usr and to its own database, which only root can do. Only
   the package manager runs as root: the clone and your compositor's config
   stay in your home and are changed as you. It lists every package,
   dependencies included, before it installs anything. sudo may ask for your
   password.

EOF
}

# sudo_run command...: runs it through sudo, the terminal as its stdin
sudo_run() {
  if ((dry_run)); then
    run sudo "$@"
  elif ((have_tty)); then
    # shellcheck disable=SC2024 # the terminal is the command's stdin, on purpose
    sudo "$@" </dev/tty
  else
    sudo "$@"
  fi
}

# The COPRs (Fedora) the picked packages need, each shown and asked
# separately: a COPR is a third-party build service, not Fedora's own
declined_coprs=()
if ((${#coprs[@]})); then
  echo
  info "${bold}Some packages come from COPRs${reset}: Fedora's build service for third-party repositories, whose packages Fedora doesn't review."
  command -v sudo >/dev/null || die "sudo is needed to enable a COPR."
  copr_plugin=1
  dnf copr --help >/dev/null 2>&1 || copr_plugin=0
  for copr in "${coprs[@]}"; do
    from=()
    for key in "${to_install[@]}"; do
      [[ "$(package_copr "$(package_of "$key")")" == "$copr" ]] && from+=("$(package_name "$(package_of "$key")")")
    done
    echo
    # dnf's copr command is a plugin, missing from minimal installs
    ((copr_plugin)) || printf "    sudo dnf install -y 'dnf-command(copr)'\n"
    printf '    sudo dnf copr enable -y %s\n\n' "$copr"
    echo "   for: $(joined "${from[@]}")"
    if interactive && ! ask "Enable $copr?"; then
      declined_coprs+=("$copr")
      continue
    fi
    if ((!copr_plugin)); then
      sudo_run dnf install -y 'dnf-command(copr)' || die "Installing dnf's copr command failed."
      copr_plugin=1
    fi
    sudo_run dnf copr enable -y "$copr" || die "Enabling the COPR $copr failed."
  done
fi

# is_skipped "feature": whether it's in skipped
is_skipped() {
  local feature
  for feature in "${skipped[@]}"; do [[ "$feature" == "$1" ]] && return 0; done
  return 1
}

# Packages from a declined COPR: a required one stops here, an optional
# one's whole feature is skipped, and the packages are planned again from
# the features left
for copr in "${declined_coprs[@]}"; do
  for key in "${need_required[@]}"; do
    [[ "$(package_copr "$(package_of "$key")")" == "$copr" ]] && die "axiom can't run without $key, which comes from $copr. Run this again and enable it."
  done
  for entry in "${offered[@]}"; do
    is_skipped "${entry%%|*}" && continue
    read -ra feature_keys <<<"${entry#*|}"
    for key in "${feature_keys[@]}"; do
      if [[ "$(package_copr "$(package_of "$key")")" == "$copr" ]]; then
        skipped+=("${entry%%|*}")
        break
      fi
    done
  done
done
if ((${#declined_coprs[@]})); then
  wanted=()
  for entry in "${offered[@]}"; do
    is_skipped "${entry%%|*}" && continue
    read -ra feature_keys <<<"${entry#*|}"
    wanted+=("${feature_keys[@]}")
  done
  plan_packages
fi

# One sudo call for every package. Declining returns 1
install_packages() {
  local flags tool
  if [[ "$distro" == arch ]]; then
    tool=pacman
    flags=(-S --needed)
    interactive || flags+=(--noconfirm)
  else
    tool=dnf
    flags=(install)
    interactive || flags+=(-y)
  fi
  echo
  info "${bold}Installing packages needs root${reset}, so this runs through sudo:"
  printf '\n    sudo %s %s %s\n\n' "$tool" "${flags[*]}" "$*"
  root_notice "$tool"
  # --yes, --minimal and no terminal go ahead: the plan above is the notice
  if interactive; then
    ask "Continue?" || return 1
  fi
  command -v sudo >/dev/null || die "sudo is needed to install packages."
  sudo_run "$tool" "${flags[@]}" "$@" && return
  if [[ "$distro" == arch ]]; then
    die "pacman failed. If a download returned 404, the package database is out of date: run \`sudo pacman -Syu\`, then this again."
  fi
  die "dnf failed. See its message above, then run this again."
}

if ((${#packages[@]})) && ! install_packages "${packages[@]}"; then
  if ((${#need_required[@]})); then
    die "axiom can't run without $(joined "${need_required[@]}"). Install them, then run this again."
  fi
  warn "Skipped the optional packages."
  skipped=()
  for entry in "${offered[@]}"; do
    skipped+=("${entry%%|*}")
  done
  to_install=()
fi

if [[ " ${to_install[*]} " == *" nmcli "* ]] && ((!dry_run)) && ! systemctl is-active --quiet NetworkManager; then
  warn "NetworkManager isn't running, so the Wi-Fi menu stays empty. Enable it with \`sudo systemctl enable --now NetworkManager\` (after stopping any other network manager, such as iwd or systemd-networkd)."
fi

if ((!dry_run)); then
  qs_path=$(command -v qs || true)
  if [[ -n "$qs_path" && "$(readlink -f "$qs_path")" != /usr/bin/* ]]; then
    warn "$qs_path comes before the quickshell package's /usr/bin/qs on your PATH."
  fi
  qs_version=$(qs --version 2>/dev/null | first_version || true)
  if [[ -z "$qs_version" ]] || ! version_at_least "$qs_version" "$MIN_QS"; then
    warn "axiom needs Quickshell $MIN_QS or newer (found ${qs_version:-none})."
  fi
  for name in "${compositors[@]}"; do
    case "$name" in
    hyprland)
      if [[ "$running_compositor" == hyprland ]]; then
        version=$(hyprctl version 2>/dev/null | first_version || true)
      else
        version=$(Hyprland --version 2>/dev/null | first_version || true)
      fi
      if [[ -n "$version" ]] && ! version_at_least "$version" "$MIN_HYPRLAND"; then
        warn "Hyprland is $version; axiom needs $MIN_HYPRLAND or newer.$([[ "$running_compositor" == hyprland ]] && echo " Log out and back in after the upgrade.")"
      fi
      ;;
    sway)
      version_text=$(sway --version 2>/dev/null || true)
      version=$(first_version <<<"$version_text" || true)
      # SwayFX's own version numbers
      if [[ "$version_text" != *swayfx* && -n "$version" ]] && ! version_at_least "$version" "$TESTED_SWAY"; then
        info "sway is $version; axiom is tested with $TESTED_SWAY, so something may not work."
      fi
      ;;
    niri)
      version=$(niri --version 2>/dev/null | first_version || true)
      if [[ -n "$version" ]] && ! version_at_least "$version" "$TESTED_NIRI"; then
        info "niri is $version; axiom is tested with $TESTED_NIRI, so something may not work."
      fi
      ;;
    esac
  done
fi

# ─── The clone ───────────────────────────────────────────────────────────────

if ((packaged)); then
  ok "axiom is installed as a package, at $PACKAGED_DIR"
elif is_axiom_clone "$AXIOM_DIR"; then
  info "axiom is already installed at $AXIOM_DIR (left as it is: it updates itself)"
elif [[ -e "$AXIOM_DIR" ]]; then
  die "$AXIOM_DIR already exists and isn't an axiom clone. Move it away and run this again."
elif ((dry_run)); then
  run git clone --quiet "$AXIOM_REPO" "$AXIOM_DIR"
  run git -C "$AXIOM_DIR" checkout '<the newest v* tag>'
else
  info "Cloning axiom into $AXIOM_DIR"
  mkdir -p "$(dirname "$AXIOM_DIR")"
  git clone --quiet "$AXIOM_REPO" "$AXIOM_DIR"
  # Releases are v* tags; self-update also works from a detached tag
  latest=$(git -C "$AXIOM_DIR" tag -l 'v*' --sort=-v:refname | head -1)
  if [[ -n "$latest" ]]; then
    # A release from before the qml/ layout runs from ~/.config/quickshell,
    # which nothing looks in any more
    if ! git -C "$AXIOM_DIR" cat-file -e "$latest:qml/shell.qml" 2>/dev/null; then
      rm -rf "$AXIOM_DIR"
      die "There's no release with the new layout yet ($latest has none); run this again once one is tagged."
    fi
    git -C "$AXIOM_DIR" -c advice.detachedHead=false checkout --quiet "$latest"
    ok "Checked out $latest"
  else
    warn "No release tag yet, so this is the development branch."
  fi
fi

# ─── The binary ──────────────────────────────────────────────────────────────

if ((packaged)); then
  [[ -x "$AXIOM_BIN" ]] || warn "The package has no $AXIOM_BIN: reinstall it."
else
  echo
  info "The axiom binary, into $AXIOM_BIN"
  run mkdir -p "$(dirname "$AXIOM_BIN")"
  if ((dry_run)); then
    run official_binary "$AXIOM_DIR" "$AXIOM_BIN.new"
    run "$AXIOM_BIN.new" schema build --tree "$AXIOM_DIR"
    run mv -f "$AXIOM_BIN.new" "$AXIOM_BIN"
    info "(else built from the install's source with go, installed first when it's missing)"
  elif official_binary "$AXIOM_DIR" "$AXIOM_BIN.new"; then
    # The tree's schema copy, which the tools read (the daemon builds the
    # shell's own)
    "$AXIOM_BIN.new" schema build --tree "$AXIOM_DIR" >/dev/null || die "Building axiom's schema failed (see above)."
    mv -f "$AXIOM_BIN.new" "$AXIOM_BIN"
    ok "Installed $AXIOM_BIN"
  else
    info "Building it from the install's source instead"
    if ! command -v go >/dev/null; then
      install_packages "$(package_name "$(package_of go)")" || die "Building the axiom binary needs go. Install it, then run this again."
    fi
    # The generated files first (the embedded schema among them), then the
    # binary beside its old one, swapped in once it built
    "$AXIOM_DIR/scripts/generate.sh" --no-docs || die "Generating axiom's files failed (see above)."
    (cd "$AXIOM_DIR/backend" && CGO_ENABLED=0 go build -trimpath -o "$AXIOM_BIN.new" ./cmd/axiom && mv -f "$AXIOM_BIN.new" "$AXIOM_BIN") \
      || die "Building the axiom binary failed (see above)."
    ok "Built $AXIOM_BIN"
  fi
  [[ ":$PATH:" == *":$(dirname "$AXIOM_BIN"):"* ]] \
    || info "$(dirname "$AXIOM_BIN") isn't on your PATH: the compositor starts axiom by its full path, but for \`axiom\` commands in a terminal, add it."
fi

# ─── Desktop entries ─────────────────────────────────────────────────────────

# The tool pages that open as windows (Settings, Themes, …: data/applications),
# for any app launcher; a package installs its own. Taken from the install,
# else (a release from before them, while this clone is the dev tree) from
# the clone this runs from. Exec names the binary by its path, which may not
# be on PATH
if ((!packaged)); then
  apps_dir=${XDG_DATA_HOME:-$HOME/.local/share}/applications
  entries_dir=""
  for dir in "$AXIOM_DIR/data/applications" ${clone_dir:+"$clone_dir/data/applications"}; do
    if compgen -G "$dir/axiom-*.desktop" >/dev/null; then
      entries_dir=$dir
      break
    fi
  done
  if ((dry_run)) && [[ -z "$entries_dir" ]]; then
    entries_dir="$AXIOM_DIR/data/applications"
    run cp "$entries_dir/axiom-*.desktop" "$apps_dir/"
  elif [[ -z "$entries_dir" ]]; then
    info "No desktop entries for axiom's settings windows in this release (they come with a later one)"
  else
    info "Desktop entries for axiom's settings windows, into $apps_dir"
    run mkdir -p "$apps_dir"
    for entry in "$entries_dir"/axiom-*.desktop; do
      if ((dry_run)); then
        run cp "$entry" "$apps_dir/"
      else
        sed "s|^Exec=axiom |Exec=$AXIOM_BIN |" "$entry" >"$apps_dir/$(basename "$entry").new" \
          && mv -f "$apps_dir/$(basename "$entry").new" "$apps_dir/$(basename "$entry")"
      fi
    done
    ((dry_run)) || ok "Installed $(compgen -G "$entries_dir/axiom-*.desktop" | wc -l) desktop entries"
  fi
fi

# ─── The screen-share portal ─────────────────────────────────────────────────

# axiom's own ScreenCast portal, which niri's screen sharing uses once the
# Screen sharing settings point xdg-desktop-portal at it: its .portal file,
# and a D-Bus activation that waits for the daemon serving it; a package
# installs its own
if ((!packaged)); then
  portal_src=""
  for dir in "$AXIOM_DIR/data/portal" ${clone_dir:+"$clone_dir/data/portal"}; do
    if [[ -f "$dir/axiom.portal" ]]; then
      portal_src=$dir
      break
    fi
  done
  data_home=${XDG_DATA_HOME:-$HOME/.local/share}
  if ((dry_run)) && [[ -z "$portal_src" ]]; then
    run cp "$AXIOM_DIR/data/portal/axiom.portal" "$data_home/xdg-desktop-portal/portals/"
  elif [[ -n "$portal_src" ]]; then
    run mkdir -p "$data_home/xdg-desktop-portal/portals" "$data_home/dbus-1/services"
    run cp "$portal_src/axiom.portal" "$data_home/xdg-desktop-portal/portals/"
    service=org.freedesktop.impl.portal.desktop.axiom.service
    if ((dry_run)); then
      run cp "$portal_src/$service" "$data_home/dbus-1/services/"
    else
      sed "s|^Exec=/usr/bin/axiom |Exec=$AXIOM_BIN |" "$portal_src/$service" >"$data_home/dbus-1/services/$service.new" \
        && mv -f "$data_home/dbus-1/services/$service.new" "$data_home/dbus-1/services/$service"
      ok "Installed axiom's screen-share portal"
    fi
  fi
fi

# ─── The dev tree ────────────────────────────────────────────────────────────

# Run from a clone: the install above is what axiom runs, and the clone can
# be its dev tree (`axiom dev on` then builds and runs it). Offered only by
# a binary that has `axiom dev set`; otherwise said
dev_set_hint=""
if ((from_clone)); then
  echo
  info "axiom runs the release installed at $AXIOM_DIR, not this clone ($clone_dir). To work on axiom, make this clone its dev tree: \`axiom dev on\` then builds and runs it."
  if ((dry_run)); then
    ask "Make it axiom's dev tree?" && run "$AXIOM_BIN" dev set "$clone_dir"
  elif "$AXIOM_BIN" dev set --help >/dev/null 2>&1; then
    if ask "Make it axiom's dev tree?"; then
      if "$AXIOM_BIN" dev set "$clone_dir"; then
        ok "This clone is axiom's dev tree: \`axiom dev on\` runs it, \`axiom dev off\` the install"
      else
        dev_set_hint="'$AXIOM_BIN' dev set '$clone_dir'"
      fi
    fi
  else
    dev_set_hint="'$AXIOM_BIN' dev set '$clone_dir'"
  fi
fi

# ─── Autostart ───────────────────────────────────────────────────────────────

# Per compositor: "present" | "added" | "manual"
declare -A autostart=()
for name in "${compositors[@]}"; do
  config=$(compositor_config "$name")
  line=$(autostart_line "$name")
  label=$(compositor_label "$name")
  target=$(readlink -f "$config" 2>/dev/null || echo "$config")
  if [[ -f "$target" ]] && grep -qE "$STARTS_AXIOM" "$target"; then
    ok "$label's config already starts axiom"
    autostart[$name]=present
    continue
  fi
  seed=$(compositor_default_config "$name")
  if [[ ! -f "$target" && -z "$seed" ]]; then
    # A config of this line alone would have no binds: niri and Hyprland
    # write their default config on their first start
    info "$config doesn't exist yet, and there's no default config of $label's to start it from. Start $label once (it writes one), then run this again, or add this line at the end of its config yourself:"
    printf '\n    %s\n\n' "$line"
    autostart[$name]=manual
    continue
  fi
  echo
  info "To start with $label, axiom needs this line at the end of $config:"
  printf '\n    %s\n\n' "$line"
  # The main compositor's yes by default; another installed one's no (it
  # may be there for something else, such as the login screen)
  default=n
  [[ "$name" == "$primary" ]] && default=y
  if ask "Add it?" "$default"; then
    run mkdir -p "$(dirname "$target")"
    if [[ -f "$target" ]]; then
      backup="$target.bak-$(date +%Y%m%d-%H%M%S)"
      run cp -p "$target" "$backup"
      info "Backed up to $backup"
    else
      run cp "$seed" "$target"
      info "Created $config from $label's default config"
    fi
    append_line "$target" "$line"
    ok "Added to $config"
    autostart[$name]=added
  else
    autostart[$name]=manual
  fi
done

# ─── Start ───────────────────────────────────────────────────────────────────

started=0
if [[ -n "$running_compositor" && " ${compositors[*]} " == *" $running_compositor "* ]]; then
  if axiom_running; then
    ok "axiom is already running"
    started=1
  elif ask "Start axiom now?"; then
    if ((dry_run)); then
      run setsid "$AXIOM_BIN" run
    else
      setsid "$AXIOM_BIN" run >/dev/null 2>&1 </dev/null &
      disown
      ok "Started axiom"
    fi
    started=1
  fi
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo
if ((dry_run)); then
  ok "${bold}Dry run done${reset}: nothing was changed"
elif ((packaged)); then
  ok "${bold}axiom is set up${reset} (the package at $PACKAGED_DIR)"
else
  ok "${bold}axiom is installed${reset} at $AXIOM_DIR"
fi
[[ -n "$dev_set_hint" ]] && info "To make this clone axiom's dev tree, run \`$dev_set_hint\`."
((${#packages[@]})) && info "Packages: $(joined "${packages[@]}")"
if ((${#skipped[@]})); then
  mapfile -t skipped < <(printf '%s\n' "${skipped[@]}" | awk '!seen[$0]++')
  info "Skipped: $(joined "${skipped[@]}"). Run this again to add them."
fi
((${#not_here[@]})) && info "Not available on $distro_name: $(joined "${not_here[@]}")."
for name in "${compositors[@]}"; do
  label=$(compositor_label "$name")
  case "${autostart[$name]}" in
  manual) [[ "$name" == "$primary" ]] && info "Add the line above to $(compositor_config "$name") to start axiom with $label." ;;
  *)
    if [[ "$name" != "$running_compositor" ]] || ((!started)); then
      info "axiom starts the next time you log in to $label."
    fi
    ;;
  esac
done
if [[ " ${compositors[*]} " == *" sway "* ]] && ! sway --version 2>/dev/null | grep -qi swayfx; then
  info "For blur and rounded corners under sway, SwayFX replaces sway in place (Arch: the AUR's swayfx; Fedora: COPR swayfx/swayfx). This script doesn't install it."
fi
((${#compositors[@]})) || info "Start axiom from your compositor with \`'$AXIOM_BIN' run\`."
info "Keybinds and the compositor's setup are in axiom's Settings → Desktop."

# ─── Into the compositor ─────────────────────────────────────────────────────

# Not in it already: say how to get there, and from a text console (no
# graphical session at all) offer to start it right here
if ((${#compositors[@]})) && [[ -z "$running_compositor" ]]; then
  label=$(compositor_label "$primary")
  launcher=$(compositor_launcher "$primary")
  echo
  info "To get into $label: run \`$launcher\` from a text console (a TTY), or log out and pick $label in your login screen's session menu."
  if interactive && ((!dry_run)) && [[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" ]] \
    && [[ "$(tty </dev/tty 2>/dev/null)" == /dev/tty[0-9]* ]] && ask "Start $label now?"; then
    # shellcheck disable=SC2086 # "niri --session" is a command and its flag
    exec $launcher </dev/tty
  fi
fi
}

main "$@"
