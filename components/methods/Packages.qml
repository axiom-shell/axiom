pragma Singleton
import QtQuick

// Which distribution this is (from its os-release) and what installs a
// command there: each command's package per distribution, the shell lines
// that install a set of them (install hints), and how it checks for and
// installs updates (the Updates widget). Adding a distribution is one
// column in `packages`, one entry in `distros`, and its test rows; until
// then, hints and updates stay hidden on it. No file access, processes or
// services.
QtObject {
  id: root

  // How each distribution installs: `install` is followed by the package
  // names, `repo` by a third-party repository to enable first. `updates`
  // checks for pending updates without root: `check` (the command),
  // `found` / `none` (its exit codes with updates, and with none), `format`
  // (its output, "pacman" or "dnf", parsed by axiom's `updates` topic),
  // `upgrade` (run in a terminal), and `aur` (an AUR helper's updates
  // count too)
  readonly property var distros: ({
      "arch": {
        "install": "sudo pacman -S --needed",
        "updates": {
          "check": ["checkupdates", "--nocolor"],
          "found": [0],
          "none": [2],
          "format": "pacman",
          "upgrade": "sudo pacman -Syu",
          "aur": true
        }
      },
      "fedora": {
        "install": "sudo dnf install",
        "repo": "sudo dnf copr enable -y",
        "updates": {
          "check": ["dnf", "check-update", "--quiet"],
          "found": [100],
          "none": [0],
          "format": "dnf",
          "upgrade": "sudo dnf upgrade",
          "aur": false
        }
      }
    })

  // The Material Symbols Rounded variable font, for distributions without a
  // package of it
  readonly property string iconFontUrl: "https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL,GRAD,opsz,wght%5D.ttf"

  // Hyprland and its tools left Fedora's own repositories; this COPR builds
  // them (and quickshell) for every current release
  readonly property string _hyprCopr: "nett00n/hyprland"
  // Quickshell's own docs point at this one (Fedora's quickshell is too old)
  readonly property string _quickshellCopr: "errornointernet/quickshell"

  // { key: { distro: package } }, a key being a command (a compositor by
  // its lowercase name), a Python module as "py:<module>", a package
  // without a command ("xdg-desktop-portal-gtk"), or "iconFont". install.sh
  // keeps a table of the same keys (scripts/check_packages.py compares them).
  // A package is a name, { name, repo } (from a repository enabled first),
  // { file, to } (a download), or null: nothing to install there (the
  // feature doesn't apply). Every key names every distribution.
  readonly property var packages: ({
      "iconFont": {
        "arch": "ttf-material-symbols-variable",
        "fedora": {
          "file": root.iconFontUrl,
          "to": "~/.local/share/fonts/MaterialSymbolsRounded.ttf"
        }
      },
      "git": {
        "arch": "git",
        "fedora": "git"
      },
      "go": {
        "arch": "go",
        "fedora": "golang"
      },
      "quickshell": {
        "arch": "quickshell",
        "fedora": {
          "name": "quickshell",
          "repo": root._quickshellCopr
        }
      },
      "hyprland": {
        "arch": "hyprland",
        "fedora": {
          "name": "hyprland",
          "repo": root._hyprCopr
        }
      },
      "sway": {
        "arch": "sway",
        "fedora": "sway"
      },
      "niri": {
        "arch": "niri",
        "fedora": "niri"
      },
      "awww": {
        "arch": "awww",
        "fedora": null
      },
      "nmcli": {
        "arch": "networkmanager",
        "fedora": "NetworkManager"
      },
      "xdg-desktop-portal-gtk": {
        "arch": "xdg-desktop-portal-gtk",
        "fedora": "xdg-desktop-portal-gtk"
      },
      "py:gi": {
        "arch": "python-gobject",
        "fedora": "python3-gobject"
      },
      "qalc": {
        "arch": "libqalculate",
        "fedora": "qalculate"
      },
      "brightnessctl": {
        "arch": "brightnessctl",
        "fedora": "brightnessctl"
      },
      "ddcutil": {
        "arch": "ddcutil",
        "fedora": "ddcutil"
      },
      "wl-copy": {
        "arch": "wl-clipboard",
        "fedora": "wl-clipboard"
      },
      "jq": {
        "arch": "jq",
        "fedora": "jq"
      },
      "curl": {
        "arch": "curl",
        "fedora": "curl"
      },
      "checkupdates": {
        "arch": "pacman-contrib",
        "fedora": null
      },
      "secret-tool": {
        "arch": "libsecret",
        "fedora": "libsecret"
      },
      "gio": {
        "arch": "glib2",
        "fedora": "glib2"
      },
      "python3": {
        "arch": "python",
        "fedora": "python3"
      },
      "py:numpy": {
        "arch": "python-numpy",
        "fedora": "python3-numpy"
      },
      "py:PIL": {
        "arch": "python-pillow",
        "fedora": "python3-pillow"
      },
      "py:icalendar": {
        "arch": "python-icalendar",
        "fedora": "python3-icalendar"
      },
      "py:dateutil": {
        "arch": "python-dateutil",
        "fedora": "python3-dateutil"
      },
      "notify-send": {
        "arch": "libnotify",
        "fedora": "libnotify"
      },
      "hyprsunset": {
        "arch": "hyprsunset",
        "fedora": {
          "name": "hyprsunset",
          "repo": root._hyprCopr
        }
      },
      "wlsunset": {
        "arch": "wlsunset",
        "fedora": "wlsunset"
      },
      "xwayland-satellite": {
        "arch": "xwayland-satellite",
        "fedora": "xwayland-satellite"
      },
      "Xwayland": {
        "arch": "xorg-xwayland",
        "fedora": "xorg-x11-server-Xwayland"
      },
      "cliphist": {
        "arch": "cliphist",
        "fedora": "cliphist"
      },
      "wf-recorder": {
        "arch": "wf-recorder",
        "fedora": "wf-recorder"
      },
      "grim": {
        "arch": "grim",
        "fedora": "grim"
      },
      "satty": {
        "arch": "satty",
        "fedora": {
          "name": "satty",
          "repo": root._hyprCopr
        }
      },
      "pactl": {
        "arch": "libpulse",
        "fedora": "pulseaudio-utils"
      },
      "powerprofilesctl": {
        "arch": "power-profiles-daemon",
        "fedora": "power-profiles-daemon"
      },
      "greetd": {
        "arch": "greetd",
        "fedora": "greetd"
      },
      "agreety": {
        "arch": "greetd-agreety",
        "fedora": "greetd"
      }
    })

  // The distribution family an os-release file names: its ID, else the
  // first of its ID_LIKE we know ("arch" for CachyOS or Manjaro, "fedora"
  // for Nobara), else ""
  function distroFamily(osRelease) {
    const fields = String(osRelease ?? "").split("\n").reduce((all, line) => {
      const match = line.trim().match(/^([A-Z_]+)=(.*)$/);
      if (match)
        all[match[1]] = match[2].trim().replace(/^(["'])(.*)\1$/, "$2");
      return all;
    }, {});
    const ids = [fields.ID ?? ""].concat((fields.ID_LIKE ?? "").split(/\s+/)).map(id => id.toLowerCase());
    return ids.find(id => id !== "" && root.distros[id] !== undefined) ?? "";
  }

  // What installs `key` on `distro`, as { name, repo } or { file, to };
  // null when nothing does or the distribution is unknown
  function packageFor(distro, key) {
    if (root.distros[distro] === undefined)
      return null;
    const entry = root.packages[key]?.[distro];
    if (entry === undefined)
      return {
        "name": key
      };
    if (entry === null)
      return null;
    return typeof entry === "string" ? {
      "name": entry
    } : entry;
  }

  // Whether `key` means anything on `distro` (an unknown one: yes)
  function applies(distro, key) {
    return root.distros[distro] === undefined || root.packageFor(distro, key) !== null;
  }

  // The shell lines that install `keys` on `distro`, in order: repositories
  // to enable, one install of every package, then downloads. [] for an
  // unknown distribution or nothing to install
  function installLines(distro, keys) {
    const how = root.distros[distro];
    if (how === undefined)
      return [];
    const unique = list => list.filter((item, i) => list.indexOf(item) === i);
    const found = unique(keys ?? []).map(key => root.packageFor(distro, key)).filter(entry => entry !== null);
    const lines = how.repo === undefined ? [] : unique(found.filter(entry => entry.repo).map(entry => entry.repo)).map(repo => `${how.repo} ${repo}`);
    const names = unique(found.filter(entry => entry.name).map(entry => entry.name));
    if (names.length > 0)
      lines.push(`${how.install} ${names.join(" ")}`);
    for (const entry of found.filter(entry => entry.file)) {
      const dir = entry.to.slice(0, entry.to.lastIndexOf("/"));
      lines.push(`mkdir -p ${dir} && curl -fLo ${entry.to} '${entry.file}' && fc-cache -f`);
    }
    return lines;
  }

  // One line that installs `keys` (a key or a list; "" when nothing does)
  function installCommand(distro, keys) {
    return root.installLines(distro, [].concat(keys)).join(" && ");
  }

  // How `distro` checks for updates (see `distros`), or null
  function updates(distro) {
    return root.distros[distro]?.updates ?? null;
  }
}
