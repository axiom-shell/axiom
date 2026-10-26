#!/usr/bin/env bash
#
# Description: Installs axiom on Arch Linux, Fedora, or a distribution based
#              on either (CachyOS, EndeavourOS, Manjaro, Nobara, …): a
#              compositor (Hyprland, sway or niri: the one you run or have,
#              else your pick), axiom's packages, a clone at the latest
#              release, and (if you agree) the line in the compositor's
#              config that starts it; from a text console it then offers to
#              start the compositor. Everything after that, keybinds
#              included, is axiom's own Settings → Desktop → Compositor.
# Usage:       curl -fsSL https://raw.githubusercontent.com/axiom-shell/axiom/main/install.sh | bash
#              ./install.sh [options]   (from a clone anywhere; it's linked
#                into ~/.config/quickshell/axiom, or moved there)
#                --yes          answer yes to every question
#                --minimal      required packages only, and no other changes
#                --compositor hyprland|sway|niri|none
#                               the compositor to install and start axiom
#                               from, without asking (none: neither)
#                --dry-run      print every command it would run; change
#                               nothing
#              AXIOM_REPO and AXIOM_DIR override the clone's source and
#              target. Safe to run again: nothing is installed or added twice.
#              sudo runs only for the package manager (and on Fedora to
#              enable a COPR), each time after showing the command.

set -euo pipefail

