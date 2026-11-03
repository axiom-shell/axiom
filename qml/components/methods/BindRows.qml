pragma Singleton
import QtQuick

// The Keybinds reference's rows (KeybindManager.keybindings): numbered
// runs and direction sets folded into one row each, and a section's rows
// grouped by their modifiers. A row is { label, combos: [{ mods, keys,
// cluster? }], axiom, user, ids, action, overrides }.
QtObject {
  id: root

  // Folded rows' own fields: sources ORed, ids joined, the first action and
  // override
  function _merged(rows, label, combos) {
    return {
      "label": label,
      "combos": combos,
      "axiom": rows.some(r => r.axiom),
      "user": rows.some(r => r.user),
      "ids": [].concat(...rows.map(r => r.ids ?? [])),
      "action": rows.map(r => r.action ?? "").find(a => a !== "") ?? "",
      "overrides": rows.map(r => r.overrides ?? "").find(o => o !== "") ?? ""
    };
  }

  // Rows in `rows` that `runOf` puts in a run (a key, or "") with more than
  // one member are replaced, where the run's first member was, by
  // `fold(members)`
  function _fold(rows, runOf, fold) {
    const runs = {};
    const keys = rows.map(row => runOf(row));
    keys.forEach((key, i) => {
      if (key !== "")
        (runs[key] = runs[key] ?? []).push(rows[i]);
    });
    const result = [];
    const placed = {};
    rows.forEach((row, i) => {
      const key = keys[i];
      if (key === "" || runs[key].length < 2) {
        result.push(row);
        return;
      }
      if (placed[key])
        return;
      placed[key] = true;
      result.push(fold(runs[key]));
    });
    return result;
  }

  /**
   * Rows like "Go to workspace 1" … "Go to workspace 5", each bound to its
   * own number key with the same modifiers, become one "Go to workspace"
   * row with the key "1–5" (or "1 2 4" when the numbers have gaps).
   * Workspace 10 is usually on the 0 key.
   */
  function collapseNumbered(rows) {
    const numberOf = row => {
      const match = String(row.label ?? "").match(/^(.*\S)\s+(\d+)$/);
      const combo = row.combos[0];
      if (!match || row.combos.length !== 1 || combo.keys.length !== 1 || (combo.keys[0] !== match[2] && !(match[2] === "10" && combo.keys[0] === "0")))
        return null;
      return {
        "label": match[1],
        "number": parseInt(match[2])
      };
    };
    return root._fold(rows ?? [], row => {
      const n = numberOf(row);
      return n ? `${n.label}\u0000${row.combos[0].mods.join("+")}` : "";
    }, members => {
      const numbers = members.map(r => numberOf(r).number).sort((a, b) => a - b);
      const contiguous = numbers.every((n, i) => i === 0 || n === numbers[i - 1] + 1);
      return root._merged(members, numberOf(members[0]).label, [
        {
          "mods": members[0].combos[0].mods,
          "keys": contiguous ? [`${numbers[0]}–${numbers[numbers.length - 1]}`] : numbers.map(String)
        }
      ]);
    });
  }

  // Directions in the order a folded row shows them (as H J K L)
  readonly property var directions: ["left", "down", "up", "right"]

  /**
   * Rows like "Focus left" … "Focus right" with the same modifiers become
   * one "Focus" row. Each combo keeps its alternatives as `cluster`: per
   * alternative, the keys in `directions` order ([["H", "J", "K", "L"],
   * ["←", "↓", "↑", "→"]]), and `keys` all of them (for the search).
   */
  function collapseDirections(rows) {
    const directionOf = row => {
      const match = String(row.label ?? "").match(/^(.*\S)\s+(left|right|up|down)$/i);
      return match ? {
        "label": match[1],
        "direction": match[2].toLowerCase()
      } : null;
    };
    // Members share the label, and per combo the modifiers and the count of
    // alternatives
    const shape = row => row.combos.map(combo => combo.mods.join("+") + "#" + combo.keys.length).join("|");
    return root._fold(rows ?? [], row => {
      const d = directionOf(row);
      return d && row.combos.length > 0 ? `${d.label.toLowerCase()}\u0000${shape(row)}` : "";
    }, members => {
      const byDirection = {};
      for (const member of members)
        byDirection[directionOf(member).direction] = byDirection[directionOf(member).direction] ?? member;
      const ordered = root.directions.filter(d => byDirection[d]).map(d => byDirection[d]);
      const combos = members[0].combos.map((combo, c) => {
        const cluster = combo.keys.map((_, alt) => ordered.map(row => row.combos[c].keys[alt]));
        return {
          "mods": combo.mods,
          "keys": [].concat(...cluster),
          "cluster": cluster
        };
      });
      return root._merged(ordered, directionOf(members[0]).label, combos);
    });
  }

  // Modifier sets in reading order: fewer first, then by KeyNames.modifiers
  function _modsOrder(mods) {
    return mods.length * 100 + mods.reduce((sum, mod) => sum + Math.pow(2, Math.max(0, KeyNames.modifiers.indexOf(mod))), 0);
  }

  /**
   * A section's rows grouped by their first combo's modifiers:
   * [{ mods, rows }], fewer modifiers first (SUPER before SUPER + SHIFT),
   * rows with none last. Rows keep their order in a group.
   */
  function byModifiers(rows) {
    const groups = {};
    const order = [];
    for (const row of rows ?? []) {
      const mods = row.combos?.[0]?.mods ?? [];
      const key = mods.join("+");
      if (!groups[key]) {
        groups[key] = {
          "mods": mods,
          "rows": []
        };
        order.push(key);
      }
      groups[key].rows.push(row);
    }
    const rank = group => group.mods.length === 0 ? Infinity : root._modsOrder(group.mods);
    return order.map(key => groups[key]).sort((a, b) => rank(a) - rank(b));
  }
}
