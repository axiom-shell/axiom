pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel

import qs.config
import qs.services.ui
import qs.services.apps

/**
 * Named snapshots of the config (one JSON file each in
 * $XDG_CONFIG_HOME/axiom/saved/) and shared configs: the examples shipped in
 * examples/, imported files, exports to the home folder. axiom does the
 * work (saved.* and share.*, backend/internal/saved): a snapshot holds the
 * look, personal parts and commands (by the schema's x-scope) and the
 * wallpaper setup (x-snapshot), in the export format, so a saved file can
 * be shared or imported as it is; restoring applies it like an example,
 * plus the wallpaper setup where its files are still there. Applying a
 * shared file first saves the running config as "before-<name>". Files of
 * any version axiom reads are taken (an older one is converted), and
 * nothing loaded changes a takeover setting (x-takeover). This keeps what
 * the settings page shows: the list, the active snapshot, a status line.
 */
QtObject {
  id: root

  readonly property string savedDir: Paths.userConfigPath + "saved/"
  // [{ name, title, description }] by name, from examples/*.json
  readonly property var examples: _examples
  // Newest first; roles: fileBaseName, filePath, fileModified
  readonly property FolderListModel model: _model
  // Last save/restore/delete outcome, for the settings UI
  property string status: ""
  // The saved config the running one was last saved as or restored from,
  // "" for none (or once its file is gone): the one the settings UI offers
  // to overwrite
  readonly property string active: _state.active ?? ""
  // Whether the running config's snapshot parts differ from the active
  // saved one's (machine settings, which restoring doesn't change, are left
  // out)
  readonly property bool modified: _state.modified ?? false
  // The shared setup the active saved config was saved from, unchanged
  // since: "" for one the user saved, or saved over
  readonly property string activeSource: _state.activeSource ?? ""
  // An imported file awaiting confirmation: { name, title, description,
  // path, hasPersonal, hasCommands } (hasPersonal: the file holds
  // preferences, keybinds or apps; hasCommands: commands), or null
  property var importing: null
  // The file picker is open
  readonly property bool picking: FilePickerManager.running

  // An example, import or shared setup was applied as `name` (its backup
  // is "before-<name>"), or failed to be (status says why). Once applied,
  // it's saved as its own snapshot ("example-<name>", "import-<name>" or
  // the shared file's), the active one.
  signal applied(string name)
  signal applyFailed(string name)

  property var _state: ({})
  property var _examples: []
  property bool _busy: false

  Component.onCompleted: {
    BackendManager.listen("saved.state", state => root._state = state);
    root._refresh();
  }

  property Connections _backend: Connections {
    target: BackendManager

    function onGreeted() {
      root._refresh();
    }
  }

  function _refresh() {
    BackendManager.call("saved.state", null, (error, state) => {
      if (!error)
        root._state = state;
    });
    BackendManager.call("share.examples", null, (error, list) => {
      if (!error)
        root._examples = list;
    });
  }

  function sanitize(name) {
    return name.trim().replace(/[^A-Za-z0-9 _.-]/g, "_").replace(/^\.+/, "");
  }

  function exists(name) {
    const fileName = sanitize(name) + ".json";
    for (let i = 0; i < _model.count; i++) {
      if (_model.get(i, "fileName") === fileName)
        return true;
    }
    return false;
  }

  // Saves the running config's snapshot parts under `name`, replacing any
  // existing snapshot of that name. Unsaved settings edits go first (the
  // settings page saves before asking).
  function save(name) {
    if (sanitize(name) === "") {
      root.status = I18n.tr("Enter a name to save as");
      return;
    }
    BackendManager.call("saved.save", {
      "name": name
    }, (error, result) => {
      root.status = error ? I18n.tr("Failed to save \"{0}\"", sanitize(name)) : I18n.tr("Saved \"{0}\"", result.name);
      if (error)
        console.warn("[SavedConfigsManager] Saving", name, "failed:", error.message);
    });
  }

  function restore(name) {
    BackendManager.call("saved.restore", {
      "name": name
    }, error => {
      if (error) {
        console.warn("[SavedConfigsManager] Restoring", name, "failed:", error.message);
        root.status = root._refusal(error, name);
        return;
      }
      SettingsManager.loadConfig();
      root.status = I18n.tr("Restored \"{0}\"", name);
    });
  }

  // Applies the schema defaults like an example (the look, personal parts
  // and commands; machine settings stay), after saving the running config as
  // "before-defaults"
  function restoreDefaults() {
    root._apply("defaults", "share.defaults", {}, "defaults");
  }

  // Applies an example's look, after saving the running config as
  // "before-<name>"
  function applyExample(name) {
    root._apply(name, "share.example", {
      "name": name
    }, name);
  }

  // Opens the desktop's file picker; the chosen file goes to openImport
  function browseImport() {
    FilePickerManager.pick(root, I18n.tr("Import a configuration"), {
      "filter": "JSON:*.json"
    }, path => root.openImport(path), () => root.status = I18n.tr("No file picker could be opened"));
  }

  // Reads a shared file (an export, an example, or a whole config.json of
  // any version) as `importing`, for the settings page to confirm
  function openImport(path) {
    root.importing = null;
    const fileName = path.split("/").pop();
    BackendManager.call("share.open", {
      "path": path
    }, (error, preview) => {
      if (error) {
        console.warn("[SavedConfigsManager] Can't import", path + ":", error.message);
        root.status = root._refusal(error, fileName);
        return;
      }
      root.importing = preview;
      root.status = "";
    });
  }

  // Applies `importing` (its personal parts too when `personal`:
  // preferences, keybinds, apps; its commands when `commands`), after
  // saving the running config as "before-<name>"
  function confirmImport(personal, commands) {
    const pending = root.importing;
    root.importing = null;
    if (!pending)
      return;
    root._apply(pending.name, "share.import", {
      "path": pending.path,
      "personal": personal,
      "commands": commands
    }, pending.name);
  }

  function cancelImport() {
    root.importing = null;
  }

  // Applies a shared file at `path` straight away, its look only, after
  // saving the running config as "before-<name>", then saves the result as
  // `snapshot`: a community setup (CommunitySetupsManager). False when
  // another apply is under way.
  function applyShared(name, path, title, snapshot) {
    return root._apply(name, "share.applyShared", {
      "name": name,
      "path": path,
      "snapshot": snapshot
    }, title);
  }

  // Writes the running config's look (and its personal parts when
  // `personal`, its commands when `commands`) to
  // ~/axiom-<name>-<date>-<time>.json, holding only what differs from the
  // defaults: a file to share, in the format examples and imports use.
  // `places`: per-monitor parts name their monitor by its place
  function exportConfig(personal, commands, places = true) {
    BackendManager.call("share.export", {
      "personal": personal,
      "commands": commands,
      "places": places
    }, (error, result) => {
      root.status = error ? I18n.tr("Failed to export") : I18n.tr("Exported to {0}", Paths.shortenHome(result.path));
      if (error)
        console.warn("[SavedConfigsManager] Export failed:", error.message);
    });
  }

  function remove(name) {
    BackendManager.call("saved.remove", {
      "name": name
    }, error => root.status = error ? I18n.tr("Failed to delete \"{0}\"", name) : I18n.tr("Deleted \"{0}\"", name));
  }

  // One apply at a time: a second would replace the first's backup
  // rpc: share.defaults, share.example, share.import, share.applyShared
  function _apply(name, method, params, label) {
    if (root._busy) {
      root.status = I18n.tr("Busy, try again");
      return false;
    }
    root._busy = true;
    BackendManager.call(method, params, (error, result) => {
      root._busy = false;
      if (error) {
        console.warn("[SavedConfigsManager] Applying", label, "failed:", error.message);
        root.status = root._refusal(error, label);
        root.applyFailed(name);
        return;
      }
      SettingsManager.loadConfig();
      root.status = result.saved ? I18n.tr("Applied \"{0}\" as \"{1}\". The previous configuration is saved as \"{2}\".", label, result.saved, result.backup) : I18n.tr("Applied \"{0}\". The previous configuration is saved as \"{1}\".", label, result.backup);
      root.applied(name);
    });
    return true;
  }

  // Why axiom refused a file, for people
  function _refusal(error, label) {
    const message = error.message ?? "";
    if (message.includes("take something over"))
      return I18n.tr("config.json is broken and the settings that take something over on this PC aren't known, so nothing replaces it. Fix it by hand or delete it.");
    if (message.includes("newer axiom"))
      return I18n.tr("\"{0}\" is from a newer axiom. Update axiom to import it.", label);
    if (message.includes("no config version"))
      return I18n.tr("\"{0}\" has no config version, so it can't be imported", label);
    if (message.includes("can't be read") || error.kind === "not_found")
      return I18n.tr("\"{0}\" could not be read", label);
    return I18n.tr("\"{0}\" is not a valid config", label);
  }

  // The folder must exist before FolderListModel watches it, or it never
  // picks up files saved later: axiom made it on its first save; until
  // then this shows none
  property FolderListModel _model: FolderListModel {
    folder: "file://" + root.savedDir
    nameFilters: ["*.json"]
    showDirs: false
    sortField: FolderListModel.Time
  }
}
