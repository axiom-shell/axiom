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
}
