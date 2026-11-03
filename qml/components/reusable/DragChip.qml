pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A pill with an icon and a name that can be carried: a bar widget or a
// module type in the editors. With a `payload`, pressing and moving it
// starts a drag on `dragLayer`; a click without moving is `clicked`.
// Children go after the name.
Rectangle {
  id: root

  property string icon
  property string label
  property bool selected: false
  // Tighter, for narrow places
  property bool compact: false
  property alias dragLayer: area.dragLayer
  // What dragging it carries; null: it can't be dragged
  property alias payload: area.payload
  default property alias trailing: row.data

  readonly property bool hovered: area.containsMouse
  // The colour of text and icons after the name
  readonly property color ink: root.selected ? Theme.background : Theme.foreground

  signal clicked

  implicitWidth: row.implicitWidth + (root.compact ? Widget.padding : Widget.padding * 2)
  implicitHeight: Widget.height + Widget.padding / 2
  radius: Widget.radius
  color: root.selected ? Theme.accent : (root.hovered ? Theme.backgroundHighlight : Theme.background)
  border.color: root.selected || root.hovered ? Theme.accent : Theme.border
  border.width: 1

  ColorGlide on color {}

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.leftMargin: root.compact ? Widget.padding / 2 : Widget.padding
    anchors.rightMargin: root.compact ? Widget.padding / 2 : Widget.padding
    spacing: root.compact ? Widget.spacing / 2 : Widget.spacing

    StyledIcon {
      text: root.icon
      textColor: root.selected ? Theme.background : Theme.accent
      Layout.preferredWidth: Appearance.fontSize * 1.3
    }

    StyledText {
      text: root.label
      textColor: root.ink
      font.bold: root.selected
      elide: Text.ElideRight
      Layout.fillWidth: true
    }
  }

  DragArea {
    id: area
    anchors.fill: parent
    dragEnabled: area.payload !== null
    onTapped: root.clicked()
  }
}
