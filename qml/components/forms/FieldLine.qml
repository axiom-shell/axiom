pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods

// The one layout of a schema field and its control (every Schema* control,
// the custom widgets' InspectorRow): the label line, the description and
// links, the control, and what goes under all of them. Where the control
// sits, on the label's line or under it, is FieldFit's decision (`kind`
// names the control's behaviour there), read from constant widths only: the
// field's own width (hosts fill their parent), the label's one-line width
// (FieldHeader.lineWidth) and the control's `controlLeast`. Never a
// laid-out width: a field that fed its own size back would flip. A short
// control stays on the label's line whenever it fits; the description then
// sits beside the label at any width, wrapping earlier on a narrow field,
// with the control centred on the whole box. Stacked: label,
// description, control. The control is the default child (`Layout.*` in it
// work as in a column); `body` goes under everything at full width.
Item {
  id: root

  property string label: ""
  property string description: ""
  // After the label (FieldHeader.trailing)
  property Component headerExtra: null
  // Under the description (FieldHeader.below)
  property Component headerBelow: null
  // FieldFit's kinds: "switch", "fixed", "flex", "slider", "fill", "block"
  property string kind: "block"
  // A fixed control's implicit width (the one `fit` must keep room for)
  property real controlLeast: 0
  default property alias control: holder.data
  // Whether there is a control at all (from data, never layout: a hidden
  // layout's size isn't kept)
  property bool hasControl: true
  // Whether `body` shows anything (from data)
  property bool bodyShown: false
  // Under the line, the description and the control, at full width
  property alias body: bodyColumn.data

  // FieldFit.place for this field
  readonly property var fit: FieldFit.place(root.kind, root.width, header.lineWidth, root.controlLeast, Widget.fieldTokens)
  readonly property bool inline: root.fit.inline
  readonly property real leastWidth: FieldFit.least(root.kind, header.lineWidth, root.controlLeast, Widget.fieldTokens)
  // The label's line and the notes as one head: something above the control
  readonly property bool _hasHead: header.hasContent || notes.hasContent

  Layout.fillWidth: true
  implicitWidth: grid.implicitWidth
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    width: parent.width
    columns: 2
    columnSpacing: Widget.spacing * 2
    rowSpacing: 0

    // Every cell's row, column and span come from `fit` here, so none is
    // ever stale against another

    FieldHeader {
      id: header
      label: root.label
      trailing: root.headerExtra
      Layout.row: 0
      Layout.column: 0
      Layout.columnSpan: root.fit.inline ? 1 : 2
      // At its own width beside a control that fills the rest
      Layout.fillWidth: root.kind !== "fill"
      // Centred on a control taller than it (a label alone)
      Layout.alignment: Qt.AlignVCenter
    }

    // The description and links (a FieldHeader with no label shows only
    // those): under the label, in the control's left column when inline
    FieldHeader {
      id: notes
      description: root.description
      below: root.headerBelow
      Layout.row: 1
      Layout.column: 0
      Layout.columnSpan: root.fit.inline ? 1 : 2
      Layout.fillWidth: true
      Layout.topMargin: header.hasContent && notes.hasContent ? Widget.px(2) : 0
    }

    ColumnLayout {
      id: holder
      visible: root.hasControl
      spacing: Widget.spacing / 2
      Layout.row: root.fit.inline ? 0 : 2
      Layout.column: root.fit.inline ? 1 : 0
      Layout.columnSpan: root.fit.inline ? 1 : 2
      Layout.rowSpan: root.fit.inline && notes.hasContent ? 2 : 1
      Layout.fillWidth: root.fit.fill
      Layout.preferredWidth: root.fit.controlWidth
      Layout.alignment: root.fit.inline ? Qt.AlignVCenter : Qt.AlignTop
      Layout.topMargin: !root.fit.inline && root._hasHead ? Widget.spacing : 0
    }

    ColumnLayout {
      id: bodyColumn
      spacing: Widget.spacing
      visible: root.bodyShown
      Layout.row: 3
      Layout.column: 0
      Layout.columnSpan: 2
      Layout.fillWidth: true
      Layout.topMargin: Widget.spacing
    }
  }
}
