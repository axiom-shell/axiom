pragma Singleton
import QtQuick

// How the editors' libraries (bar widgets, overlay modules) order their
// types: by label, or by group (the schema's `x-libraryGroups`, in order)
// and by label within each, and which of them a search finds. `labelOf`
// gives a type's shown (translated) label, `headingOf` a group's heading.
QtObject {
  id: root

  // A copy of `types` by label, in the user's locale
  function sorted(types, labelOf) {
    return (types ?? []).map(type => ({
          "type": type,
          "label": String(labelOf(type))
        })).sort((a, b) => a.label.localeCompare(b.label)).map(entry => entry.type);
  }

  // The types whose shown label, type or group heading holds `query`
  // (any case); all of them for a blank one
  function filtered(types, query, labelOf, headingOf) {
    const q = String(query ?? "").trim().toLowerCase();
    if (q === "")
      return types ?? [];
    const has = text => String(text ?? "").toLowerCase().includes(q);
    return (types ?? []).filter(type => has(labelOf(type)) || has(type.type) || has(headingOf(type.group ?? "")));
  }

  // Sections [{ name, types }]: one per group in `groups` that has types,
  // in that order, then the types in none (name "") last. Each section's
  // types are by label.
  function grouped(types, groups, labelOf) {
    const known = groups ?? [];
    const byLabel = root.sorted(types, labelOf);
    const sections = known.map(name => ({
          "name": name,
          "types": byLabel.filter(type => type.group === name)
        }));
    sections.push({
      "name": "",
      "types": byLabel.filter(type => !known.includes(type.group))
    });
    return sections.filter(section => section.types.length > 0);
  }

  // `types` as a library shows them: grouped, or one unnamed section by
  // label
  function sections(types, groups, labelOf, byGroup) {
    if (byGroup)
      return root.grouped(types, groups, labelOf);
    const all = root.sorted(types, labelOf);
    return all.length > 0 ? [
      {
        "name": "",
        "types": all
      }
    ] : [];
  }
}
