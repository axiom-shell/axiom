pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config

// One entry of an editor's list (bars, overlay pages, edge menus): an
// icon and a name, filled with the accent container while selected, then
// `badges`, the unsaved-edits dot and the row's actions (RowActions, as
// children), which show while the row is hovered, focused or selected.
// A tap is `clicked`; with `dragArea.dragLayer` and `payload` set, the row
// can also be carried.
Rectangle {
  id: root

  property string icon
  property string label
  property bool selected: false
  // A disabled entry: its name is dimmed
  property bool dimmed: false
  // Unsaved edits
  property bool changed: false
  property alias badges: badgeRow.data
  default property alias actions: actionRow.data
  property alias dragArea: area

  // A HoverHandler, not the drag area's containsMouse, so the row stays
  // hovered while the pointer is on one of its actions
  readonly property bool hovered: hover.hovered
  // The colour of text and icons on the row
  readonly property color ink: root.selected ? Style.inkAccentContainer.text : root.dimmed ? Style.textFaint : Style.text
  // The colour of a sub-line on the row
  readonly property color inkMuted: root.selected ? Style.inkAccentContainer.muted : Style.textMuted
  // Whether the row's actions show: hovered, focused or selected, or one of
  // them focused
  readonly property bool revealed: root.hovered || root.selected || root.activeFocus || root._actionFocused

  readonly property bool _actionFocused: actionRow.children.some(child => child.activeFocus)

  signal clicked

  Layout.fillWidth: true
  Layout.preferredHeight: Widget.height + Widget.padding
  color: root.selected ? Style.accentContainer : Qt.alpha(Style.accentContainer, 0) // style-exempt: the selected fill at no alpha, so deselecting doesn't fade through black
  radius: Style.radius

  ColorGlide on color {
    duration: Appearance.animNormal
  }

  StateLayer {
    hovered: root.hovered
    dragged: area.dragged
  }

  HoverHandler {
    id: hover
  }

  DragArea {
    id: area
    anchors.fill: parent
    dragEnabled: area.dragLayer !== null
    onTapped: root.clicked()
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Widget.padding
    anchors.rightMargin: Widget.padding / 2
    spacing: Widget.spacing

    StyledIcon {
      text: root.icon
      textColor: root.selected ? Style.inkAccentContainer.icon : root.dimmed ? Style.textFaint : Style.textAccent
      Layout.preferredWidth: Style.iconSm * 1.5
    }

    StyledLabel {
      id: name

      text: root.label
      role: "label"
      overflow: "line"
      textColor: root.ink
      Layout.fillWidth: true
    }

    RowLayout {
      id: badgeRow
      spacing: Widget.spacing
    }

    UnsavedDot {
      shown: root.changed
      onAccent: root.selected
    }

    RowLayout {
      id: actionRow
      spacing: Widget.spacing
    }
  }

  // The full name of an elided label
  LazyLoader {
    active: hover.hovered && name.truncated
    StyledToolTip {
      target: name
      text: root.label
    }
  }
}
