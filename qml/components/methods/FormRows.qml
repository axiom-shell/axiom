pragma Singleton
import QtQuick

// The rules a column of form rows shares: which row is the top one (no
// divider), whether a card ends on a shut fold, whether every row of a card
// is hidden. `rows` is a list of items (a layout's `children`, a Repeater's
// items, null where one isn't built yet); a row is told by its `bodyHeight`,
// read from `shown` and `bodyHeight`, never from `y`, `height` or `visible`
// (a row flipping with its own place kept the layout polishing forever).
// FormColumn, FoldingCard, FieldGroup and Utils.firstFormRow call it. No
// files, processes or services.
QtObject {
  id: root

  // The index of the top row: the first that draws something, shown or not
  // yet known (undefined) and not empty; -1 for none. Items that aren't rows
  // (no `bodyHeight`) are skipped
  function first(rows) {
    for (let i = 0; i < (rows?.length ?? 0); i++) {
      const row = rows[i];
      if (row && row.shown !== false && row.bodyHeight > 0)
        return i;
    }
    return -1;
  }

  // Whether a card ends on a shut fold row (`shutFold`), so that row's own
  // padding closes it: the last of `rows` not hidden (a form's `allHidden`, a
  // row's or other child's `shown`) decides. Never while `collapsed`
  function endsShut(rows, collapsed) {
    if (collapsed)
      return false;
    for (let i = (rows?.length ?? 0) - 1; i >= 0; i--) {
      const row = rows[i];
      if (!row || row.allHidden === true || row.shown === false)
        continue;
      return row.shutFold === true;
    }
    return false;
  }

  // Whether every counted row is hidden: a form (`allHidden`) or a row
  // (`bodyHeight` and `shown`) counts, anything else doesn't; false for none
  function empty(rows) {
    let counted = 0;
    for (let i = 0; i < (rows?.length ?? 0); i++) {
      const row = rows[i];
      if (!row)
        continue;
      if (row.allHidden !== undefined) {
        if (row.allHidden !== true)
          return false;
      } else if (row.bodyHeight !== undefined) {
        if (row.shown !== false)
          return false;
      } else {
        continue;
      }
      counted++;
    }
    return counted > 0;
  }
}
