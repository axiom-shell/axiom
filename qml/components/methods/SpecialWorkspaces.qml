pragma Singleton
import QtQuick

// Special workspaces as data: what makes an id valid, which ones exist (the
// configured entries, the live ones, the ids settings refer to), why one
// can't be deleted, and the cells the bar's switcher and the overview's
// column show with what each shows. No file access, processes or services.
QtObject {
  id: root

  // The longest id
  readonly property int maxIdLength: 32

  // Whether `id` is a special workspace id: ItemId's pattern (starts with a
  // letter or digit, then letters, digits, ".", "_" or "-"), at most 32
  // characters, case-sensitive, and not "special" (Hyprland's bare special
  // workspace is `special:special`, so that name would mean the unnamed one).
  // "" is not an id: the unnamed special workspace has none.
  function validId(id) {
    if (typeof id !== "string" || id.length > root.maxIdLength || id === "special")
      return false;
    return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(id);
  }

  // The ids the config refers to, from the fields `sites` lists
  // (SchemaRefs.sites): [{ id, usedBy, name }] for each item of `config`
  // that a site's `when` matches and whose field holds a non-empty string.
  // `usedBy` is the source text of the reason, `name` what it names (the
  // item's bind key, or the title of its hot corner: the field's
  // `x-enumLabels` entry, `translate` then true, as source text).
  function references(config, sites) {
    const out = [];
    (sites ?? []).forEach(site => {
      let items = config;
      for (const key of site.path)
        items = items?.[key];
      if (!Array.isArray(items))
        return;
      items.forEach(item => {
        const id = item?.[site.key];
        if (typeof id !== "string" || id === "" || !SchemaLayout.showIfHolds(site.when, key => item[key]))
          return;
        const raw = String(item[site.name] ?? "");
        const label = site.nameLabels?.[raw];
        out.push({
          "id": id,
          "usedBy": site.usedBy,
          "name": label ?? raw,
          "translate": label !== undefined
        });
      });
    });
    return out;
  }

  // Every special workspace that exists as a row, `""` (the unnamed one)
  // never among them: the configured `entries` ([{ id, icon, text }]) in
  // their order, then the ids settings refer to (`refs`, as references()
  // gives them) in the order met, then the live `specials` (contract.md ›
  // Shapes) by id. A row: { id, label, icon, configured, special,
  // windowCount, refs, editable }: `label` the entry's text, `icon` its
  // icon, `configured` whether it has an entry, `special` the live special
  // or null, `refs` the references to it, `editable` whether its id is
  // valid (an invalid live or referenced id shows as it is and is left alone).
  function list(entries, specials, refs) {
    const ids = [];
    const add = id => {
      if (typeof id === "string" && id !== "" && !ids.includes(id))
        ids.push(id);
    };
    (entries ?? []).forEach(entry => add(entry?.id));
    (refs ?? []).forEach(ref => add(ref.id));
    (specials ?? []).map(special => special.name).sort().forEach(add);
    return ids.map(id => {
      const entry = (entries ?? []).find(e => e?.id === id) ?? null;
      const special = (specials ?? []).find(s => s.name === id) ?? null;
      return {
        "id": id,
        "label": entry?.text ?? "",
        "icon": entry?.icon ?? "",
        "configured": entry !== null,
        "special": special,
        "windowCount": special?.windowCount ?? 0,
        "refs": (refs ?? []).filter(ref => ref.id === id),
        "editable": root.validId(id)
      };
    });
  }

  // Why a row can't be deleted: [{ kind: "windows", count }] while it has
  // windows, then [{ kind: "ref", usedBy, name }] for each reference
  function blockers(row) {
    const out = [];
    if ((row?.windowCount ?? 0) > 0)
      out.push({
        "kind": "windows",
        "count": row.windowCount
      });
    (row?.refs ?? []).forEach(ref => out.push({
        "kind": "ref",
        "usedBy": ref.usedBy,
        "name": ref.name,
        "translate": ref.translate === true
      }));
    return out;
  }

  // Whether a row can be deleted: it has an entry and nothing blocks it
  function deletable(row) {
    return row?.configured === true && root.blockers(row).length === 0;
  }

  // The specials (contract.md › Shapes) to show as cells for `mode` ("off",
  // "occupied" or "all"), from `list` (list()'s rows), as the shape of
  // `specials` (name is the id): occupied are those with windows or open;
  // all adds every row of the list, as an empty closed one where no special
  // is live. The list's order, then the unnamed one (name ""), which shows
  // only while it has windows or is open, never as `all`'s padding.
  function cells(list, specials, mode) {
    if (mode !== "occupied" && mode !== "all")
      return [];
    const live = id => (specials ?? []).find(s => s.name === id) ?? null;
    const out = [];
    (list ?? []).forEach(row => {
      const special = live(row.id);
      if (special !== null && (mode === "all" || special.windowCount > 0 || special.open))
        out.push(special);
      else if (special === null && mode === "all")
        out.push({
          "name": row.id,
          "id": 0,
          "open": false,
          "output": "",
          "windowCount": 0,
          "urgent": false,
          "windows": []
        });
    });
    const unnamed = live("");
    if (unnamed && (unnamed.windowCount > 0 || unnamed.open))
      out.push(unnamed);
    return out;
  }

  // The names of cells as one string, so a Repeater keyed on it is rebuilt
  // only when the set changes (each name led by a newline: the unnamed one,
  // "", alone still makes a key), and back
  function keyOf(names) {
    return (names ?? []).map(name => "\n" + name).join("");
  }

  function namesOf(key) {
    return key === "" ? [] : key.slice(1).split("\n");
  }

  // The entry (of the Workspaces.specialWorkspaces list) for special
  // workspace `id`, or null (always for the unnamed one: "" is no id)
  function entryFor(entries, id) {
    if (id === "")
      return null;
    return (entries ?? []).find(entry => entry?.id === id) ?? null;
  }

  // What a cell shows, as { kind, text, lead, tail } in WorkspaceCells.pick's
  // kinds. Mode "icon": the entry's icon, else the apps' icons (`hasIcons`),
  // else a star (the toggleSpecial action's icon). Mode "name": the entry's
  // label, else the id. Mode "both": the icon (the entry's, else a star)
  // as `lead` before the text (the entry's label, else the id); app icons
  // only after a divider. With `split` the label is never the app icons: the
  // cell shows it, a short divider, then the apps' icons (`tail`, true only
  // with `hasIcons`). The unnamed one (id "") has no id to show: without
  // a label its name and both modes show a star, never an empty text.
  function content(entry, id, mode, hasIcons, split) {
    const tail = split === true && hasIcons;
    const make = (kind, text, lead) => ({
          "kind": kind,
          "text": text,
          "lead": lead ?? "",
          "tail": tail
        });
    const label = entry?.text ?? "";
    if (id === "" && label === "" && mode !== "icon")
      return make("glyph", "star");
    if (mode === "name")
      return label !== "" ? make("text", label) : make("name", id);
    const icon = entry?.icon ?? "";
    if (mode === "both")
      return make(label !== "" ? "text" : "name", label !== "" ? label : id, icon !== "" ? icon : "star");
    if (icon !== "")
      return make("text", icon);
    return hasIcons && split !== true ? make("icons", "") : make("glyph", "star");
  }
}
