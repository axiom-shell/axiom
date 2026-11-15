pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.forms
import qs.services.core
import qs.components.content.parts.custom

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
  // The lock-screen column's width
  readonly property real lockWidth: Appearance.fontSize * 16
  // The previews: the popout at the design size, then the sizes a page may give
  // I18n.tr("Popout") I18n.tr("Square") I18n.tr("Wide") I18n.tr("Large") I18n.tr("Strip")
  readonly property var previews: [
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
  // The zoom that fits them in the width and height the tab has beside the
  // lock-screen column
  readonly property var previewSizes: root.previews.map(p => p.size)
  readonly property real previewZoom: CustomWidgetData.previewZoom(root.previewSizes, root.card, root.width, root.availableHeight, root.lockWidth + Widget.spacing * 2, Widget.spacing * 2)

  width: parent?.width ?? 0
  height: root.availableHeight
  spacing: Widget.spacing * 2

  // The previews, the lock screen switch
  RowLayout {
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    clip: true
    spacing: Widget.spacing * 2

    Repeater {
      model: root.previews

      ColumnLayout {
        id: preview
        required property var modelData
        readonly property real zoom: root.previewZoom
        Layout.alignment: Qt.AlignTop
        spacing: Widget.spacing / 2

        StyledText {
          text: I18n.tr(preview.modelData.label)
          role: "caption"
          tone: "muted"
        }
        // A module card sits on the overlay's page colour, as on a real page
        Surface {
          implicitWidth: GridPlacement.span(preview.modelData.size[0], root.card) * preview.zoom
          implicitHeight: GridPlacement.span(preview.modelData.size[1], root.card) * preview.zoom
          tone: "page"
          clip: true

          Item {
            width: parent.width / preview.zoom
            height: parent.height / preview.zoom
            scale: preview.zoom
            readonly property real contentZoom: scale
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

      SchemaPropertiesForm {
        Layout.preferredWidth: root.lockWidth
        propertiesSchema: Utils.pick(ConfigManager.configSchema.definitions.CustomWidget.properties.module.properties, ["lockscreen"])
        order: ["lockscreen"]
        values: root.definition?.module ?? ({})
        onEdited: (path, value) => root.editor.set(["module"].concat(path), value)
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

  ElementEditorLayout {
    Layout.fillWidth: true
    Layout.fillHeight: true
    elements: root.elements
    editable: root.definition !== null
  }
}
