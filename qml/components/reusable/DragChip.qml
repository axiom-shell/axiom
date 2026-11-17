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
  property alias dragLayer: area.dragLayer
  // Selected, it's filled with the accent; off, the host draws its own tint (a live bar widget)
  property bool solid: true
  // What dragging it carries; null: it can't be dragged
  property alias payload: area.payload
  default property alias trailing: row.data

  readonly property bool hovered: area.containsMouse
  // The colour of text and icons after the name
  readonly property color ink: root.selected ? (root.solid ? Style.inkAccent.text : Style.inkAccentContainer.text) : Style.inkHighest.text

  // A right click asks for a menu (`menuRequested`, at the point in it)
  property bool hasMenu: false

  signal clicked
  signal menuRequested(real x, real y)

  implicitWidth: row.implicitWidth + (root.compact ? Widget.padding : Widget.padding * 2)
  implicitHeight: Style.chipRowHeight
  radius: Style.radius
  color: root.selected ? Style.accent : Style.surfaceHighest
  border.color: root.selected ? Style.accent : Style.borderStrong
  border.width: root.selected && !root.solid ? Style.focusWidth : Style.hairline

  ColorGlide on color {}
  ColorGlide on border.color {}

  StateLayer {
    hovered: root.hovered || root.highlighted
    pressed: area.pressed
    dragged: area.dragged
    onAccent: root.selected && root.solid
  }

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.leftMargin: root.compact ? Widget.padding / 2 : Widget.padding
    anchors.rightMargin: root.compact ? Widget.padding / 2 : Widget.padding
    spacing: root.compact ? Widget.spacing / 2 : Widget.spacing

    StyledIcon {
      visible: root.showsLabel
      text: root.icon
      textColor: root.selected ? Style.inkAccent.icon : Style.inkHighest.graphic
      Layout.preferredWidth: Style.iconSm * 1.3
    }

    StyledLabel {
      id: name

      visible: root.showsLabel
      text: root.label
      role: "label"
      overflow: "line"
      textColor: root.ink
      Layout.fillWidth: true
    }
  }

  DragArea {
    id: area
    anchors.fill: parent
    dragEnabled: area.payload !== null
    onTapped: root.clicked()
  }

  // The full name of an elided label
  TruncationTip {
    target: name
    text: root.label
    hovered: root.hovered
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
