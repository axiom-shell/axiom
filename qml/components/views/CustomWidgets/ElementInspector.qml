pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.forms
import qs.components.views.Layouts

// Custom widgets page, Module tab: the element library while nothing is
// selected; the selected element's settings in its place: its text fields
// (Shows: a ValueField per slot of its kind), the actions it runs and its look
// (its kind's options, CustomWidgetsConfig.elementKinds).
ColumnLayout {
  id: root

  // The GridDragLayer library elements are carried in
  required property var dragLayer
  readonly property var editor: CustomWidgetsManager.editor
  readonly property var grid: root.editor.elements
  readonly property var element: root.editor.element
  readonly property var kind: CustomWidgetsConfig.elementKind(root.element?.type ?? "")
  readonly property string elementKey: root.element ? root.editor.selectedId + "/" + root.editor.viewIndex + "/" + root.element.id : ""

  // The titles of an element's triggers ("On press", "On change"…): every
  // kind's `run` has the base's
  readonly property var triggerTitles: {
    const defs = ConfigManager.configSchema.definitions;
    const first = defs.CustomElement.oneOf[0].$ref.replace("#/definitions/", "");
    return defs[first].properties.run.properties;
  }
  // What the previewed sample makes of one of the element's text fields ("" unbound)
  function readBind(slot) {
    const binding = root.element?.bind?.[slot] ?? "";
    return binding && root.editor.previewFields ? CustomWidgetData.asText(CustomWidgetData.elementValue(root.editor.previewFields, binding)) : "";
  }

  // The name "New action…" gives an action made for this element: its name,
  // else its label, else its kind
  readonly property string actionName: root.element?.name || root.readBind("label") || I18n.tr(root.kind?.label ?? "")
  // What {value} reads as in the previewed sample, for the Runs line under a trigger
  readonly property string valueText: root.readBind("value")

  // The slots the Shows group lists: the kind's own. (show and tone, which
  // every kind has, are no text fields: they go with the colours)
  readonly property var shownSlots: (root.kind?.slots ?? []).filter(slot => slot !== "show" && slot !== "tone")

  // A slot's title in the Shows group. The names are the kinds' slots:
  // I18n.tr("Text") I18n.tr("Value") I18n.tr("Unit") I18n.tr("Label") I18n.tr("Icon")
  // I18n.tr("Badge") I18n.tr("Items") I18n.tr("Image") I18n.tr("State") I18n.tr("Min")
  // I18n.tr("Max") I18n.tr("Placeholder") I18n.tr("Enabled") I18n.tr("Second value")
  function slotTitle(name) {
    const titles = {
      "text": I18n.tr("Text"),
      "value": I18n.tr("Value"),
      "value2": I18n.tr("Second value"),
      "unit": I18n.tr("Unit"),
      "label": I18n.tr("Label"),
      "icon": I18n.tr("Icon"),
      "badge": I18n.tr("Badge"),
      "items": I18n.tr("Items"),
      "image": I18n.tr("Image"),
      "state": I18n.tr("State"),
      "min": I18n.tr("Min"),
      "max": I18n.tr("Max"),
      "placeholder": I18n.tr("Placeholder"),
      "enabled": I18n.tr("Enabled")
    };
    return titles[name] ?? name;
  }

  // What an empty slot means. Most fall back to the output's own key; a
  // Button's label to its action's name; `enabled` is always on; a Button's
  // icon and value, a Toggle's label and an Entry's placeholder are empty
  function slotPlaceholder(name) {
    const type = root.element?.type ?? "";
    if (name === "enabled")
      return I18n.tr("Always");
    if (type === "Button")
      return name === "label" ? I18n.tr("The action's name") : "";
    if (type === "Entry" || (type === "Toggle" && name === "label"))
      return "";
    return I18n.tr("The output's own");
  }

  // What a slot's {value} is for, where it isn't plain
  function slotDescription(name) {
    return root.element?.type === "Button" && name === "value" ? I18n.tr("Sent to the action as {value}") : "";
  }

  spacing: Widget.spacing * 2

  // The library: drag one onto the module, or click it to add it where
  // there's room. It is the whole of the nothing-selected state
  FieldGroup {
    visible: !root.element
    Layout.fillWidth: true
    title: I18n.tr("Add an element")
    description: I18n.tr("Drag one onto the module, or click it to add it where there's room.")

    Flow {
      Layout.fillWidth: true
      spacing: Widget.spacing

      Repeater {
        model: CustomWidgetsConfig.elementKinds

        ModuleChip {
          required property var modelData
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
    key: root.elementKey

    sourceComponent: ColumnLayout {
      width: selected.width
      spacing: Widget.spacing * 2

      InspectorHeader {
        icon: root.kind?.icon ?? "widgets"
        title: I18n.tr(root.kind?.label ?? root.element?.type ?? "")
        // In grid units, as the canvas sizes it
        subtitle: root.element ? I18n.tr("{0} × {1}", root.element.place.w / CustomWidgetData.subCells, root.element.place.h / CustomWidgetData.subCells) : ""

        canDuplicate: true
        duplicateTooltip: I18n.tr("Copy this element")
        canRemove: true
        removeTooltip: I18n.tr("Remove this element")
        closable: true
        closeTooltip: I18n.tr("Back to the elements")
        onDuplicate: root.grid.duplicateModule(root.grid.selected)
        onRemove: root.grid.removeModule(root.grid.selected)
        onClose: root.grid.clearSelection()
      }

      // Shown on the canvas: empty, the kind
      InspectorRow {
        first: true
        label: I18n.tr("Name")

        StyledTextEntry {
          id: nameEntry
          Layout.fillWidth: true
          placeholderText: I18n.tr(root.kind?.label ?? "")
          onTextEdited: root.editor.setElement(["name"], nameEntry.text)
          Binding {
            target: nameEntry
            property: "text"
            value: root.element?.name ?? ""
            when: !nameEntry.input.activeFocus
            restoreMode: Binding.RestoreNone
          }
        }
      }

      FieldGroup {
        visible: root.shownSlots.length > 0
        Layout.fillWidth: true
        title: I18n.tr("Shows")
        headerExtras: TipIcon {
          text: "help"
          tip: I18n.tr("Type text, or insert {a value}.")
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          // By count over the kind's slots
          Repeater {
            model: root.shownSlots

            ValueField {
              id: field
              required property string modelData
              required property int index
              Layout.fillWidth: true
              first: field.index === 0
              slot: field.modelData
              label: root.slotTitle(field.modelData)
              description: root.slotDescription(field.modelData)
              placeholder: root.slotPlaceholder(field.modelData)
            }
          }
        }
      }

      FieldGroup {
        visible: (root.kind?.actions.length ?? 0) > 0
        Layout.fillWidth: true
        title: I18n.tr("Runs")
        description: I18n.tr("Never on the lock screen.")

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          Repeater {
            model: root.kind?.actions ?? []

            TriggerField {
              id: trigger
              required property string modelData
              required property int index
              first: trigger.index === 0
              label: root.triggerTitles[trigger.modelData].title
              current: root.element?.run?.[trigger.modelData] ?? ""
              newName: root.actionName
              valueText: root.valueText
              writeRun: value => root.editor.setElement(["run", trigger.modelData], value)
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

      StyledTextButton {
        Layout.alignment: Qt.AlignRight
        implicitHeight: Widget.height
        kind: "text"
        text: I18n.tr("More in Help")
        onClicked: root.editor.openHelp("slots")
      }
    }
  }
}
