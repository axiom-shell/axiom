pragma Singleton
import QtQuick

// The Keybinds editor's list: axiom's binds grouped by section, and in a
// section, numbered runs (SUPER + 1 … SUPER + 0 going to workspaces 1–10)
// folded into one row.
QtObject {
  id: root

  // The run a bind belongs to, or "": a bind on a number key whose action
  // takes a workspace number, that number (10 on the 0 key), with no label
  // of its own. Binds in one run share the action, the modifiers and the
  // flags. `table` is the bind actions' (KeybindManager.actionTable).
  function runKey(table, bind) {
    if (BindActions.argumentKind(table, bind?.action) !== "workspace" || String(bind.description ?? "").trim() !== "")
      return "";
    const parts = KeyNames.split(bind.key);
    const argument = String(bind.argument ?? "").trim();
    if (!/^[0-9]$/.test(parts.key) || !(parts.key === argument || (parts.key === "0" && argument === "10")))
      return "";
    const flags = (table?.flagNames ?? []).concat(["paused"]).map(flag => bind[flag] === true ? "1" : "0").join("");
    return [bind.action, parts.mods.slice().sort().join("+"), flags].join("|");
  }

  /**
   * The shown binds as sections of rows: [{ key, indices, rows: [[index]] }].
   * `shown` are bind indices in the order they show, `sections` each
   * bind's section (by index) and `order` the sections that go first, in
   * order (the rest follow by name). A row holds one bind, or a run's
   * binds by number, where its first shown bind is.
   */
  function groups(table, binds, shown, sections, order) {
    const bySection = {};
    for (const index of shown ?? []) {
      const section = sections[index] ?? "";
      (bySection[section] = bySection[section] ?? []).push(index);
    }
    const known = (order ?? []).filter(section => bySection[section]);
    const others = Object.keys(bySection).filter(section => !known.includes(section)).sort();
    return known.concat(others).map(section => ({
          "key": section,
          "indices": bySection[section],
          "rows": root._rows(table, binds, bySection[section])
        }));
  }

  function _rows(table, binds, indices) {
    const keys = indices.map(index => root.runKey(table, binds[index]));
    const counts = {};
    for (const key of keys)
      if (key !== "")
        counts[key] = (counts[key] ?? 0) + 1;
    const rows = [];
    const runAt = {};
    indices.forEach((index, i) => {
      const key = keys[i];
      if (key === "" || counts[key] < 2) {
        rows.push([index]);
        return;
      }
      if (runAt[key] === undefined) {
        runAt[key] = rows.length;
        rows.push([]);
      }
      rows[runAt[key]].push(index);
    });
    const number = index => parseInt(binds[index].argument);
    for (const row of rows)
      if (row.length > 1)
        row.sort((a, b) => number(a) - number(b));
    return rows;
  }

  // A run's numbers as a short text: "1–10", or "1 2 4" with gaps
  function runNumbers(binds, indices) {
    const numbers = indices.map(index => parseInt(binds[index].argument)).sort((a, b) => a - b);
    const contiguous = numbers.every((n, i) => i === 0 || n === numbers[i - 1] + 1);
    return contiguous && numbers.length > 2 ? `${numbers[0]}–${numbers[numbers.length - 1]}` : numbers.join(" ");
  }

  // A run's keys as a short text: "1–0", or "1 2 4"
  function runKeys(binds, indices) {
    const keys = indices.map(index => KeyNames.split(binds[index].key).key);
    const numbers = indices.map(index => parseInt(binds[index].argument));
    const contiguous = numbers.every((n, i) => i === 0 || n === numbers[i - 1] + 1);
    return contiguous && keys.length > 2 ? `${keys[0]}–${keys[keys.length - 1]}` : keys.join(" ");
  }
}
