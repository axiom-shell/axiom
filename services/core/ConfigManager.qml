pragma Singleton
import QtQuick

import Quickshell

import qs.components.methods

/* The config, as axiom (the binary, the shell's parent: `axiom run`) has
 * it. axiom owns config.json: it loads it (converting older files),
 * normalizes it and writes it. The shell reads the snapshot axiom wrote for
 * its start ($AXIOM_CONFIG) and the pushes after (config.changed); a write
 * is applied at once and sent, and axiom's answer stands (it validates). The greeter runs on the snapshot `axiom greeter`
 * made from the exported bundle, and writes nothing. Without axiom (qs
 * started by hand) there is no config: the shell shows only a notice
 * (shell.qml, `available`). docs/dev/core/config-manager.md */
QtObject {
  id: root

  // --- Public ---
  readonly property var config: _config
  readonly property var configSchema: _configSchema
  // axiom handed this shell a config (false: started by hand)
  readonly property bool available: _snapshotPath !== "" && _config !== null
  // The config version this shell's schema is (format 2 counts on from
  // format 1's 75): what a shared file or catalog entry must not be newer than
  readonly property int currentVersion: _configSchema?.properties?.version?.default ?? 0
  readonly property string configDir: dataDirs.config
  readonly property string configFile: "config.json"

  // Where axiom keeps what it writes (DataDirs: config, state, ui, data,
  // notes, generatedThemes, communityThemes, cache), read by Paths
  readonly property var dataDirs: DataDirs.xdg({
    "HOME": Quickshell.env("HOME"),
    "XDG_CONFIG_HOME": Quickshell.env("XDG_CONFIG_HOME"),
    "XDG_STATE_HOME": Quickshell.env("XDG_STATE_HOME"),
    "XDG_DATA_HOME": Quickshell.env("XDG_DATA_HOME"),
    "XDG_CACHE_HOME": Quickshell.env("XDG_CACHE_HOME")
  })

  // True while config.json on disk doesn't load (axiom says so): the shell
  // runs on the last good config, and saves are refused until the file is
  // fixed or a saved config is restored
  readonly property bool savesBlocked: _savesBlocked

  // The greeter (greetd's login screen, greeter.qml) runs read-only on the
  // config `axiom greeter` made from the bundle, never on config.json
  readonly property bool greeter: Quickshell.env("AXIOM_GREETER") === "1"
  // Where the greeter's config came from: "bundle", "fallback" (the
  // snapshot taken when the greeter was installed) or "defaults" (axiom
  // greeter says, $AXIOM_GREETER_SOURCE); "" outside the greeter
  readonly property string greeterSource: greeter ? (Quickshell.env("AXIOM_GREETER_SOURCE") ?? "") : ""

  // The config as it shows: `config` with the previews laid over it. What
  // readers read; a save starts from `config`, never from this
  readonly property var live: ConfigOps.apply(_config, ConfigOps.previewOps(_previews))

  // Unsaved edits shown live, by dotted key path: an editor's whole
  // section ({ Bars: {...} }) or one setting ("Appearance.font.size", the
  // settings page). A deeper path shows through a section laid over it.
  // They're never merged into `config` or saved, so other saves and pushes
  // leave them alone.
  readonly property var previews: _previews

  function setPreview(path, value) {
    setPreviews({
      [path]: value
    });
  }

  function clearPreview(path) {
    setPreviews({
      [path]: undefined
    });
  }

  // Several previews in one change (path → value; undefined clears one)
  function setPreviews(values) {
    let previews = root._previews;
    for (const path of Object.keys(values)) {
      if (values[path] !== undefined || path in previews)
        previews = Utils.withEntry(previews, path, values[path] === undefined ? undefined : Utils.clone(values[path]));
    }
    if (previews !== root._previews)
      root._previews = previews;
  }

  // `value` with the defaults of a schema definition (e.g. "Bar",
  // "OverlayModule") filled in: a new entry for an editor to add
  function withDefaults(value, definition) {
    return SchemaValidation.applyDefaults(value, {
      "$ref": "#/definitions/" + definition
    }, root._configSchema);
  }

  // The theme by name (e.g. "catppuccin-mocha", "generated/wallpaper-tonal-dark")
  function setTheme(themeName) {
    if (_config.Appearance.theme.name === themeName)
      return;
    console.log("[ConfigManager] Setting theme to '" + themeName + "'");
    const next = Utils.clone(_config);
    next.Appearance.theme.name = themeName;
    commit(next);
  }

  // A monitor's wallpaper (a file URL). The primary monitor's is also
  // Appearance.wallpaper.file. Only picks by hand write these: rotation
  // and the light/dark wallpapers are ThemeManager's.
  function setWallpaper(wallpaperUrl, monitor, primary) {
    setWallpapers({
      [monitor]: wallpaperUrl
    }, primary ? monitor : "");
  }

  // Several monitors' wallpapers (monitor name → file URL) with one save;
  // primary's is also Appearance.wallpaper.file
  function setWallpapers(wallpapers, primary) {
    const next = Utils.clone(_config);
    const wallpaper = next.Appearance.wallpaper;
    const monitors = Object.keys(wallpapers).filter(monitor => wallpaper.perScreen[monitor] !== wallpapers[monitor] || (monitor === primary && wallpaper.file !== wallpapers[monitor]));
    if (monitors.length === 0)
      return;
    console.log("[ConfigManager] Setting wallpapers on", monitors.join(", "));
    for (const monitor of monitors) {
      wallpaper.perScreen[monitor] = wallpapers[monitor];
      if (monitor === primary)
        wallpaper.file = wallpapers[monitor];
    }
    commit(next);
  }

  // Replaces the running config with `object` (defaults filled) and saves
  // what differs from it (config.set's ops); false and no change while
  // saves can't be made. axiom validates: a refusal reads its config back.
  // axiom keeps the `x-takeover` settings as it has them
  // unless `takeover`: only a save from a takeover setting's own control
  // sends it (SettingsManager._takesOver), so a save made from a config
  // that predates a takeover write axiom made can't put the stale value back
  function commit(object, takeover = false) {
    if (!_maySave())
      return false;
    const filled = SchemaValidation.applyDefaults(Utils.clone(object), root._configSchema);
    const ops = ConfigOps.diff(root._config, filled);
    if (ops.length === 0)
      return true;
    root._config = filled;
    BackendManager.call("config.set", {
      "ops": ops,
      "takeover": takeover
    }, (error, result) => {
      if (!error)
        return;
      console.error("[ConfigManager] axiom refused the config:", error.message, (error.issues ?? []).map(i => i.path + ": " + i.message).join("; "));
      root.hardResetConfig();
    });
    return true;
  }

  // Replaces the whole config with a parsed one (a saved config, an
  // import), of any version axiom reads: axiom loads it as it loads
  // config.json (an older file converted) and keeps the `x-takeover`
  // settings (compositor mode, locker, idle, polkit, greeter) as they are:
  // only their own cards switch them. It also lifts savesBlocked.
  // done(ok) once axiom has answered.
  function restoreConfig(object, done) {
    if (root.greeter || !root.available) {
      done?.(false);
      return;
    }
    BackendManager.call("config.restore", {
      "config": object
    }, (error, result) => {
      if (error)
        console.error("[ConfigManager] axiom refused the config:", error.message, (error.issues ?? []).map(i => i.path + ": " + i.message).join("; "));
      done?.(!error);
    });
  }

  // Discards in-memory edits: the config as axiom has it
  function hardResetConfig() {
    BackendManager.call("config.get", null, (error, result) => {
      if (!error && result?.config) {
        root._config = result.config;
        root._revision = result.revision;
      }
    });
  }

  // --- Private Implementation ---
  Component.onCompleted: {
    if (root.greeter)
      console.log("[ConfigManager] Greeter config from the", root.greeterSource || "defaults");
    else if (root.available) {
      console.log("[ConfigManager] Config from axiom.");
      root._listen();
    }
  }

  function _maySave() {
    if (root.greeter || !root.available)
      return false;
    if (root._savesBlocked) {
      console.warn("[ConfigManager] config.json doesn't load; not saving until it is fixed (or a saved config is restored).");
      return false;
    }
    return true;
  }

  // What axiom pushes
  function _listen() {
    // The ops from the revision before: applied when that's the one
    // here, else (one missed, or ops this can't apply) the config is read
    // again. The shell's own saves come back too, already applied
    BackendManager.listen("config.changed", params => {
      if (root._revision < 0 || params.revision <= root._revision)
        return;
      const next = params.revision === root._revision + 1 ? ConfigOps.apply(root._config, params.changes ?? []) : null;
      console.log("[ConfigManager] axiom pushed the config, revision", params.revision);
      if (next === null) {
        root.hardResetConfig();
        return;
      }
      root._config = next;
      root._revision = params.revision;
    });
    BackendManager.listen("config.state", params => root._applyState(params));
    // `axiom run --dev` rebuilt the schema from its YAML source
    BackendManager.listen("schema.changed", () => {
      console.log("[ConfigManager] The schema was rebuilt; reading it again.");
      root._configSchema = root._loadSchema();
    });
    BackendManager.listen("schema.error", params => console.error("[ConfigManager] the schema source doesn't build:", params.message));
  }

  property Connections _backend: Connections {
    target: root.available && !root.greeter ? BackendManager : null

    function onGreeted() {
      const state = BackendManager.hello?.state ?? {};
      root._applyState(state);
      // The first run is this session's: acknowledged, so a QML reload
      // doesn't start the onboarding again
      if (state.firstRun) {
        root._firstRun = true;
        BackendManager.call("config.ackFirstRun", null, null);
      }
      // A push missed while disconnected (a re-exec, which may count
      // the revisions again): read it again, ignoring pushes until then
      root._revision = -1;
      root.hardResetConfig();
    }
  }

  function _applyState(state) {
    if (state.blocked && !root._savesBlocked)
      console.error("[ConfigManager] config.json doesn't load; axiom keeps the last good config and blocks saves until it's fixed.", (state.issues ?? []).map(i => i.path + ": " + i.message).join("; "));
    root._savesBlocked = !!state.blocked;
  }

  readonly property string _snapshotPath: Quickshell.env("AXIOM_CONFIG") ?? ""
  property var _configSchema: _loadSchema()
  property var _config: _readSnapshot()
  // The revision `_config` is (axiom's count of changes); -1 until read
  // (config.get, when the connection says hello)
  property int _revision: -1
  property bool _savesBlocked: false
  property var _previews: ({})

  // The schema axiom built from the tree, else the tree's own build
  function _loadSchema() {
    const built = Quickshell.env("AXIOM_SCHEMA") ?? "";
    const text = FileManager.read(built ? "file://" + built : Qt.resolvedUrl("../../config/json/config.schema.json"));
    try {
      return text ? JSON.parse(text) : {};
    } catch (e) {
      console.error("[ConfigManager] The schema isn't JSON:", e);
      return {};
    }
  }

  // The config axiom wrote for the shell's start: already loaded,
  // converted and filled
  function _readSnapshot() {
    if (root._snapshotPath === "")
      return null;
    const text = FileManager.read("file://" + root._snapshotPath);
    try {
      if (text)
        return JSON.parse(text);
    } catch (e) {
      console.error("[ConfigManager] axiom's config snapshot isn't JSON:", e);
    }
    return SchemaValidation.applyDefaults({}, _loadSchema());
  }

  // Set when axiom found no config.json: a first run (the onboarder starts
  // from it), once per session
  readonly property bool firstRun: _firstRun
  property bool _firstRun: false
}
