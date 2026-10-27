pragma Singleton
import QtQuick
import Quickshell
import qs.config
import qs.components.methods
import qs.services.compositor
import qs.services.system

/*
 * Startup checks for what the whole shell needs to look right: the icon font
 * (every icon is a Material Symbols name, StyledIcon, which shows as a word
 * without it) and the text font (`Appearance.font.family`, a free-text
 * setting: a misspelt name silently falls back to fontconfig's default).
 * Warns in the log and notifies once per qs launch (the text font once per
 * name, checked again whenever it changes). Created from shell.qml's
 * `_services`.
 *
 * Also which commands (and Python modules, as "py:<module>") are installed
 * (`found`, filled by `check(commands)` through axiom's deps.check),
 * for the onboarder: the optional `tools` below, the apps it offers; and
 * what installs them on this distribution (`distro`, `installLines`).
 */
Singleton {
  id: root

  readonly property bool iconFontInstalled: Qt.fontFamilies().includes(Appearance.iconFamily)
  readonly property bool textFontInstalled: hasFontFamily(Appearance.fontFamily)

  // fontconfig's generic names, which match no single family
  readonly property var _genericFamilies: ["monospace", "mono", "sans-serif", "sans", "serif", "system-ui", "cursive", "fantasy", "emoji"]

  // Whether fontconfig knows the family (any of its names, in any case)
  function hasFontFamily(name) {
    const wanted = String(name ?? "").trim().toLowerCase();
    if (wanted === "" || _genericFamilies.includes(wanted))
      return true;
    return Qt.fontFamilies().some(family => family.toLowerCase() === wanted);
  }

  // The distribution family (Packages.distroFamily: "arch", "fedora", or
  // "" for one axiom has no package names for), from os-release
  readonly property string distro: Packages.distroFamily(FileManager.read("/etc/os-release") ?? FileManager.read("/usr/lib/os-release"))

  // The shell lines that install these commands (or "iconFont") here: []
  // on an unknown distribution
  function installLines(keys) {
    return Packages.installLines(root.distro, keys);
  }

  // A key as people read it: "python: numpy" for "py:numpy", the font's
  // family for "iconFont"
  function label(key) {
    if (key === "iconFont")
      return Appearance.iconFamily;
    return String(key).startsWith("py:") ? "python: " + key.slice(3) : key;
  }

  // One line that installs a command here ("" on an unknown distribution)
  function installCommand(key) {
    return Packages.installCommand(root.distro, key);
  }

  // The programs features use, for the onboarder's checks. `compositors`
  // limits one to those compositors (CompositorManager.kind);
  // `alternatives` are commands that do its job as well (toolFound), the
  // command itself being what's installed when none is; one with nothing
  // to install on this distribution (Packages) is left out.
  // I18n.tr("Calculator in the launcher")
  // I18n.tr("Brightness of external monitors") I18n.tr("Copying to the clipboard")
  // I18n.tr("Reading JSON (theme integrations)") I18n.tr("Downloads (album art, Claude usage, community setups)")
  // I18n.tr("Pending package updates")
  // I18n.tr("Chat API keys in the keyring") I18n.tr("Moving notes to the trash")
  // I18n.tr("Theme generation, theme integrations and keybinds")
  // I18n.tr("Notifications from axiom itself, with their buttons")
  // I18n.tr("Idle locking and screen blanking") I18n.tr("Night light")
  // I18n.tr("X11 apps (Steam, games, older apps)")
  // I18n.tr("Clipboard history shared with other apps")
  // I18n.tr("Typing emoji from the launcher") I18n.tr("Screen recording")
  // I18n.tr("The system's sound in screen recordings")
  // I18n.tr("Annotating screenshots (swappy works too)")
  // I18n.tr("Power profiles in the quick actions")
  // I18n.tr("Theme generation from the wallpaper") I18n.tr("Calendar accounts and feeds")
  // I18n.tr("The login screen's compositor (Hyprland works too)")
  readonly property var tools: [
    {
      "command": "qalc",
      "purpose": "Calculator in the launcher"
    },
    {
      "command": "ddcutil",
      "purpose": "Brightness of external monitors"
    },
    {
      "command": "jq",
      "purpose": "Reading JSON (theme integrations)"
    },
    {
      "command": "curl",
      "purpose": "Downloads (album art, Claude usage, community setups)"
    },
    {
      "command": "checkupdates",
      "purpose": "Pending package updates"
    },
    {
      "command": "secret-tool",
      "purpose": "Chat API keys in the keyring"
    },
    {
      "command": "gio",
      "purpose": "Moving notes to the trash"
    },
    {
      "command": "python3",
      "purpose": "Theme generation, theme integrations and keybinds"
    },
    {
      "command": "py:numpy",
      "purpose": "Theme generation from the wallpaper"
    },
    {
      "command": "py:PIL",
      "purpose": "Theme generation from the wallpaper"
    },
    {
      "command": "py:icalendar",
      "purpose": "Calendar accounts and feeds"
    },
    {
      "command": "notify-send",
      "purpose": "Notifications from axiom itself, with their buttons"
    },
    {
      "command": "wlsunset",
      "purpose": "Night light, where the compositor has no gamma control",
      "compositors": ["niri"]
    },
    {
      "command": "xwayland-satellite",
      "purpose": "X11 apps (Steam, games, older apps)",
      "compositors": ["niri"]
    },
    {
      "command": "Xwayland",
      "purpose": "X11 apps (Steam, games, older apps)",
      "compositors": ["sway"]
    },
    {
      "command": "wf-recorder",
      "purpose": "Screen recording"
    },
    {
      "command": "grim",
      "purpose": "Screenshots (the picker's frozen frame)",
      "compositors": ["niri"]
    },
    {
      "command": "pactl",
      "purpose": "The system's sound in screen recordings"
    },
    {
      "command": "satty",
      "purpose": "Annotating screenshots (swappy works too)"
    },
    {
      "command": "powerprofilesctl",
      "purpose": "Power profiles in the quick actions"
    },
    // What the login screen runs in (greeter-session.sh): sway, else
    // Hyprland
    {
      "command": "sway",
      "alternatives": ["start-hyprland"],
      "purpose": "The login screen's compositor (Hyprland works too)"
    }
  ].filter(tool => Packages.applies(root.distro, tool.command) && (tool.compositors === undefined || tool.compositors.includes(CompositorManager.kind)))

  // A tool's commands: its own, then its `alternatives`
  function commandsOf(tool) {
    return [tool.command].concat(tool.alternatives ?? []);
  }

  // Whether a tool is installed (any of commandsOf): undefined until each
  // one is checked, unless one already is
  function toolFound(tool) {
    const states = root.commandsOf(tool).map(command => root.found[command]);
    if (states.includes(true))
      return true;
    return states.includes(undefined) ? undefined : false;
  }

  // The command a tool is installed as (the first of commandsOf found), or
  // its own
  function toolCommand(tool) {
    return root.commandsOf(tool).find(command => root.found[command] === true) ?? tool.command;
  }

  // { command: bool } for every command checked so far
  property var found: ({})

  // Looks the commands up (axiom's deps.check: $PATH; a "py:<module>"
  // with python3's importlib) and adds them to `found`. Without axiom
  // they stay unknown
  function check(commands) {
    const wanted = (commands ?? []).map(c => String(c).trim().split(/\s+/)[0]).filter(c => /^(py:)?[\w.+-]+$/.test(c));
    if (wanted.length === 0)
      return;
    _pendingChecks = _pendingChecks.concat(wanted);
    // Later, not now: services check while they're being built, and
    // callLater batches their calls into one lookup
    Qt.callLater(root._runLookup);
  }

  // Whether a command (its first word) is installed: undefined until checked
  function has(command) {
    return root.found[String(command ?? "").trim().split(/\s+/)[0]];
  }

  property var _pendingChecks: []

  // A lookup is running (its answer starts the next)
  property bool _busy: false

  function _runLookup() {
    if (_busy || _pendingChecks.length === 0)
      return;
    _busy = true;
    const commands = Array.from(new Set(_pendingChecks));
    _pendingChecks = [];
    BackendManager.call("deps.check", {
      "commands": commands
    }, (error, result) => {
      if (error) {
        if (error.kind !== "unavailable")
          console.warn("[DependencyManager] checking", commands.join(" "), "failed:", error.message);
      } else {
        const next = Object.assign({}, root.found);
        for (const command of commands)
          next[command] = result.found.includes(command);
        root.found = next;
      }
      // Checks asked for meanwhile go next
      root._busy = false;
      root._runLookup();
    });
  }

  // Survives hot reloads, so only a qs launch notifies again
  PersistentProperties {
    id: _run
    reloadableId: "axiomDependencies"
    property bool notified: false
    // The last missing text font notified, so each name is only notified once
    property string notifiedFont: ""
  }

  // Let the notification server come up first
  Timer {
    id: _notify
    interval: 3000
    onTriggered: {
      _run.notified = true;
      const command = root.installCommand("iconFont");
      NotificationManager.sendNotification("axiom", I18n.tr("Icon font missing"), command !== "" ? I18n.tr("Install {0} ({1}), then restart the shell.", Appearance.iconFamily, command) : I18n.tr("Install {0}, then restart the shell.", Appearance.iconFamily));
    }
  }

  // Settings commit the family on every keystroke: check once it settles
  readonly property string _textFont: Appearance.fontFamily
  on_TextFontChanged: _checkTextFont.restart()

  Timer {
    id: _checkTextFont
    interval: 3000
    onTriggered: {
      if (root.textFontInstalled)
        return;
      const family = Appearance.fontFamily;
      console.warn(`[DependencyManager] font family "${family}" is not installed: text falls back to fontconfig's default`);
      if (_run.notifiedFont === family)
        return;
      _run.notifiedFont = family;
      NotificationManager.sendNotification("axiom", I18n.tr("Font not found"), I18n.tr("No installed font is named \"{0}\", so text uses a fallback. Check the name in Settings → Look & Feel → Font.", family));
    }
  }

  Component.onCompleted: {
    _checkTextFont.start();
    if (root.iconFontInstalled)
      return;
    console.warn(`[DependencyManager] ${Appearance.iconFamily} is not installed: icons will show as words`);
    if (!_run.notified)
      _notify.start();
  }
}
