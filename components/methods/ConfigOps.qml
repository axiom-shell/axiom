pragma Singleton
import QtQuick

// The config's path ops (axiom's `config.set`, `config.changed`'s changes,
// backend/internal/config/ops.go): the ops between two configs, and a
// config with ops applied. Paths here are keys only (a list is set whole).
// No file access, processes or services.
QtObject {
  id: root

  // The ops that turn `before` into `after`: { op: "set", path, value }
  // for each value that differs (a list whole), { op: "delete", path } for
  // each key gone, objects followed down to what changed. As Go's
  // config.Diff makes them
  function diff(before, after, path = []) {
    const isObject = value => value !== null && typeof value === "object" && !Array.isArray(value);
    const ops = Object.keys(before).filter(key => !(key in after)).map(key => ({
          "op": "delete",
          "path": path.concat(key)
        }));
    for (const key of Object.keys(after)) {
      if (isObject(before[key]) && isObject(after[key]))
        ops.push(...root.diff(before[key], after[key], path.concat(key)));
      else if (!(key in before) || JSON.stringify(before[key]) !== JSON.stringify(after[key]))
        ops.push({
          "op": "set",
          "path": path.concat(key),
          "value": after[key]
        });
    }
    return ops;
  }

  // `config` with `ops` applied, in order; null if one isn't a set or a
  // delete on a path of keys (an {id} selector, an order). Only the
  // objects along a path are copied: everything else stays the object it
  // was, and `config` itself is left alone
  function apply(config, ops) {
    if (ops.length === 0)
      return config;
    const out = Object.assign({}, config);
    for (const op of ops) {
      if (!["set", "delete"].includes(op.op) || op.path.length === 0 || op.path.some(key => typeof key !== "string"))
        return null;
      let cur = out;
      for (const key of op.path.slice(0, -1)) {
        const next = cur[key];
        cur[key] = next !== null && typeof next === "object" && !Array.isArray(next) ? Object.assign({}, next) : {};
        cur = cur[key];
      }
      const last = op.path[op.path.length - 1];
      if (op.op === "set")
        cur[last] = op.value;
      else
        delete cur[last];
    }
    return out;
  }

  // The ops that lay previews (dotted path → value) over a config,
  // shallower paths first so a deeper one shows through a whole section
  function previewOps(previews) {
    return Object.keys(previews).sort((a, b) => a.split(".").length - b.split(".").length).map(dotted => ({
          "op": "set",
          "path": dotted.split("."),
          "value": previews[dotted]
        }));
  }
}
