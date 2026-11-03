pragma Singleton
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core

/*
 * The Material Symbols the bundled icon font draws (Appearance.iconFamily),
 * for icon pickers (SchemaField's icon field). The catalog is
 * config/json/material-symbols.json (built with the font by
 * scripts/generate_icons.py): [name, "search words"], most popular first.
 * `search(query, limit)` ranks names (Search.rankIcons), reading the
 * catalog then if it's not read yet (a picker opened or typed in).
 * `isKnown(name)` says whether the font has it: until the catalog is read,
 * every name is, and asking schedules the read after the frame, so a page
 * of icon fields never waits on it (a binding asking runs again once read).
 */
QtObject {
  id: root

  // The names best matching `query` (the most popular with none)
  function search(query, limit) {
    root._load();
    return Search.rankIcons(root._entries, query, limit);
  }

  // Whether the font has an icon of this name (true until the catalog is read)
  function isKnown(name) {
    if (!root._loaded) {
      Qt.callLater(root._load);
      return true;
    }
    // No catalog (already warned): no name is doubted
    return root._entries.length === 0 || root._names[String(name ?? "").trim()] === true;
  }

  // --- Private ---

  property bool _loaded: false
  property var _entries: []
  // Each name as a key: an object, since a Set of them is ~30x slower to
  // build in this engine
  property var _names: ({})

  // Reads the catalog, once; [] when the file can't be read
  function _load() {
    if (root._loaded)
      return;
    const text = FileManager.read(Paths.resourcePath + "json/material-symbols.json");
    let entries = [];
    try {
      entries = text ? JSON.parse(text) : [];
    } catch (e) {
      console.warn("[IconManager] Could not parse material-symbols.json:", e);
    }
    if (entries.length === 0)
      console.warn("[IconManager] No icon catalog: run scripts/generate_icons.py");
    root._entries = entries;
    const names = Object.create(null);
    entries.forEach(entry => names[entry[0]] = true);
    root._names = names;
    root._loaded = true;
  }
}
