pragma Singleton
import QtQuick

// The Keybinds page's filter over KeybindManager.keybindings: a search plus
// toggle chips in three groups (sections, modifiers, source). Chips in a
// group are alternatives; the groups, and the search, all have to match.
// A group with nothing selected doesn't filter.
QtObject {
  id: root

  // A section's chip key: its title, or one no title can be for the
  // undescribed binds (whose title is "" like the section "Other")
  function sectionKey(section) {
    return section.undescribed ? "\u0001undescribed" : section.title;
  }

  // Whether `row` ({ combos, axiom, user }) passes the modifier and source
  // chips: some combo holds every selected modifier, and the row has binds
  // from a selected source ("axiom" | "user")
  function rowPasses(row, mods, sources) {
    if (mods.length > 0 && !row.combos.some(combo => mods.every(mod => combo.mods.includes(mod))))
      return false;
    if (sources.length > 0 && !sources.some(source => row[source]))
      return false;
    return true;
  }

  function _matches(text, query) {
    return !!text && text.toLowerCase().includes(query);
  }

  function _rowMatches(row, query) {
    return _matches(row.label, query) || row.combos.some(combo => combo.mods.concat(combo.keys).some(key => _matches(key, query)));
  }

  /**
   * The sections with their binds that pass: `query` (matched against a
   * section's title, which keeps all its rows, a row's label and its keys,
   * case-insensitively) and `filters` ({ sections: [sectionKey], mods:
   * ["SUPER", …], sources: ["axiom" | "user"], ids: [BindKeys.keyId] (a
   * row holding one of them; null doesn't filter) }). Sections left with
   * no binds are dropped.
   */
  function filter(sections, query, filters) {
    const needle = String(query ?? "").trim().toLowerCase();
    const keys = filters?.sections ?? [];
    const mods = filters?.mods ?? [];
    const sources = filters?.sources ?? [];
    const ids = filters?.ids ?? null;
    const result = [];
    for (const section of sections ?? []) {
      if (keys.length > 0 && !keys.includes(sectionKey(section)))
        continue;
      const titleMatches = needle === "" || _matches(section.title, needle);
      const binds = section.binds.filter(row => rowPasses(row, mods, sources) && (ids === null || (row.ids ?? []).some(id => ids.includes(id))) && (titleMatches || _rowMatches(row, needle)));
      if (binds.length === 0)
        continue;
      result.push(binds.length === section.binds.length ? section : Object.assign({}, section, {
        "binds": binds
      }));
    }
    return result;
  }

  // Sections split into `count` columns for a masonry layout: each goes to
  // the shortest column so far, by rows (a heading counts 1.5, each
  // modifier group's header 1 (BindRows.byModifiers), the undescribed
  // section's note 2 more)
  function columns(sections, count) {
    const result = [];
    const heights = [];
    for (let i = 0; i < Math.max(1, count); i++) {
      result.push([]);
      heights.push(0);
    }
    for (const section of sections ?? []) {
      const target = heights.indexOf(Math.min(...heights));
      result[target].push(section);
      heights[target] += 1.5 + section.binds.length + BindRows.byModifiers(section.binds).filter(group => group.mods.length > 0).length + (section.undescribed ? 2 : 0);
    }
    return result;
  }
}
