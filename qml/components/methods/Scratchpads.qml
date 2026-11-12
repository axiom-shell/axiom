pragma Singleton
import QtQuick

// The workspace switcher's scratchpad cells (special workspaces) as data:
// which names are configured, which cells show, and what each one shows. No
// file access, processes or services.
QtObject {
  id: root

  // The names configured: `listed` (Workspaces.scratchpads entries) first,
  // then the argument of each toggleSpecial bind in `binds`, trimmed, not
  // empty, without duplicates
  function configuredNames(listed, binds) {
    const names = [];
    const add = text => {
      const name = String(text ?? "").trim();
      if (name !== "" && !names.includes(name))
        names.push(name);
    };
    (listed ?? []).forEach(entry => add(entry?.name));
    (binds ?? []).filter(bind => bind?.action === "toggleSpecial").forEach(bind => add(bind.argument));
    return names;
  }

  // The specials (contract.md › Shapes) to show for `mode` ("off",
  // "occupied" or "all"): occupied are those with windows or open; all adds
  // each `configured` name no special has, as an empty closed one. The
  // configured names come first in their order, the rest by name. The
  // unnamed one (name "") shows only while it has windows or is open, never
  // as `all`'s padding, and comes last.
  function cells(specials, configured, mode) {
    if (mode !== "occupied" && mode !== "all")
      return [];
    let shown = (specials ?? []).filter(s => mode === "all" ? s.name !== "" || s.windowCount > 0 || s.open : s.windowCount > 0 || s.open);
    if (mode === "all") {
      const missing = (configured ?? []).filter(name => !shown.some(s => s.name === name)).map(name => ({
            "name": name,
            "id": 0,
            "open": false,
            "output": "",
            "windowCount": 0,
            "urgent": false,
            "windows": []
          }));
      shown = shown.concat(missing);
    }
    const rank = s => {
      const i = (configured ?? []).indexOf(s.name);
      return s.name === "" ? Infinity : i < 0 ? 1e9 : i;
    };
    return shown.slice().sort((a, b) => {
      const ra = rank(a);
      const rb = rank(b);
      if (ra !== rb)
        return ra < rb ? -1 : 1;
      return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
    });
  }

  // The first of `listed` with that name, or null
  function entryFor(listed, name) {
    return (listed ?? []).find(entry => String(entry?.name ?? "").trim() === name) ?? null;
  }

  // What a cell shows, as { kind, text, lead, tail } in WorkspaceCells.pick's
  // kinds. Mode "icon": the entry's icon, else the apps' icons (`hasIcons`),
  // else a star (the toggleSpecial action's icon). Mode "name": the entry's
  // label, else the name. Mode "both": the icon (the entry's, else a star)
  // as `lead` before the text (the entry's label, else the name); app icons
  // only after a divider. With `split` the label is never the app icons: the
  // cell shows it, a short divider, then the apps' icons (`tail`, true only
  // with `hasIcons`). The unnamed one (name "") has no name to show: without
  // a label its name and both modes show a star, never an empty text.
  function content(entry, name, mode, hasIcons, split) {
    const tail = split === true && hasIcons;
    const make = (kind, text, lead) => ({
          "kind": kind,
          "text": text,
          "lead": lead ?? "",
          "tail": tail
        });
    const label = entry?.text ?? "";
    if (name === "" && label === "" && mode !== "icon")
      return make("glyph", "star");
    if (mode === "name")
      return label !== "" ? make("text", label) : make("name", name);
    const icon = entry?.icon ?? "";
    if (mode === "both")
      return make(label !== "" ? "text" : "name", label !== "" ? label : name, icon !== "" ? icon : "star");
    if (icon !== "")
      return make("text", icon);
    return hasIcons && split !== true ? make("icons", "") : make("glyph", "star");
  }
}
