pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.reusable

// The modules that can be added to the page or menu being edited: drag one
// onto the canvas, or click it to add it at its default size in the first
// free spot. By name, or by group.
ColumnLayout {
  id: root

  required property var dragLayer

  readonly property var modules: OverlayConfig.modulesFor(root.dragLayer.editor.host)

  spacing: Widget.spacing

  StyledText {
    Layout.fillWidth: true
    elide: Text.ElideRight
    text: I18n.tr("Drag a module onto the canvas, or click one to add it.")
    opacity: 0.6
    textSize: Appearance.fontSizeBy(-2)
  }

  TypeLibrary {
    id: library
    Layout.fillWidth: true
    Layout.fillHeight: true
    types: root.modules
    groups: OverlayConfig.libraryGroups
    grouped: EditsManager.libraryGrouped
    // Schema keys (labels, group names)
    labelOf: type => I18n.tr(type.label)
    headingOf: name => name ? I18n.tr(name) : I18n.tr("Other")
    minTileWidth: Appearance.fontSize * 16
    onGroupingChosen: grouped => EditsManager.setLibraryGrouped(grouped)

    delegate: ModuleChip {
      id: chip
      required property var modelData
      implicitWidth: library.tileWidth
      dragLayer: root.dragLayer
      typeInfo: chip.modelData
      onClicked: root.dragLayer.editor.addModule(chip.modelData.type)
    }
  }
}