# Wrapped in main so bash reads all of it before running any of it: under
# curl | bash, anything reading stdin would otherwise eat the rest
main() {
AXIOM_REPO=${AXIOM_REPO:-https://github.com/axiom-shell/axiom.git}
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
# Where `axiom run` looks for it
QS_DIR=$CONFIG_HOME/quickshell/axiom
AXIOM_DIR=${AXIOM_DIR:-$QS_DIR}
# An AUR (or other) package's copy, with the marker its PKGBUILD writes
PACKAGED_DIR=/usr/share/axiom

# What installs each key (Packages.packages' keys, checked against it by
# scripts/check_packages.py): key|Arch|Fedora, each a package name,
# "owner/project:name" (from that COPR), "download" (the icon font, into
# your home), "-" (nothing needed there) or "n/a" (not packaged there)
PACKAGES=(
  "git|git|git"
  "go|go|golang"
  "quickshell|quickshell|errornointernet/quickshell:quickshell"
  "jq|jq|jq"
  "curl|curl|curl"
  "python3|python|python3"
  "iconFont|ttf-material-symbols-variable|download"
  "hyprland|hyprland|nett00n/hyprland:hyprland"
  "sway|sway|sway"
  "niri|niri|niri"
  "awww|awww|n/a"
  "py:numpy|python-numpy|python3-numpy"
  "py:PIL|python-pillow|python3-pillow"
  "py:icalendar|python-icalendar|python3-icalendar"
  "secret-tool|libsecret|libsecret"
  "nmcli|networkmanager|NetworkManager"
  "checkupdates|pacman-contrib|-"
  "wl-copy|wl-clipboard|wl-clipboard"
  "wf-recorder|wf-recorder|wf-recorder"
  "grim|grim|grim"
  "satty|satty|nett00n/hyprland:satty"
  "qalc|libqalculate|qalculate"
  "wtype|wtype|wtype"
  "cliphist|cliphist|cliphist"
  "brightnessctl|brightnessctl|brightnessctl"
  "ddcutil|ddcutil|ddcutil"
  "hyprsunset|hyprsunset|nett00n/hyprland:hyprsunset"
  "wlsunset|wlsunset|wlsunset"
  "xwayland-satellite|xwayland-satellite|xwayland-satellite"
  "Xwayland|xorg-xwayland|xorg-x11-server-Xwayland"
  "powerprofilesctl|power-profiles-daemon|power-profiles-daemon"
  "xdg-desktop-portal-gtk|xdg-desktop-portal-gtk|xdg-desktop-portal-gtk"
  "py:gi|python-gobject|python3-gobject"
  "greetd|greetd|greetd"
  "agreety|greetd-agreety|greetd"
)
ICON_FONT_URL="https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL,GRAD,opsz,wght%5D.ttf"
ICON_FONT_FILE=$HOME/.local/share/fonts/MaterialSymbolsRounded.ttf
# go builds the axiom binary from a clone (a package brings its own)
REQUIRED=(git go quickshell jq curl python3 iconFont)
# "feature|keys|compositors" (none listed: any), offered one at a time;
# the AUR package's optdepends say the same
FEATURES=(
  "Wallpapers|awww|"
  "Themes generated from your wallpaper|py:numpy py:PIL|"
  "Calendar accounts and feeds|py:icalendar secret-tool|"
  "Wi-Fi menu and network widget|nmcli|"
  "Package update checks|checkupdates|"
  "Copying screenshots to the clipboard|wl-copy|"
  "Screen recording|wf-recorder|"
  "Screenshots under niri|grim|niri"
  "Annotating screenshots|satty|"
  "Launcher calculator|qalc wl-copy|"
  "Typing emoji from the launcher (copying needs only wl-clipboard)|wtype wl-copy|"
  "Clipboard history with images, shared with other apps|cliphist wl-copy|"
  "Brightness keys and OSD bar (laptop panels, external monitors over DDC/CI)|brightnessctl ddcutil|"
  "Night light|hyprsunset|hyprland"
  "Night light|wlsunset|sway niri"
  "X11 apps under niri (Steam, games, older apps)|xwayland-satellite|niri"
  "X11 apps under sway (Steam, games, older apps)|Xwayland|sway"
  "Power profiles|powerprofilesctl|"
  "Browse buttons for folders and importing configs (the desktop's file picker)|xdg-desktop-portal-gtk py:gi|"
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
while (($#)); do
  case "$1" in
  --yes | -y) mode=yes ;;
  --minimal) mode=minimal ;;
  --dry-run) dry_run=1 ;;
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
    sed -n '3,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "Unknown option: $1 (try --help)" >&2
    exit 2
    ;;
  esac
  shift
done

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
  download) [[ -f "$ICON_FONT_FILE" ]] || fc-list 2>/dev/null | grep -q 'Material Symbols Rounded' ;;
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

is_axiom_clone() { [[ -f "$1/shell.qml" && -f "$1/scripts/self_update.sh" ]] && git -C "$1" rev-parse --git-dir >/dev/null 2>&1; }
same_dir() { [[ "$(readlink -f "$1" 2>/dev/null)" == "$(readlink -f "$2" 2>/dev/null)" ]]; }

# Run from a clone (not curl | bash): that clone is the install, wherever it is
from_clone=0
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  if is_axiom_clone "$script_dir"; then
    AXIOM_DIR=$script_dir
    from_clone=1
  fi
fi

# Installed as a package (the AUR's axiom-shell): `axiom run` finds it
# through /etc/xdg, so no clone, unless this runs from one
packaged=0
[[ -f "$PACKAGED_DIR/.packaged" ]] && ((!from_clone)) && ! is_axiom_clone "$AXIOM_DIR" && packaged=1

# The axiom binary (the shell's parent: `axiom run`): the package's, else
# built from the clone into your home
if ((packaged)); then
  AXIOM_BIN=/usr/bin/axiom
else
  AXIOM_BIN=${XDG_BIN_HOME:-$HOME/.local/bin}/axiom
fi

# ─── The plan ────────────────────────────────────────────────────────────────

if ((packaged)); then
  clone_step="none: axiom is installed as a package, at $PACKAGED_DIR"
elif ((from_clone)); then
  clone_step="this clone, at $AXIOM_DIR"
else
  clone_step="a clone of the latest release at $AXIOM_DIR"
fi
((packaged)) || same_dir "$AXIOM_DIR" "$QS_DIR" || clone_step+=$'\n      (then linked or moved to '"$QS_DIR"', where `axiom run` looks)'
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
  binary_step="the axiom binary, built from the clone (with go) into $AXIOM_BIN"
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
  # A package brings its binary: nothing to build
  [[ "$key" == go ]] && ((packaged)) && continue
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

# Every key to install (a key can be wanted twice: wl-copy), as packages
mapfile -t to_install < <(missing "${need_required[@]}" "${wanted[@]}" | sort -u)
packages=() coprs=() download=0
for key in "${to_install[@]}"; do
  cell=$(package_of "$key")
  case "$cell" in
  - | n/a) ;;
  download) download=1 ;;
  *)
    packages+=("$(package_name "$cell")")
    copr=$(package_copr "$cell")
    [[ -n "$copr" ]] && ! copr_enabled "$copr" && [[ " ${coprs[*]} " != *" $copr "* ]] && coprs+=("$copr")
    ;;
  esac
done
mapfile -t packages < <(printf '%s\n' "${packages[@]}" | sed '/^$/d' | sort -u)

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

# Packages from a declined COPR: a required one stops here, an optional
# one's feature is skipped
for copr in "${declined_coprs[@]}"; do
  for key in "${need_required[@]}"; do
    [[ "$(package_copr "$(package_of "$key")")" == "$copr" ]] && die "axiom can't run without $key, which comes from $copr. Run this again and enable it."
  done
  for entry in "${offered[@]}"; do
    read -ra feature_keys <<<"${entry#*|}"
    for key in "${feature_keys[@]}"; do
      if [[ "$(package_copr "$(package_of "$key")")" == "$copr" ]]; then
        skipped+=("${entry%%|*}")
        break
      fi
    done
  done
  mapfile -t packages < <(for package in "${packages[@]}"; do
    for key in "${to_install[@]}"; do
      cell=$(package_of "$key")
      [[ "$(package_name "$cell")" == "$package" && "$(package_copr "$cell")" == "$copr" ]] && continue 2
    done
    echo "$package"
  done)
