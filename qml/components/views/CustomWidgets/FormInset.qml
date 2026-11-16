pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// Room for the hover of a flat form's rows (the custom widgets editor's tabs
// and inspector): a FormRow's tint reaches Style.rowBleed past its sides and
// rounds its ends there, as on the settings page, whose cards pad their rows.
// A pane's groups are flat, so a form straight in a scroll view would have the
// tint cut square at its edge: its children sit in a column inset by that
// much on both sides. Children set their own Layout.fillWidth.
Item {
  id: root

  default property alias content: column.data

  Layout.fillWidth: true
  implicitHeight: column.implicitHeight

  ColumnLayout {
    id: column
    x: Style.rowBleed
    width: root.width - Style.rowBleed * 2
    spacing: 0
  }
}
