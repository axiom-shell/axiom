pragma Singleton
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core

/*
 * The Material Symbols the bundled icon font draws (Appearance.iconFamily),
 * for icon pickers (forms/SchemaIconField). The catalog is
 * config/json/material-symbols.json (built with the font by
 * scripts/generate_icons.py): [name, "search words"], most popular first,
 * read the first time it's asked for. `search(query, limit)` ranks names
 * (Search.rankIcons); `isKnown(name)` says whether the font has it.
 */
QtObject {
  id: root

  // Every icon, loaded on first use; [] when the file can't be read
  function entries() {
    const cache = root._cache;
    if (cache.entries === null) {
      const text = FileManager.read(Paths.resourcePath + "json/material-symbols.json");
      try {
        cache.entries = text ? JSON.parse(text) : [];
      } catch (e) {
        console.warn("[IconManager] Could not parse material-symbols.json:", e);
        cache.entries = [];
      }
      if (cache.entries.length === 0)
        console.warn("[IconManager] No icon catalog: run scripts/generate_icons.py");
      cache.names = new Set(cache.entries.map(entry => entry[0]));
    }
    return cache.entries;
  }

  // The names best matching `query` (the most popular with none)
  function search(query, limit) {
    return Search.rankIcons(root.entries(), query, limit);
  }

  // Whether the font has an icon of this name
  function isKnown(name) {
    root.entries();
    return root._cache.names.has(String(name ?? "").trim());
  }

  // --- Private ---

  // Filled in place, not assigned: loading it from a binding (isKnown in
  // a field's `visible`) must not change a property that binding reads
  readonly property var _cache: ({
      "entries": null,
      "names": null
    })
}