done

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

# The icon font, where it isn't packaged: a download into your home, as you
if ((download)) && [[ " ${to_install[*]} " == *" iconFont "* ]]; then
  echo
  info "The icon font (Material Symbols Rounded) isn't packaged for $distro_name: downloading it from Google's repository into $ICON_FONT_FILE."
  run mkdir -p "$(dirname "$ICON_FONT_FILE")"
  run curl -fL --progress-bar -o "$ICON_FONT_FILE" "$ICON_FONT_URL" || die "Downloading the icon font failed."
  run fc-cache -f >/dev/null
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
elif ((from_clone)); then
  info "Using this clone: $AXIOM_DIR"
elif is_axiom_clone "$AXIOM_DIR"; then
  info "axiom is already cloned at $AXIOM_DIR"
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
    git -C "$AXIOM_DIR" -c advice.detachedHead=false checkout --quiet "$latest"
    ok "Checked out $latest"
  else
    warn "No release tag yet, so this is the development branch."
  fi
fi

# `axiom run` only looks in $QS_DIR (then /etc/xdg), so a clone elsewhere
# is linked (or moved) there
placed=1
if ((packaged)); then
  :
elif [[ ! -d "$AXIOM_DIR" ]]; then
  # A dry run's clone that wasn't made
  :
elif same_dir "$QS_DIR" "$AXIOM_DIR"; then
  AXIOM_DIR=$(cd "$AXIOM_DIR" && pwd)
  [[ -L "$QS_DIR" ]] && ok "$QS_DIR links to this clone"
elif [[ -e "$QS_DIR" ]]; then
  placed=0
  if is_axiom_clone "$QS_DIR"; then
    warn "$QS_DIR is another axiom clone, and it's the one \`axiom run\` runs. Run its install.sh instead, or move it away and run this again to use $AXIOM_DIR."
  else
    warn "$QS_DIR exists and isn't axiom, so \`axiom run\` can't find $AXIOM_DIR. Move it away and run this again."
  fi
else
  AXIOM_DIR=$(cd "$AXIOM_DIR" && pwd)
  echo
  info "\`axiom run\` looks for axiom at $QS_DIR, but this clone is at $AXIOM_DIR."
  # A dangling link there (a clone that was moved or deleted) is replaced
  [[ -L "$QS_DIR" ]] && info "$QS_DIR is a broken link; it gets replaced."
  if ask "Link it there? (recommended: the clone stays where it is)"; then
    run mkdir -p "$(dirname "$QS_DIR")"
    run ln -sfn "$AXIOM_DIR" "$QS_DIR"
    ok "Linked $QS_DIR → $AXIOM_DIR"
  elif ask "Move the clone there instead?" n; then
    run mkdir -p "$(dirname "$QS_DIR")"
    run rm -f "$QS_DIR"
    run mv "$AXIOM_DIR" "$QS_DIR"
    AXIOM_DIR=$QS_DIR
    ok "Moved the clone to $QS_DIR"
  else
    placed=0
  fi
fi

# ─── The binary ──────────────────────────────────────────────────────────────

if ((packaged)); then
  [[ -x "$AXIOM_BIN" ]] || warn "The package has no $AXIOM_BIN: reinstall it."
else
  echo
  info "Building the axiom binary into $AXIOM_BIN"
  # The generated files first (the embedded schema among them), then the
  # binary beside its old one, swapped in once it built
  run "$AXIOM_DIR/scripts/generate.sh" || die "Generating axiom's files failed (see above)."
  run mkdir -p "$(dirname "$AXIOM_BIN")"
  run bash -c 'cd "$1/backend" && CGO_ENABLED=0 go build -trimpath -o "$2.new" ./cmd/axiom && mv -f "$2.new" "$2"' _ "$AXIOM_DIR" "$AXIOM_BIN" \
    || die "Building the axiom binary failed (see above)."
  ok "Built $AXIOM_BIN"
  [[ ":$PATH:" == *":$(dirname "$AXIOM_BIN"):"* ]] \
    || info "$(dirname "$AXIOM_BIN") isn't on your PATH: the compositor starts axiom by its full path, but for \`axiom\` commands in a terminal, add it."
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
  elif ((placed)) && ask "Start axiom now?"; then
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
if ((!placed)); then
  warn "\`axiom run\` won't find it until it's at $QS_DIR. Link it with: ln -s \"$AXIOM_DIR\" \"$QS_DIR\""
fi
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
