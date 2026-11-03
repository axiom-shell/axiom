pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A trash can that appears while an editor carries something it can
// delete: dropped on it, the drag layer removes what's carried
// (`targetKind` "trash"; the layer's `accepts` decides what it takes and
// its `dropped` does the removing). Above any target it overlaps
// (`dropPriority`). Used by the layouts editor's canvas and the bar
// editor.
Item {
  id: root

  // A DragLayer
  required property var dragLayer
  // Whether the drag being carried can go in the trash
  property bool active: false

  readonly property string targetKind: "trash"
  readonly property int dropPriority: 1
  readonly property bool hovered: root.dragLayer.hoverTarget === root

  implicitWidth: pill.implicitWidth
  implicitHeight: pill.implicitHeight
  opacity: root.active ? 1 : 0
  visible: root.opacity > 0
  z: 8

  Glide on opacity {}

  Rectangle {
    id: pill
    anchors.centerIn: parent
    implicitWidth: label.implicitWidth + icon.implicitWidth + Widget.padding * 3
    implicitHeight: Widget.height + Widget.padding
    radius: height / 2
    color: root.hovered ? Theme.error : Theme.backgroundAlt
    border.color: Theme.error
    border.width: Math.max(Appearance.borderWidth, 1)
    scale: root.hovered ? 1.08 : 1

    ColorGlide on color {}
    Glide on scale {}

    Row {
      anchors.centerIn: parent
      spacing: Widget.spacing

      StyledIcon {
        id: icon
        anchors.verticalCenter: parent.verticalCenter
        text: "delete"
        textColor: root.hovered ? Theme.background : Theme.error
        textSize: Appearance.fontSizeBy(4)
      }
      StyledText {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        text: I18n.tr("Drop to remove")
        textColor: root.hovered ? Theme.background : Theme.foreground
        font.bold: true
      }
    }
  }

  Component.onCompleted: root.dragLayer.registerTarget(root)
  Component.onDestruction: root.dragLayer.unregisterTarget(root)
}
