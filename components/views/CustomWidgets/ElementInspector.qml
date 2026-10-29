pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.forms
import qs.components.views.Layouts

// Custom widgets page, Module tab: the selected element's bindings (each
// slot: the widget's own field, another field, a path in the output or a
// format), its look (its kind's options, CustomWidgetData.elementKinds) and
// the commands it runs, under the element library.
ColumnLayout {
  id: root

  // The GridDragLayer library elements are carried in
  required property var dragLayer
  readonly property var editor: CustomWidgetsManager.editor
  readonly property var grid: root.editor.elements
  readonly property var element: root.grid.selected >= 0 ? (root.editor.selected?.module?.elements?.[root.grid.selected] ?? null) : null
  readonly property var kind: CustomWidgetData.elementKind(root.element?.type ?? "")
  readonly property var fields: CustomWidgetsManager.fields[root.editor.selectedId] ?? null
  // The binding choices: the fields, then the sample's paths
  readonly property var bindOptions: [
    {
      "value": "",
      "label": I18n.tr("The widget's own")
    }
  ].concat(CustomWidgetData.fieldNames.map(name => ({
        "value": name,
        "label": name
      }))).concat((root.fields?.sample ? CustomWidgetData.flatten(root.fields.sample) : []).filter(p => p.type !== "object" && !CustomWidgetData.fieldNames.includes(p.path)).map(p => ({
        "value": p.path,
        "label": p.path
      })))

  spacing: Widget.spacing * 2

  // I18n.tr("click") I18n.tr("change") I18n.tr("on") I18n.tr("off")
  // I18n.tr("text") I18n.tr("value") I18n.tr("unit") I18n.tr("label")
  // I18n.tr("icon") I18n.tr("badge") I18n.tr("items") I18n.tr("image")
  // I18n.tr("state")
  readonly property var actionTitles: ({
      "click": "On click",
      "change": "On change ({value} is the new value)",
      "on": "Turning it on",
      "off": "Turning it off"
    })

  // The library: drag one onto the module, or click it to add it where
  // there's room
  FieldGroup {
    Layout.fillWidth: true
    title: I18n.tr("Elements")
    description: I18n.tr("Drag one onto the module, or click it to add it where there's room.")

    Repeater {
      model: CustomWidgetData.elementKinds

      ModuleChip {
        required property var modelData
        Layout.fillWidth: true
        dragLayer: root.dragLayer
        // Kind labels: declared in CustomWidgetData.elementKinds
        typeInfo: modelData
        onClicked: root.grid.addModule(modelData.type)
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

      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing

        StyledIcon {
          text: root.kind?.icon ?? "widgets"
          textColor: Theme.accent
        }
        StyledText {
          Layout.fillWidth: true
          text: I18n.tr(root.kind?.label ?? root.element?.type ?? "")
          font.bold: true
        }
        FlatIconButton {
          size: Widget.iconButton
          iconText: "content_copy"
          tooltipText: I18n.tr("Copy this element")
          onClicked: root.grid.duplicateModule(root.grid.selected)
        }
        FlatIconButton {
          size: Widget.iconButton
          iconText: "delete"
          tooltipText: I18n.tr("Remove this element")
          onClicked: root.grid.removeModule(root.grid.selected)
        }
        FlatIconButton {
          size: Widget.iconButton
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
              Layout.preferredWidth: Appearance.fontSize * 5
              text: I18n.tr(slot.modelData)
            }
            StyledComboEntry {
              Layout.fillWidth: true
              editable: true
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
          order: Object.keys(root.kind?.options ?? {})
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
          propertiesSchema: (root.kind?.actions ?? []).reduce((schema, action) => {
            schema[action] = {
              "type": "string",
              "title": root.actionTitles[action],
              "default": "",
              "x-scope": "commands"
            };
            return schema;
          }, {})
          order: root.kind?.actions ?? []
          values: root.element?.actions ?? ({})
          onEdited: (path, value) => root.editor.setElement(["actions"].concat(path), value)
        }
      }
    }
  }
}
