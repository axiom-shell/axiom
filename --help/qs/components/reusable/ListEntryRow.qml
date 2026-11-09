pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// One entry of an editor's list (bars, overlay pages, edge menus): an
// icon and a name, filled with the accent while selected, then `badges`,
// the unsaved-edits dot and the row's actions (RowActions, as children).
// A tap is `clicked`; with `dragArea.dragLayer` and `payload` set, the row
// can also be carried.
StyledContainer {
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
  readonly property color ink: root.selected ? Theme.background : Theme.foreground

  signal clicked

  Layout.fillWidth: true
  Layout.preferredHeight: Widget.height + Widget.padding
  // Clear is the hover colour at no alpha, not "transparent" (black), so
  // fading out doesn't pass through grey
  backgroundColor: root.selected ? Theme.accent : Qt.alpha(Theme.backgroundHighlight, root.hovered ? 1 : 0)
  borderWidth: 0

  ColorGlide on color {
    duration: Appearance.animNormal
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
      textColor: root.selected ? Theme.background : Theme.accent
      Layout.preferredWidth: Appearance.fontSize * 1.5
    }

    StyledText {
      text: root.label
      textColor: root.ink
      font.bold: root.selected
      opacity: root.dimmed ? 0.5 : 1
      elide: Text.ElideRight
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
}
