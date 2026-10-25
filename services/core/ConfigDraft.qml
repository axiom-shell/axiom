pragma ComponentBehavior: Bound
import QtQuick
import qs.components.methods

// A working copy of one config section for an editor (settings, bar,
// overlay, edge menu, keybind and monitor editors). Edits mutate `local` in place, then call
// changed(); nothing reaches the running config or disk until save().
// Not a singleton: each editor service owns one.
QtObject {
  id: root

  // Key path of the section in the config, e.g. ["Bars"]; [] is all of it
  property var path: []

  // Plain values, filled by load(): a binding here would reset the draft
  // on every config change
  property var local: null
  property var saved: null
  property bool isDirty: false

  Component.onCompleted: load()

  function _read() {
    let value = ConfigManager.config;
    for (const key of root.path)
      value = value?.[key];
    return value;
  }

  // Start over from the current config
  function load() {
    root._loadedFrom = _read();
    root.local = Utils.clone(root._loadedFrom);
    root.saved = Utils.clone(root.local);
    root.isDirty = false;
  }

  // load(), unless the draft holds unsaved edits or already holds the
  // current config: a page reopening (an editor's ensureLoaded) then
  // rebuilds nothing. The config is a new object on every change, so the
  // one it was loaded from tells whether it's current
  function loadIfStale() {
    if (!root.isDirty && (root.local === null || _read() !== root._loadedFrom))
      load();
  }

  property var _loadedFrom: null

  // After mutating `local` in place: update isDirty, and re-assign it (next
  // tick) so bindings on it see the change, since in-place mutation doesn't
  // notify. Deferred so it doesn't re-enter the binding of the control
  // that made the edit.
  function changed() {
    root.isDirty = JSON.stringify(root.local) !== JSON.stringify(root.saved);
    Qt.callLater(() => root.local = Utils.clone(root.local));
  }

  // Merges `local` onto the LATEST config (so settings edited elsewhere
  // meanwhile survive) and commits it. Returns false, staying dirty, if
  // ConfigManager rejects it.
  function save() {
    let merged = Utils.clone(root.local);
    if (root.path.length > 0) {
      merged = Utils.clone(ConfigManager.config);
      let cur = merged;
      for (let i = 0; i < root.path.length - 1; i++)
        cur = cur[root.path[i]];
      cur[root.path[root.path.length - 1]] = Utils.clone(root.local);
    }
    if (!ConfigManager.commit(merged))
      return false;
    root.saved = Utils.clone(root.local);
    root.isDirty = false;
    return true;
  }
}
