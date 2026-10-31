pragma Singleton
import QtQuick

// Windows in the order they were used (the window switcher): the
// compositor's windows by focusRank, stepping through them, and where each
// one's tile goes.
QtObject {
  id: root

  // The windows `keep` accepts, most recently focused first. `activeId`
  // (the focused window, known from events before the window list catches
  // up) goes first whatever its focusRank says, so a quick second switch
  // still swaps back.
  function mru(windows, keep, activeId) {
    const kept = (windows ?? []).filter(win => keep(win));
    kept.sort((a, b) => (a.focusRank ?? Infinity) - (b.focusRank ?? Infinity));
    const active = kept.findIndex(win => win.id === activeId);
    if (active > 0)
      kept.unshift(kept.splice(active, 1)[0]);
    return kept;
  }

  // `index` moved `step` places, wrapping around `count`
  function stepIndex(index, step, count) {
    if (count <= 0)
      return 0;
    return ((index + step) % count + count) % count;
  }

  // Where `count` tiles go in `order` (leftToRight | rightToLeft |
  // topToBottom | bottomToTop), `perLine` to a line before the next line
  // starts (below a row, right of a column): { columns, rows, cells:
  // [{ column, row }] } by index. A line short of tiles is the last one,
  // filled from its start.
  function tileGrid(count, perLine, order) {
    const vertical = order === "topToBottom" || order === "bottomToTop";
    const reversed = order === "rightToLeft" || order === "bottomToTop";
    const along = Math.max(1, Math.min(count, perLine));
    const lines = count > 0 ? Math.ceil(count / along) : 0;
    const cells = [];
    for (let i = 0; i < count; i++) {
      const step = reversed ? along - 1 - i % along : i % along;
      const line = Math.floor(i / along);
      cells.push(vertical ? {
        "column": line,
        "row": step
      } : {
        "column": step,
        "row": line
      });
    }
    return {
      "columns": vertical ? lines : (count > 0 ? along : 0),
      "rows": vertical ? (count > 0 ? along : 0) : lines,
      "cells": cells
    };
  }
}
