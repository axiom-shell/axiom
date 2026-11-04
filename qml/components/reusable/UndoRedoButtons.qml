pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// An editor's Undo and Redo buttons, side by side, each enabled while
// there's a step to take (its EditHistory's canUndo / canRedo, passed in).
RowLayout {
  id: root

  property bool canUndo: false
  property bool canRedo: false

  signal undo
  signal redo

  spacing: 0

  FlatIconButton {
    size: Widget.iconButton
    iconText: "undo"
    tooltipText: I18n.tr("Undo")
    enabled: root.canUndo
    onClicked: root.undo()
  }
  FlatIconButton {
    size: Widget.iconButton
    iconText: "redo"
    tooltipText: I18n.tr("Redo")
    enabled: root.canRedo
    onClicked: root.redo()
  }
}
