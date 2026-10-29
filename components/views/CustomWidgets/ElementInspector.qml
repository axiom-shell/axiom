pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.forms
import qs.components.views.Layouts

// Custom widgets page, Module tab: the element library, then the selected
// element's bindings (each slot: the output's own key, a path in it, a
// format or a number), its look (its kind's options,
// CustomWidgetsConfig.elementKinds) and the commands it runs.
ColumnLayout {
  id: root

  // The GridDragLayer library elements are carried in
  required property var dragLayer
  readonly property var editor: CustomWidgetsManager.editor
  readonly property var grid: root.editor.elements
  readonly property var element: root.grid.selected >= 0 ? (root.editor.selected?.module?.elements?.[root.grid.selected] ?? null) : null
  readonly property var kind: CustomWidgetsConfig.elementKind(root.element?.type ?? "")
  readonly property var fields: CustomWidgetsManager.fields[root.editor.selectedId] ?? null
  // The binding choices: the output's own key, or any path in it (a
  // format or a number can be typed)
  readonly property var bindOptions: [
    {
      "value": "",
      "label": I18n.tr("The output's own")
    }
  ].concat((root.fields?.sample ? CustomWidgetData.flatten(root.fields.sample) : []).filter(p => p.type !== "object").map(p => ({
        "value": p.path,
        "label": p.path
      })))

  spacing: Widget.spacing * 2

  // Slot names, shown as is: I18n.tr("text") I18n.tr("value")
  // I18n.tr("unit") I18n.tr("label") I18n.tr("icon") I18n.tr("badge")
  // I18n.tr("items") I18n.tr("image") I18n.tr("state") I18n.tr("min")
  // I18n.tr("max")

  // The library: drag one onto the module, or click it to add it where
  // there's room
  // Only while no element is selected, as the layouts editor's library
  Loader {
    active: root.element === null
    visible: active
    Layout.fillWidth: true

    sourceComponent: FieldGroup {
      title: I18n.tr("Elements")
      description: I18n.tr("Drag one onto the module, or click it to add it where there's room.")

      Repeater {
        model: CustomWidgetsConfig.elementKinds

        ModuleChip {
          required property var modelData
          Layout.fillWidth: true
          dragLayer: root.dragLayer
          // Kind labels: the schema's
          typeInfo: modelData
          onClicked: root.grid.addModule(modelData.type)
        }
      }
    }
  }

  // The selected element, rebuilt per element
  KeyedLoader {
    id: selected
    Layout.fillWidth: true
    Layout.preferredHeight: selected.childrenRect.height
    key: root.element ? root.editor.selectedId + "/" + root.element.id : ""

    sourceComponent: ColumnLayout {
      width: selected.width
      spacing: Widget.spacing * 2

      InspectorHeader {
        icon: root.kind?.icon ?? "widgets"
        title: I18n.tr(root.kind?.label ?? root.element?.type ?? "")
        // In grid units, as the canvas sizes it
        subtitle: root.element ? I18n.tr("{0} × {1}", root.element.place.w / CustomWidgetData.subCells, root.element.place.h / CustomWidgetData.subCells) : ""

        SquareIconButton {
          size: Widget.height
          iconText: "content_copy"
          tooltipText: I18n.tr("Copy this element")
          onClicked: root.grid.duplicateModule(root.grid.selected)
        }
        SquareIconButton {
          size: Widget.height
          iconText: "delete"
          tooltipText: I18n.tr("Remove this element")
          onClicked: root.grid.removeModule(root.grid.selected)
        }
        SquareIconButton {
          size: Widget.height
          iconText: "close"
          tooltipText: I18n.tr("Back to the elements")
          onClicked: root.grid.clearSelection()
        }
      }

      FieldGroup {
        visible: (root.kind?.slots.length ?? 0) > 0
        Layout.fillWidth: true
        title: I18n.tr("Shows")

        Repeater {
          model: root.kind?.slots ?? []

          RowLayout {
            id: slot
            required property string modelData
            Layout.fillWidth: true
            spacing: Widget.spacing

            StyledText {
              elide: Text.ElideRight
              Layout.preferredWidth: Appearance.fontSize * 5
              text: I18n.tr(slot.modelData)
            }
            StyledComboEntry {
              Layout.fillWidth: true
              editable: true
              placeholderText: I18n.tr("The output's own")
              value: root.element?.bind?.[slot.modelData] ?? ""
              options: root.bindOptions
              onPicked: value => root.editor.setElement(["bind", slot.modelData], value === "" ? undefined : value)
            }
          }
        }
      }

      FieldGroup {
        visible: Object.keys(root.kind?.options ?? {}).length > 0
        Layout.fillWidth: true
        title: I18n.tr("Look")

        SchemaPropertiesForm {
          Layout.fillWidth: true
          propertiesSchema: root.kind?.options ?? ({})
          order: root.kind?.optionsOrder ?? []
          values: root.element?.options ?? ({})
          onEdited: (path, value) => root.editor.setElement(["options"].concat(path), value)
        }
      }

      FieldGroup {
        visible: (root.kind?.actions.length ?? 0) > 0
        Layout.fillWidth: true
        title: I18n.tr("Runs")
        description: I18n.tr("Never on the lock screen.")

        SchemaPropertiesForm {
          Layout.fillWidth: true
          propertiesSchema: root.kind?.actionsSchema ?? ({})
          order: root.kind?.actions ?? []
          values: root.element?.actions ?? ({})
          onEdited: (path, value) => root.editor.setElement(["actions"].concat(path), value)
        }
      }
    }
  }
}
