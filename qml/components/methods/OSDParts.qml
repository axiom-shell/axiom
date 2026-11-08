pragma Singleton
import QtQuick

// The OSD's parts (the bars, the status icons, a card; surfaces/osd):
// the bars' keys, which tiles the row shows, the parts' order
// out from the edge, their shared deadlines and which close together
// (docs/dev/features/osd.md › Engine).
QtObject {
  id: root

  // The OSD's parts, out from the edge in this order: the bars, the
  // status icons, the card
  readonly property var parts: ["level", "status", "card"]

  // Whether a system's `x-barNames` (`spec`) says it is one bar
  // ({ bar: its key }, Brightness's) rather than a list's entries
  function oneBar(spec) {
    return typeof spec?.bar === "string";
  }

  // A bar's key in its system's `exposes`, by its `x-barNames` (`spec`):
  // a one-bar system's its `bar`; an entry of its `from` list (`entry`)
  // its kind (its `by` field), else what `keys` names for that kind
  // (Audio's microphone: micLevel), and for a kind it `repeats`
  // "<kind>:<the entry's id>" (an App bar: app:<id>)
  function barKey(spec, entry) {
    if (root.oneBar(spec))
      return spec.bar;
    const kind = String(entry?.[spec?.by] ?? "");
    if ((spec?.repeats ?? []).includes(kind))
      return kind + ":" + entry.id;
    return spec?.keys?.[kind] ?? kind;
  }

  // The tiles the row shows, in the OSD's order: of `types` (its tile
  // keys), by `mode` ("notable" | "all" | "changed") over `tiles` (by
  // key, OSDEngine.tileOf's), `kept` (the change, and every one shown
  // since the icons came out: one that turned ordinary stays until they
  // go) always among them. A hidden tile shows only as it changes.
  function rowTypes(types, tiles, mode, kept) {
    return types.filter(type => {
      if ((kept ?? []).includes(type))
        return true;
      const t = tiles[type];
      if (!t || t.hidden)
        return false;
      return mode === "all" || (mode === "notable" && t.notable);
    });
  }

  // The parts' order out from the edge once `incoming` opens: `order` the
  // ones shown. In `parts`' order: the bars by the edge, the icons past
  // them, or with `iconsInside` (an OSD's `iconsPlace` "inside") the icons
  // by the edge; the card always last. `atEnd`
  // (the pointer on the OSD, holding still): a box part goes after the
  // one out, so nothing under the pointer moves; what that left out of
  // order stays so
  function partOrder(order, incoming, atEnd, iconsInside) {
    if (order.includes(incoming))
      return order.slice();
    const box = order.filter(part => part !== "card");
    const card = order.includes("card") ? ["card"] : [];
    if (incoming === "card")
      return box.concat(["card"]);
    if (atEnd)
      return box.concat([incoming], card);
    const ranked = iconsInside === true ? ["status", "level", "card"] : root.parts;
    const rank = part => ranked.indexOf(part);
    const at = box.findIndex(part => rank(part) > rank(incoming));
    return at < 0 ? box.concat([incoming], card) : box.slice(0, at).concat([incoming], box.slice(at), card);
  }

  // The parts' shared time, from `deadlines` (by part; 0 or missing: not
  // open): the bars and the status icons open take the later of theirs,
  // so they close together; the card keeps its own, neither holding nor
  // held (it says what happened once: they fold back without it)
  function sharedDeadlines(deadlines) {
    const out = Object.assign({}, deadlines ?? {});
    const shared = Object.keys(out).filter(part => part !== "card" && out[part] > 0);
    const latest = Math.max(0, ...shared.map(part => out[part]));
    shared.forEach(part => out[part] = latest);
    return out;
  }

  // Which parts close at `now` (ms), from `deadlines` (by part; 0 or
  // missing: not open): those due, each held for any due within `grace`
  // after it so they close together, not in steps. { due: [parts], next:
  // when to look again (0: nothing pending) }
  function partsDue(deadlines, now, grace) {
    const open = Object.keys(deadlines ?? {}).filter(part => deadlines[part] > 0).sort((a, b) => deadlines[a] - deadlines[b]);
    let due = [];
    let next = 0;
    let i = 0;
    while (i < open.length) {
      const first = deadlines[open[i]];
      let j = i;
      while (j + 1 < open.length && deadlines[open[j + 1]] - first <= grace)
        j++;
      const at = deadlines[open[j]];
      const group = open.slice(i, j + 1);
      if (at <= now)
        due = due.concat(group);
      else if (next === 0 || at < next)
        next = at;
      i = j + 1;
    }
    return {
      "due": due,
      "next": next
    };
  }
}
