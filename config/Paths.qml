pragma Singleton
import QtQuick
import Quickshell
import qs.services.core
import qs.components.methods

// Derived, non-configurable filesystem paths (from the environment, not config).
QtObject {
  id: root

  // --- Paths (from the environment, not from any config value) ---
  readonly property string homeDirectory: Quickshell.env("HOME") + "/"
  // Shell root (this repo), always with a trailing slash. Read-only: axiom
  // writes nothing under it (a package installs it where it can't)
  readonly property string axiomPath: decodeURIComponent(Quickshell.shellDir.toString().replace("file://", "")).replace(/\/?$/, "/")
  // How compositors, binds and idle daemons call axiom: the binary that
  // runs this shell ($AXIOM_BIN), by its path (a compositor's PATH may not
  // have it). `<shellCommand> ipc <target> <fn>` calls the shell.
  readonly property string axiomBin: Quickshell.env("AXIOM_BIN") || "axiom"
  readonly property string shellCommand: `'${root.axiomBin}'`
  // What the shell runs axiom's tools with (`axiom compositor …`): the
  // binary the daemon runs now, which a dev build's re-exec may have
  // changed since $AXIOM_BIN was set (/proc follows the exec); the greeter,
  // with no daemon, runs $AXIOM_BIN (itself)
  readonly property string toolBin: Quickshell.env("AXIOM_DAEMON_PID") ? `/proc/${Quickshell.env("AXIOM_DAEMON_PID")}/exe` : root.axiomBin
  // The restart binds' command: axiom restarts the shell it runs
  readonly property string restartCommand: `${root.shellCommand} restart`
  // A line in a compositor config that starts axiom (Python regex, for
  // integration_hookup.py's `accept`): `axiom run`
  readonly property string startPattern: "(^|[\\s'\"/])axiom['\"]? +run\\b"
  readonly property string themePath: root.axiomPath + "config/themes/"
  readonly property string scriptsPath: root.axiomPath + "scripts/"
  // What ships with axiom in config/: json/ (schema, theme defaults,
  // emoji), themes/, i18n/
  readonly property string resourcePath: root.axiomPath + "config/"
  // Installed as a package (the AUR's axiom-shell): its version, from the
  // marker its PKGBUILD writes ("" for a clone: docs/dev/packaging.md).
  // The package manager updates it (SelfUpdateManager stays off) and the
  // login screen runs it (GreeterManager)
  readonly property string packagedVersion: (FileManager.read(root.axiomPath + ".packaged") ?? "").trim()
  readonly property bool packaged: packagedVersion !== ""

  // --- What axiom writes (ConfigManager.dataDirs: the XDG folders) ---

  // $XDG_CONFIG_HOME/axiom/: config.json and saved/
  readonly property string userConfigPath: ConfigManager.configDir
  // Small persisted state (StateManager), $XDG_STATE_HOME/axiom/ui/. In the
  // greeter, whose code is a root-owned copy, its own state folder instead
  readonly property string statePath: root.greeter ? root.greeterStatePath : ConfigManager.dataDirs.ui
  // Per-user state ($XDG_STATE_HOME/axiom/): secrets, chats, notification
  // history, the generated hypridle/Hyprland configs
  readonly property string userStatePath: root.greeter ? root.greeterStatePath : ConfigManager.dataDirs.state
  // $XDG_DATA_HOME/axiom/: what the user made (the default notes folder)
  readonly property string userDataPath: ConfigManager.dataDirs.data
  readonly property string defaultNotesPath: ConfigManager.dataDirs.notes
  // Themes generated from the wallpaper ("generated/<name>")
  readonly property string generatedThemesPath: ConfigManager.dataDirs.generatedThemes
  // Palettes community setups brought ("community/<id>"), $XDG_DATA_HOME/axiom/themes/
  readonly property string communityThemesPath: ConfigManager.dataDirs.communityThemes
  // The community setups catalog and its downloads, $XDG_CACHE_HOME/axiom/community/
  readonly property string communityCachePath: ConfigManager.dataDirs.cache + "community/"

  // Hyprland's config folder ($XDG_CONFIG_HOME/hypr/, where Hyprland looks)
  readonly property string hyprlandPath: (Quickshell.env("XDG_CONFIG_HOME") || root.homeDirectory + ".config").replace(/\/$/, "") + "/hypr/"
  // Sway's config folder ($XDG_CONFIG_HOME/sway/, as sway looks there first)
  readonly property string swayPath: (Quickshell.env("XDG_CONFIG_HOME") || root.homeDirectory + ".config").replace(/\/$/, "") + "/sway/"
  // niri's config folder ($XDG_CONFIG_HOME/niri/, where niri looks)
  readonly property string niriPath: (Quickshell.env("XDG_CONFIG_HOME") || root.homeDirectory + ".config").replace(/\/$/, "") + "/niri/"
  // Where to look for data the system (or the user) installed, most
  // important first: $XDG_DATA_HOME, then $XDG_DATA_DIRS (DataDirs.searchDirs;
  // /usr/share isn't where every distro has it). No trailing slashes.
  readonly property var dataSearchDirs: DataDirs.searchDirs({
    "HOME": Quickshell.env("HOME"),
    "XDG_DATA_HOME": Quickshell.env("XDG_DATA_HOME"),
    "XDG_DATA_DIRS": Quickshell.env("XDG_DATA_DIRS")
  })
  // $XDG_RUNTIME_DIR, the user's own 0700 tmpfs (always there, unlike
  // runtimePath, which is made by whatever writes into it)
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  // Scratch files that go with the session: unsaved chat attachments,
  // clipboard thumbnails, copy-only screenshots, album art
  readonly property string runtimePath: root.runtimeDir + "/axiom/"

  // --- The greeter (GreeterManager, greeter.qml) ---

  // This instance is the greeter: greetd's login screen, running as
  // greetd's user from the installed copy (set by greeter-session.sh;
  // ConfigManager reads the same variable, as it reads no reader)
  readonly property bool greeter: Quickshell.env("AXIOM_GREETER") === "1"
  // The greeter's folder: config/ (the bundle the user's axiom exports,
  // theirs) and state/ (the greeter's: last user and sessions)
  readonly property string greeterDir: (Quickshell.env("AXIOM_GREETER_DIR") || "/var/lib/axiom-greeter") + "/"
  readonly property string greeterBundlePath: root.greeterDir + "config/"
  readonly property string greeterStatePath: root.greeterDir + "state/"
  // The snapshot of the bundle its install took (greeter_install.sh): in
  // the install folder the session script names, else beside the code (a
  // packaged axiom's install folder isn't its code's)
  readonly property string greeterFallbackUrl: Quickshell.env("AXIOM_GREETER_FALLBACK") ? "file://" + Quickshell.env("AXIOM_GREETER_FALLBACK") : Qt.resolvedUrl("../fallback/")

  // A theme's JSON file, by its Appearance.theme name: "generated/<name>"
  // from generatedThemesPath, "community/<id>" from communityThemesPath,
  // the rest from the bundled themes
  function themeFile(name) {
    const prefixed = String(name).match(/^(generated|community)\/(.+)$/);
    if (!prefixed)
      return root.themePath + name + ".json";
    return (prefixed[1] === "generated" ? root.generatedThemesPath : root.communityThemesPath) + prefixed[2] + ".json";
  }

  // The file a type is loaded from (docs/dev/core/config-v2.md, rule 11):
  // a type is a folder <root>/<Type>/ with <Type>.qml. A content name with
  // a slash names another file in a type's folder ("Submenu/MenuSubmenu").
  function widgetUrl(type) {
    return "file://" + root.axiomPath + "components/bar/widgets/" + type + "/" + type + ".qml";
  }
  function contentUrl(name) {
    const file = String(name).includes("/") ? name : name + "/" + name;
    return "file://" + root.axiomPath + "components/content/" + file + ".qml";
  }
  function viewUrl(type) {
    return "file://" + root.axiomPath + "components/views/" + type + "/" + type + ".qml";
  }

  // A path from config or the user: trimmed, a leading ~ as home, no
  // trailing slash ("~/Pictures/" -> "/home/<user>/Pictures")
  function expandHome(path) {
    return String(path ?? "").trim().replace(/^~(?=\/|$)/, Quickshell.env("HOME")).replace(/(.)\/+$/, "$1");
  }

  // A path to show: home as ~ ("/home/<user>/x" -> "~/x")
  function shortenHome(path) {
    const home = Quickshell.env("HOME");
    return path === home || String(path).startsWith(home + "/") ? "~" + String(path).slice(home.length) : String(path);
  }
}
