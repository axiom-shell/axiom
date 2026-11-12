pragma Singleton
import QtQuick

// What the footprint ledger (docs/dev/backend/footprint.md) shows of the
// settings: which fields write outside axiom's folders (`x-footprint`), the
// value that turns one off, and the ledger's rows grouped and named for the
// General card. No file access, processes or services.
QtObject {
  id: root

  // Whether a field changes things outside axiom's folders: its `x-footprint`
  // (true, or a condition as `x-showIf` takes, held against `valueOf`), or
  // its section's `x-footprint: true`, or an `x-hookup`
  function persistent(field, section, valueOf) {
    if (!field)
      return false;
    if (field["x-hookup"])
      return true;
    if (section && section["x-footprint"] === true)
      return true;
    const own = field["x-footprint"];
    if (own === undefined || own === null || own === false)
      return false;
    if (own === true)
      return true;
    return root._holds(own, valueOf);
  }

  // `{ key: value | [values] }` held against valueOf(key), every key
  function _holds(condition, valueOf) {
    return Object.keys(condition).every(key => {
      const want = condition[key];
      const value = valueOf ? valueOf(key) : undefined;
      if (want !== null && typeof want === "object" && typeof want.length === "number")
        return Array.prototype.includes.call(want, value);
      return value === want;
    });
  }

  // The value that turns a setting off: false for a boolean, else its
  // schema default
  function offValue(field) {
    if (field?.type === "boolean")
      return false;
    return field?.default;
  }

  // Rows by owner, in first-seen order, the compositor's own lines (owner
  // "") last: [{ owner, rows }] (the card names each)
  function groups(rows) {
    const order = [];
    const by = {};
    for (const row of rows ?? []) {
      const owner = row.owner ?? "";
      if (!by[owner]) {
        by[owner] = [];
        if (owner !== "")
          order.push(owner);
      }
      by[owner].push(row);
    }
    const out = order.map(owner => ({
          "owner": owner,
          "rows": by[owner]
        }));
    if (by[""])
      out.push({
        "owner": "",
        "rows": by[""]
      });
    return out;
  }

  // A row's name: a shortened path (home as ~, the tail of a long one), or
  // `gsettings <schema> <key>`, `fcitx5 <uri>`
  function label(row, home) {
    const target = row.target ?? "";
    const suffix = row.key ? " (" + row.key.replace(/^Default Applications\//, "") + ")" : "";
    if (row.kind === "gsetting")
      return "gsettings " + target;
    if (row.kind === "fcitx-config" || row.kind === "fcitx-group")
      return "fcitx5 " + target.replace(/^fcitx:\/\//, "");
    if (row.kind === "rebuild")
      return target + " cache";
    let path = target;
    if (home && path.startsWith(home + "/"))
      path = "~" + path.slice(home.length);
    const parts = path.split("/");
    if (parts.length > 4)
      path = parts[0] + "/…/" + parts.slice(-3).join("/");
    return path + suffix;
  }
}
