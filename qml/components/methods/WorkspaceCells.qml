pragma Singleton
import QtQuick

// The Workspaces bar widget's cells as numbers: where each sits along its
// row when they differ in length (WorkspaceCellRow, ActiveCellIndicator).
// No file access, processes or services.
QtObject {
  id: root

  // A row of cells `lengths` long at rest (one per cell), `spacing` apart,
  // with cell `active` (-1: none) longer by `extra` (wide active: one
  // normal cell's length): { starts, lengths, total }, each cell's start
  // and length along the row and the row's whole length
  function layout(lengths, spacing, active, extra) {
    const starts = [];
    const shown = [];
    let along = 0;
    for (let i = 0; i < lengths.length; i++) {
      const length = lengths[i] + (i === active ? extra : 0);
      starts.push(along);
      shown.push(length);
      along += length + spacing;
    }
    return {
      "starts": starts,
      "lengths": shown,
      "total": lengths.length > 0 ? along - spacing : 0
    };
  }

  // Where cell `index` starts along a row of cells `lengths` long at rest,
  // `spacing` apart: where the active box sits on it, as only cells after
  // the active one move when it widens (an index below 0 starts at 0, one
  // past the end where a next cell would)
  function startOf(lengths, spacing, index) {
    let along = 0;
    for (let i = 0; i < Math.min(index, lengths.length); i++)
      along += lengths[i] + spacing;
    return along;
  }

  // Whether `text` is a Material Symbols name (as StyledIcon reads it:
  // drawn as that icon), not a glyph or words drawn in the text font
  function isSymbol(text) {
    return /^\s*[a-z][a-z0-9_]*(\s+[a-z][a-z0-9_]*)*\s*$/.test(text ?? "");
  }

  // The label of one's own for the workspace numbered `number` (the
  // widget's `workspaceLabels`: [{ workspace, label }]), or "" with none
  function labelFor(entries, number) {
    const entry = (entries ?? []).find(e => e.workspace === number && (e.label ?? "") !== "");
    return entry ? entry.label : "";
  }

  // A workspace's compositor `name` where it says more than its id or the
  // number its cell shows, else ""
  function nameShown(name, id, number) {
    const text = (name ?? "").trim();
    return text === "" || text === String(id) || text === String(number) ? "" : text;
  }

  // What a cell shows, highest first: the grid's arrow (`glyph`), a label
  // of one's own (`label`), app icons (`icons`, given only for a workspace
  // with windows), the compositor's name (`name`, given only with names
  // on), else its number, dot or nothing: { kind: "glyph" | "text" |
  // "icons" | "labels", text }
  function pick(glyph, label, icons, name) {
    const make = (kind, text) => ({
          "kind": kind,
          "text": text
        });
    if (glyph !== "")
      return make("glyph", glyph);
    if (label !== "")
      return make("text", label);
    if (icons.length > 0)
      return make("icons", "");
    if (name !== "")
      return make("text", name);
    return make("labels", "");
  }
}
