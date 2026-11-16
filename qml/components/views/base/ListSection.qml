pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A titled section of a tool page's list: a header (the title, a count and,
// at the end, `trailing` controls), one faint `hint` line, then its rows
// (children). `collapsible` makes the header a toggle: a click emits
// `toggled` and never writes `open`, so the page keeps its own state (and a
// binding on `open` survives); the rows hide while it is not `open`.
ColumnLayout {
  id: root

  property string title
  property int count: -1
  property string hint: ""
  property bool collapsible: false
  property bool open: true
  property alias trailing: trailingRow.data
  default property alias rows: rowColumn.data

  signal toggled

  Layout.fillWidth: true
  spacing: Widget.spacing / 2

  Item {
    id: header

    // Marks a list header, which the rows' Up/Down walk steps over
    readonly property bool _listHeader: true
    Layout.fillWidth: true
    Layout.preferredHeight: Widget.height

    StateLayer {
      visible: root.collapsible
      hovered: headerArea.containsMouse
      pressed: headerArea.pressed
    }

    MouseArea {
      id: headerArea
      anchors.fill: parent
      enabled: root.collapsible
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggled()
    }

    RowLayout {
      anchors.fill: parent
      spacing: Widget.spacing

      FoldChevron {
        visible: root.collapsible
        open: root.open
        hot: headerArea.containsMouse
      }

      StyledLabel {
        text: root.title
        role: "label"
        tone: "muted"
        overflow: "line"
        Layout.fillWidth: true
        // Elides when short of room, but never pushes the count away
        Layout.maximumWidth: Math.ceil(implicitWidth)
      }

      StyledText {
        visible: root.count >= 0
        role: "caption"
        tone: "muted"
        text: String(root.count)
      }

      Item {
        Layout.fillWidth: true
      }

      RowLayout {
        id: trailingRow
        visible: children.length > 0
        spacing: Widget.spacing
      }
    }
  }

  StyledText {
    visible: root.hint !== ""
    Layout.fillWidth: true
    role: "caption"
    tone: "faint"
    text: root.hint
  }

  ColumnLayout {
    id: rowColumn
    visible: root.open
    Layout.fillWidth: true
    spacing: Widget.spacing / 2
  }
}
