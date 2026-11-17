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
//
// `joins` (a hand-built field of several rows: a TriggerField, ConditionRows)
// makes the column a row of the FormColumn it sits in: it has a `bodyHeight`
// while it draws a row, and only takes part in the outer one's `firstRow`
// when it is the outer's top, so its own top row draws no divider only then.
// Outside a FormColumn it has no top to claim: its `firstRow` is null, so a
// joined field in a plain column draws its divider.
ColumnLayout {
  id: root

  property bool joins: false
  // The top row among its own children, whatever the column sits in
  readonly property var topRow: {
    const index = FormRows.first(root.children);
    return index < 0 ? null : root.children[index];
  }
  readonly property Item firstRow: {
    if (!root.joins)
      return root.topRow;
    const outerColumn = root.parent as FormColumn;
    if (!outerColumn)
      return null;
    const outer = outerColumn.firstRow;
    return outer !== undefined && outer !== root ? null : root.topRow;
  }
  // As a row of an outer column (undefined, no row, unless it `joins`)
  readonly property var bodyHeight: root.joins ? root.topRow?.bodyHeight ?? 0 : undefined

  spacing: 0
}
