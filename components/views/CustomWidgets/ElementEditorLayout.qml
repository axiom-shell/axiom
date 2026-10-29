pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.views.Layouts

// Custom widgets page, Module tab: the element library and the selected
// element down the left, and the layouts editor's canvas filling the rest,
// in one GridDragLayer (as LayoutsEditorLayout holds the layouts editor's),
// so elements are carried from the library onto the module.
GridDragLayer {
  id: root

  // The selected definition's elements, and whether there's one
  property var elements: []
  property bool editable: false

  editor: CustomWidgetsManager.editor.elements
  // Element kinds, not module types (schema labels)
  describe: type => {
    const kind = CustomWidgetsConfig.elementKind(type);
    return kind ? {
      "icon": kind.icon,
      "label": I18n.tr(kind.label)
    } : null;
  }
  // In grid units (4 sub-cells each)
  sizeLabel: (w, h) => I18n.tr("{0} × {1}", w / CustomWidgetData.subCells, h / CustomWidgetData.subCells)

  RowLayout {
    anchors.fill: parent
    spacing: Widget.spacing * 3

    StyledScrollView {
      id: side
      Layout.preferredWidth: Appearance.fontSize * 22
      Layout.fillHeight: true
      contentPadding: 0

      ElementInspector {
        width: side.availableWidth
        dragLayer: root
      }
    }

    // GridCanvas anchors itself to what holds it
    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      GridCanvas {
        dragLayer: root
        modules: root.editable ? root.elements : null
        title: I18n.tr("Module")
        icon: "widgets"
        emptyText: I18n.tr("Drag elements here from the left: the module's box fits them.")
      }
    }
  }
}
