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
// proportionally) across the top; under it the layer strip (the base
// elements, and a chip per screen, with the selected screen's form), then
// the element library and the selected element down the left, and the
// layouts editor's canvas filling the rest, editing the layer's elements as
// it edits a submenu's modules (drag in, move, resize from any side, push,
// box-select, guides, undo). The module's box fits the elements of every
// layer; the base is drawn dimmed under a screen being edited. The previews draw the
// edited screen's sample (kept in the definition, else the last one seen
// live: CustomWidgetsEditor.previewFields), so every screen can be designed
// before the script reaches it.
ColumnLayout {
  id: root

  required property var grid
  // The height the tab has (the page's, less its header)
  required property real availableHeight
  readonly property var editor: CustomWidgetsManager.editor
  readonly property var definition: root.editor.selected
  // The layer being edited (the base, or a screen)
  readonly property var elements: root.editor.layerElements
  readonly property var views: root.definition?.module?.views ?? []
  readonly property var view: root.views[root.editor.viewIndex] ?? null
  readonly property var designSize: CustomWidgetData.designSize(CustomWidgetData.allElements(root.definition?.module), root.definition?.module?.size)
  readonly property real card: root.grid?.unit ?? Widget.px(400)
  // The lock-screen column's width: wide enough for its button's whole label
  readonly property real lockWidth: CustomWidgetData.lockColumnWidth(Appearance.fontSize * 16, defaultLayoutButton.implicitWidth)
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
              fields: root.editor.previewFields ?? ({})
              history: CustomWidgetsManager.history[root.editor.selectedId] ?? ({})
              actionsEnabled: false
              viewIndex: root.editor.viewIndex
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
        id: defaultLayoutButton
        visible: root.elements.length === 0 && root.views.length === 0
        implicitHeight: Widget.height
        iconText: "auto_awesome"
        text: I18n.tr("Start from the default layout")
        onClicked: root.editor.useDefaultElements()
      }
    }
  }

  // The base is empty and the sample picks no screen: nothing to draw
  Notice {
    visible: root.editor.viewIndex < 0 && root.views.length > 0 && root.elements.length === 0 && CustomWidgetData.pickView(root.definition?.module, CustomWidgetsManager.fields[root.editor.selectedId] ?? null).index < 0
    status: "info"
    title: I18n.tr("No screen for this sample")
    text: I18n.tr("The base elements are empty: pick a screen to design it.")
  }

  // The layers: the base, and a screen each (the first whose condition
  // holds is drawn over the base)
  Flow {
    Layout.fillWidth: true
    spacing: Widget.spacing

    ToggleChip {
      text: I18n.tr("Base")
      checked: root.editor.viewIndex < 0
      onToggled: root.editor.selectView(-1)
    }
    Repeater {
      model: root.views.length

      ToggleChip {
        id: chip
        required property int index
        text: root.views[chip.index]?.name || root.views[chip.index]?.id || ""
        checked: root.editor.viewIndex === chip.index
        onToggled: root.editor.selectView(chip.index)
      }
    }
    StyledTextButton {
      implicitHeight: Widget.smallHeight
      iconText: "add"
      text: I18n.tr("Add a screen")
      enabled: root.definition !== null
      onClicked: root.editor.addView(I18n.tr("Screen {0}", root.views.length + 1))
    }
  }

  // The selected screen: its name, whether the base shows under it, and
  // when it is drawn
  FieldGroup {
    visible: root.view !== null
    Layout.fillWidth: true
    title: I18n.tr("Screen")
    description: I18n.tr("Drawn over the base elements while its condition holds; the first screen that holds wins. The key \"error\" is the script's failure.")

    KeyedLoader {
      Layout.fillWidth: true
      Layout.preferredHeight: childrenRect.height
      key: root.view ? root.editor.selectedId + "/" + root.editor.viewIndex : ""

      sourceComponent: ColumnLayout {
        width: parent?.width ?? 0
        spacing: Widget.spacing

        SchemaPropertiesForm {
          Layout.fillWidth: true
          propertiesSchema: Utils.pick(ConfigManager.configSchema.definitions.CustomWidget.properties.module.properties.views.items.properties, ["name", "base", "when"])
          order: ["name", "base", "when"]
          values: root.view ?? ({})
          onEdited: (path, value) => root.editor.setView(path, value)
        }
        StyledTextButton {
          implicitHeight: Widget.height
          iconText: "delete"
          text: I18n.tr("Remove this screen")
          onClicked: root.editor.removeView(root.editor.viewIndex)
        }
      }
    }
  }

  ElementEditorLayout {
    Layout.fillWidth: true
    Layout.fillHeight: true
    elements: root.elements
    editable: root.definition !== null
    underlay: root.view && root.view.base ? (root.definition?.module?.elements ?? []).map(e => ({
          "place": e.place,
          "label": e.options?.label || e.type
        })) : []
  }
}
