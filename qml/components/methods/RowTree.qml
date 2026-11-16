pragma Singleton
import QtQuick

// The indent tree of a form's rows, from the schema's conditions alone: a
// row sits under the earlier row whose value shows it, at any depth. Used by
// SchemaPropertiesForm (`rows` in, levels for FormRow, `lead` for FieldGroup).
// No file access, processes or services.
QtObject {
  id: root

  // The row indexes a condition (relative to `base`, a path array) names
  // among the rows before `at`: [index] for each plain key that resolves to
  // an earlier row. Keys starting with `/` or `$` (config-wide and context
  // reads) and `anyOf` name nothing here
  function _named(condition, base, paths, at) {
    const found = [];
    for (const key of Object.keys(condition ?? {})) {
      if (key === "anyOf" || key.startsWith("/") || key.startsWith("$"))
        continue;
      const full = SchemaLayout.keyPath(base, key).join(".");
      const index = paths.indexOf(full);
      if (index >= 0 && index < at)
        found.push(index);
    }
    return found;
  }

  // `index` and every row above it in the tree so far, nearest first
  function _chain(index, parents) {
    const out = [];
    for (let i = index; i >= 0; i = parents[i])
      out.push(i);
    return out;
  }

  // The parent a condition gives the row at `at`: the latest earlier row a
  // plain key names; with `anyOf`, the nearest row every branch sits under
  // (the branch's own parent when they agree, else the nearest strict
  // ancestor all share), -1 when a branch has none. -1 for no parent
  function _parentOf(condition, base, paths, at, parents) {
    let best = Math.max(-1, ...root._named(condition, base, paths, at));
    const any = condition?.anyOf;
    if (any && typeof any.length === "number") {
      const branches = Array.prototype.map.call(any, branch => root._parentOf(branch, base, paths, at, parents));
      let shared = -1;
      if (branches.every(b => b >= 0)) {
        if (branches.every(b => b === branches[0])) {
          shared = branches[0];
        } else {
          const chains = branches.map(b => root._chain(parents[b], parents));
          shared = chains[0].find(i => chains.every(chain => chain.includes(i))) ?? -1;
        }
      }
      best = Math.max(best, shared);
    }
    return best;
  }

  // `rows`: SchemaPropertiesForm.rows ({ path, schema, groupShowIf }). Gives
  // { lead, levels, parents }: `parents[i]` the row i sits under (-1 for
  // none), `levels[i]` its depth (0 for none, else its parent's + 1), and
  // `lead` whether the first row leads the rest: two or more rows, the first
  // unconditional, every other row under it somewhere up the chain
  function plan(rows) {
    const list = rows ?? [];
    const paths = list.map(row => row.path.join("."));
    const parents = [];
    const levels = [];
    for (let i = 0; i < list.length; i++) {
      const row = list[i];
      let parent = root._parentOf(row.schema?.["x-showIf"], row.path.slice(0, -1), paths, i, parents);
      for (const entry of row.groupShowIf ?? [])
        parent = Math.max(parent, root._parentOf(entry.condition, entry.path, paths, i, parents));
      parents.push(parent);
      levels.push(parent < 0 ? 0 : levels[parent] + 1);
    }
    let lead = list.length >= 2 && !list[0].schema?.["x-showIf"] && !list[0].schema?.["x-hintedIf"] && (list[0].groupShowIf ?? []).length === 0;
    for (let i = 1; lead && i < list.length; i++) {
      let top = i;
      while (parents[top] >= 0)
        top = parents[top];
      lead = top === 0;
    }
    return {
      "lead": lead,
      "levels": levels,
      "parents": parents
    };
  }
}
