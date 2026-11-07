pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A DragLayer inside a form or card (SchemaOrderedChips' chips, the bind
// editor's rows, an OSD's systems): it takes no room in its layout (only
// the coordinate space, `z` above its siblings) and draws the carried
// payload's `label` in an accent pill by the pointer. `draggingKind` is
// the payload's `kind`, as the editors' layers name it.
DragLayer {
  id: root

  readonly property string draggingKind: root.dragging?.kind ?? ""

  Layout.fillWidth: true
  Layout.preferredHeight: 0
  z: 10
  onMoved: point => ghost.at = point

  StyledContainer {
    id: ghost
    property point at: Qt.point(0, 0)
    visible: root.dragging !== null
    x: ghost.at.x + Widget.spacing
    y: ghost.at.y - height / 2
    implicitWidth: ghostLabel.implicitWidth + Widget.padding * 2
    implicitHeight: Widget.height
    backgroundColor: Theme.accent

    StyledText {
      id: ghostLabel
      anchors.centerIn: parent
      text: root.dragging?.label ?? ""
      textColor: Theme.background
    }
  }
}
