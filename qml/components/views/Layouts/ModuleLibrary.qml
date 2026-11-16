pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.views.base

// The modules that can be added to the page or menu being edited: drag one
// onto the canvas, or click it to add it at its default size in the first
// free spot. By name, or by group (an EditorLibrary).
EditorLibrary {
  id: root

  required property var dragLayer

  types: OverlayConfig.modulesFor(root.dragLayer.editor.host)
  caption: I18n.tr("Drag a module onto the canvas, or click one to add it.")
  groups: OverlayConfig.libraryGroups
  minTileWidth: Appearance.fontSize * 16

  delegate: ModuleChip {
    id: chip
    required property var modelData
    implicitWidth: root.tileWidth
    dragLayer: root.dragLayer
    typeInfo: chip.modelData
    onClicked: root.dragLayer.editor.addModule(chip.modelData.type)
  }
}
