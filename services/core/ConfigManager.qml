pragma Singleton
import QtQuick

import Quickshell

import qs.components.methods

/* The config, as axiom (the binary, the shell's parent: `axiom run`) has
 * it. axiom owns config.json: it loads it (converting older files),
 * normalizes it and writes it. The shell reads the snapshot axiom wrote for
 * its start ($AXIOM_CONFIG) and the pushes after (config.changed); a write
 * is checked here against the schema, applied at once and sent, and
 * axiom's answer stands. The greeter runs on the snapshot `axiom greeter`
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

  // Unsaved edits an editor shows live, by top-level section ({ Bars: {...} }).
  // Readers of that section prefer them to `config`; they're never merged
  // into it or saved, so other saves and pushes leave them alone.
  readonly property var previews: _previews

  function setPreview(section, value) {
    const previews = Object.assign({}, root._previews);
    previews[section] = Utils.clone(value);
    root._previews = previews;
  }

  // `value` with the defaults of a schema definition (e.g. "Bar",
  // "OverlayModule") filled in: a new entry for an editor to add
  function withDefaults(value, definition) {
    return SchemaValidation.applyDefaults(value, {
      "$ref": "#/definitions/" + definition
    }, root._configSchema);
  }

  function clearPreview(section) {
    if (!(section in root._previews))
      return;
    const previews = Object.assign({}, root._previews);
    delete previews[section];
    root._previews = previews;
  }

  // The theme by name (e.g. "catppuccin-mocha", "generated/wallpaper-tonal-dark")
  function setTheme(themeName) {
    if (_config.Appearance.theme.name === themeName)
      return;
    console.log("[ConfigManager] Setting theme to '" + themeName + "'");
    _config.Appearance.theme.name = themeName;
    saveConfig();
  }

  // A monitor's wallpaper (a file URL). The primary monitor's is also
  // Appearance.wallpaper.file. Only picks by hand write these: rotation
  // and the light/dark wallpapers are ThemeManager's.
  function setWallpaper(wallpaperUrl, monitor, primary) {
    const wallpaper = _config.Appearance.wallpaper;
    if (wallpaper.perScreen[monitor] === wallpaperUrl && (!primary || wallpaper.file === wallpaperUrl))
      return;
    console.log("[ConfigManager] Setting wallpaper on", monitor, "to", wallpaperUrl);
    wallpaper.perScreen[monitor] = wallpaperUrl;
    if (primary)
      wallpaper.file = wallpaperUrl;
    saveConfig();
  }

  // Several monitors' wallpapers (monitor name → file URL) with one save;
  // primary's is also Appearance.wallpaper.file
  function setWallpapers(wallpapers, primary) {
    const wallpaper = _config.Appearance.wallpaper;
    const monitors = Object.keys(wallpapers).filter(monitor => wallpaper.perScreen[monitor] !== wallpapers[monitor] || (monitor === primary && wallpaper.file !== wallpapers[monitor]));
    if (monitors.length === 0)
      return;
    console.log("[ConfigManager] Setting wallpapers on", monitors.join(", "));
    for (const monitor of monitors) {
      wallpaper.perScreen[monitor] = wallpapers[monitor];
      if (monitor === primary)
        wallpaper.file = wallpapers[monitor];
    }
    saveConfig();
  }

  // Saves the running config (after edits to it in place); true if it was
  // valid and sent to axiom
  function saveConfig() {
    if (!_maySave())
      return false;
    if (!SchemaValidation.validateAgainstSchema(root._config, root._configSchema)) {
      console.error("[ConfigManager] The config doesn't validate against the schema; not saving.");
      return false;
    }
    root._config = Utils.clone(root._config);
    _send(root._config, true);
    return true;
  }

  // Replaces the running config with `object` (defaults filled) and saves
  // it; false and no change if it doesn't validate. `takeover` false keeps
  // the `x-takeover` settings as axiom has them: a save that changes none
  // (one made from a config that may predate a takeover write axiom made)
  function commit(object, takeover = true) {
    if (!_maySave())
      return false;
    const filled = SchemaValidation.applyDefaults(Utils.clone(object), root._configSchema);
    if (!SchemaValidation.validateAgainstSchema(filled, root._configSchema)) {
      console.error("[ConfigManager] Rejected config: it does not validate against the schema.");
      return false;
    }
    root._config = filled;
    _send(filled, takeover);
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

  // Shows `object` in place of the running config without saving it (the
  // settings page's live edits, until Save commits them); a push or a save
  // replaces it
  function applyConfig(object) {
    if (SchemaValidation.validateAgainstSchema(object, root._configSchema))
      root._config = Utils.clone(object);
  }

  // Discards in-memory edits: the config as axiom has it
  function hardResetConfig() {
    BackendManager.call("config.get", null, (error, result) => {
      if (!error && result?.config)
        root._config = result.config;
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
    BackendManager.listen("config.changed", params => {
      console.log("[ConfigManager] axiom pushed the config, revision", params.revision);
      root._config = params.config;
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
      // A push missed while disconnected (a re-exec): read it again
      root.hardResetConfig();
    }
  }

  function _applyState(state) {
    if (state.blocked && !root._savesBlocked)
      console.error("[ConfigManager] config.json doesn't load; axiom keeps the last good config and blocks saves until it's fixed.", (state.issues ?? []).map(i => i.path + ": " + i.message).join("; "));
    root._savesBlocked = !!state.blocked;
  }

  // Sends a config to axiom, which writes it (or says why not, and what's
  // running goes back to its)
  function _send(config, takeover) {
    BackendManager.call("config.replace", {
      "config": config,
      "takeover": takeover
    }, (error, result) => {
      if (!error)
        return;
      console.error("[ConfigManager] axiom refused the config:", error.message, (error.issues ?? []).map(i => i.path + ": " + i.message).join("; "));
      root.hardResetConfig();
    });
  }

  readonly property string _snapshotPath: Quickshell.env("AXIOM_CONFIG") ?? ""
  property var _configSchema: _loadSchema()
  property var _config: _readSnapshot()
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
