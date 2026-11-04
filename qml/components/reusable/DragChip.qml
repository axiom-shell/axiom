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
  // Drawn as hovered, for a pointer somewhere else (the bar editor's
  // chip of the widget hovered on the bar)
  property bool highlighted: false
  // Its icon and name; off, only what's put in it shows (the bar
  // editor's live widgets)
  property bool showsLabel: true
  // What's put in it runs down, the chip as wide as it's otherwise high
  // (a side bar's live widgets); a chip showing its name stays a row
  property bool vertical: false
  readonly property bool _column: root.vertical && !root.showsLabel
  property alias dragLayer: area.dragLayer
  // What dragging it carries; null: it can't be dragged
  property alias payload: area.payload
  default property alias trailing: row.data

  readonly property bool hovered: area.containsMouse
  // The colour of text and icons after the name
  readonly property color ink: root.selected ? Theme.background : Theme.foreground

  // A right click asks for a menu (`menuRequested`, at the point in it)
  property bool hasMenu: false

  signal clicked
  signal menuRequested(real x, real y)

  readonly property real _inset: root.compact ? Widget.padding / 2 : Widget.padding
  implicitWidth: root._column ? Widget.height + Widget.padding / 2 : row.implicitWidth + root._inset * 2
  implicitHeight: root._column ? row.implicitHeight + root._inset * 2 : Widget.height + Widget.padding / 2
  radius: Widget.radius
  color: root.selected ? Theme.accent : (root.hovered || root.highlighted ? Theme.backgroundHighlight : Theme.background)
  border.color: root.selected || root.hovered || root.highlighted ? Theme.accent : Theme.border
  border.width: 1

  ColorGlide on color {}

  // One row, or one column (_column)
  GridLayout {
    id: row
    anchors.fill: parent
    anchors.leftMargin: root._column ? 0 : root._inset
    anchors.rightMargin: root._column ? 0 : root._inset
    anchors.topMargin: root._column ? root._inset : 0
    anchors.bottomMargin: root._column ? root._inset : 0
    flow: root._column ? GridLayout.TopToBottom : GridLayout.LeftToRight
    rowSpacing: root.compact ? Widget.spacing / 2 : Widget.spacing
    columnSpacing: root.compact ? Widget.spacing / 2 : Widget.spacing

    StyledIcon {
      visible: root.showsLabel
      text: root.icon
      textColor: root.selected ? Theme.background : Theme.accent
      Layout.preferredWidth: Appearance.fontSize * 1.3
    }

    StyledText {
      visible: root.showsLabel
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

  // Over the drag area, taking only the right button (a left press goes
  // through to it)
  MouseArea {
    anchors.fill: parent
    enabled: root.hasMenu
    acceptedButtons: Qt.RightButton
    onClicked: mouse => root.menuRequested(mouse.x, mouse.y)
  }
}
