pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.content.parts.custom
import qs.components.views.Layouts

// Custom widgets page, Module tab: the module as it's drawn (the bar
// widget's popout, and the sizes a page may give it: it's laid out
// proportionally) across the top; under it the element library and the
// selected element down the left, and the layouts editor's canvas filling
// the rest, editing the elements as it edits a submenu's modules (drag in,
// move, resize from any side, push, box-select, guides, undo). The
// module's box fits its elements.
ColumnLayout {
  id: root

  required property var grid
  // The height the tab has (the page's, less its header)
  required property real availableHeight
  readonly property var editor: CustomWidgetsManager.editor
  readonly property var definition: root.editor.selected
  readonly property var elements: root.definition?.module?.elements ?? []
  readonly property var designSize: CustomWidgetData.designSize(root.elements, root.definition?.module?.size)
  readonly property real card: root.grid?.unit ?? Widget.px(400)

  width: parent?.width ?? 0
  height: root.availableHeight
  spacing: Widget.spacing * 2

  // The previews, the lock screen switch
  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing * 2

    // I18n.tr("Popout") I18n.tr("Square") I18n.tr("Wide") I18n.tr("Large") I18n.tr("Strip")
    Repeater {
      model: [
        {
          "label": "Popout",
          "size": root.designSize
        },
        {
          "label": "Square",
          "size": [4, 4]
        },
        {
          "label": "Wide",
          "size": [8, 2]
        },
        {
          "label": "Large",
          "size": [8, 4]
        },
        {
          "label": "Strip",
          "size": [4, 1]
        }
      ]

      ColumnLayout {
        id: preview
        required property var modelData
        readonly property real zoom: Math.min(0.3, root.availableHeight * 0.22 / Math.max(1, GridPlacement.span(Math.max(...[root.designSize[1], 4]), root.card)))
        Layout.alignment: Qt.AlignTop
        spacing: Widget.spacing / 2

        StyledText {
          text: I18n.tr(preview.modelData.label)
          textSize: Appearance.fontSizeBy(-2)
          opacity: 0.7
        }
        Rectangle {
          implicitWidth: GridPlacement.span(preview.modelData.size[0], root.card) * preview.zoom
          implicitHeight: GridPlacement.span(preview.modelData.size[1], root.card) * preview.zoom
          radius: Widget.radius
          color: Appearance.fill(Theme.background)
          border.color: Theme.border
          border.width: Appearance.borderWidth
          clip: true

          Item {
            width: parent.width / preview.zoom
            height: parent.height / preview.zoom
            scale: preview.zoom
            transformOrigin: Item.TopLeft

            CustomLayout {
              anchors.fill: parent
              anchors.margins: Widget.cardPadding
              definition: root.definition
              fields: CustomWidgetsManager.fields[root.editor.selectedId] ?? ({})
              history: CustomWidgetsManager.history[root.editor.selectedId] ?? ({})
              actionsEnabled: false
            }
          }
        }
      }
    }

    Item {
      Layout.fillWidth: true
    }

    ColumnLayout {
      Layout.alignment: Qt.AlignTop
      spacing: Widget.spacing

      RowLayout {
        spacing: Widget.spacing
        StyledText {
          text: I18n.tr("On the lock screen")
        }
        StyledSwitch {
          checked: root.definition?.module?.lockscreen ?? false
          onToggled: root.editor.set(["module", "lockscreen"], checked)
        }
      }
      StyledTextButton {
        visible: root.elements.length === 0
        implicitHeight: Widget.height
        iconText: "auto_awesome"
        text: I18n.tr("Start from the default layout")
        onClicked: root.editor.useDefaultElements()
      }
    }
  }

  GridDragLayer {
    id: elementLayer
    Layout.fillWidth: true
    Layout.fillHeight: true
    editor: root.editor.elements
    // Element kinds, not module types (labels declared in CustomWidgetData)
    describe: type => {
      const kind = CustomWidgetData.elementKind(type);
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
          dragLayer: elementLayer
        }
      }

      // GridCanvas anchors itself to what holds it
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        GridCanvas {
          dragLayer: elementLayer
          modules: root.definition ? root.elements : null
          title: I18n.tr("Module")
          icon: "widgets"
          emptyText: I18n.tr("Drag elements here from the left: the module's box fits them.")
        }
      }
    }
  }
}
