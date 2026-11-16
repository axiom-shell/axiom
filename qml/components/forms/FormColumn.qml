pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.components.methods

// A column of FormRows, abutting (spacing 0), that publishes `firstRow`, the
// top row drawn (FormRows.first over its children), which a FormRow in it
// reads for `first`: no divider on the top row, and it moves to the next row
// when the top one hides. Read from the rows' `shown` and `bodyHeight`, never
// from `y`, `height` or `visible` (a row flipping between its place and its
// height kept the layout polishing forever). FoldingColumn's inner column is
// one, so a FieldGroup's and FoldingCard's rows get it too.
ColumnLayout {
  id: root

  readonly property Item firstRow: {
    const index = FormRows.first(root.children);
    return index < 0 ? null : root.children[index];
  }

  spacing: 0
}
