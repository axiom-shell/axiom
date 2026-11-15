pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.forms
import qs.services.ui
import qs.services.compositor
import qs.components.views.Layouts

// Custom widgets page, Module tab: the element library (shown while no
// element is selected), then the selected
// element's bindings (each slot: the output's own key, a path in it, a
// format or a number), its look (its kind's options,
// CustomWidgetsConfig.elementKinds) and the commands it runs.
ColumnLayout {
  id: root

  // The GridDragLayer library elements are carried in
  required property var dragLayer
  readonly property var editor: CustomWidgetsManager.editor
  readonly property var grid: root.editor.elements
  readonly property var element: root.editor.element
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

  // A slot's title in the Shows group: the kinds' slot names (translated as
  // they are), the two every kind has (show and tone) and a Sparkline's second series
  function slotTitle(name) {
    return name === "show" ? I18n.tr("Show when") : name === "tone" ? I18n.tr("Color by") : name === "value2" ? I18n.tr("Second value") : I18n.tr(name);
  }

  // What an empty slot means: the output's own key, for show and tone
  // nothing (always shown, not coloured)
  function slotOptions(name) {
    const none = name === "show" ? I18n.tr("Always") : I18n.tr("Not colored");
    return name === "show" || name === "tone" ? [
      {
        "value": "",
        "label": none
      }
    ].concat(root.bindOptions.slice(1)) : root.bindOptions;
  }

  // The actions an element can name: none (its own commands), the
  // built-ins, an action of the shell that's allowed (never a session or
  // destructive one), then the ids the output's `actions` lists
  readonly property var actionOptions: {
    const refused = ActionsManager.sessionActions.concat(KeybindManager.actions.filter(id => ActionsManager.destructive(id)));
    const out = [
      {
        "value": "",
        "label": I18n.tr("None (the commands)")
      }
    ];
    for (const id of CustomWidgetsConfig.builtinActions)
      out.push({
        "value": id,
        "label": CustomWidgetsManager.actionLabel(id)
      });
    for (const id of KeybindManager.actions) {
      if (CustomWidgetData.builtinAllowed("axiom:" + id, refused))
        out.push({
          "value": "axiom:" + id,
          "label": ActionsManager.label(id)
        });
    }
    for (const id of Object.keys(root.fields?.actions ?? ({})))
      out.push({
        "value": id,
        "label": id
      });
    return out;
  }

  spacing: Widget.spacing * 2

  // Slot names, shown as is: I18n.tr("text") I18n.tr("value")
  // I18n.tr("unit") I18n.tr("label") I18n.tr("icon") I18n.tr("badge")
  // I18n.tr("items") I18n.tr("image") I18n.tr("state") I18n.tr("min")
  // I18n.tr("max") I18n.tr("placeholder") I18n.tr("enabled")

  // The library: drag one onto the module, or click it to add it where
  // there's room
  // Only while no element is selected, as the layouts editor's library
  Loader {
    active: root.element === null
    visible: active
    Layout.fillWidth: true
    // A Flow's height comes from its width
    Layout.preferredHeight: (item as Item)?.implicitHeight ?? 0

    // (Its title and description are the column's header, in
    // ElementEditorLayout)
    sourceComponent: Flow {
      width: parent?.width ?? 0
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
    key: root.element ? root.editor.selectedId + "/" + root.editor.viewIndex + "/" + root.element.id : ""

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

            StyledLabel {
              Layout.preferredWidth: Widget.textPx(70)
              text: root.slotTitle(slot.modelData)
            }
            StyledComboEntry {
              Layout.fillWidth: true
              editable: true
              placeholderText: root.slotOptions(slot.modelData)[0].label
              value: root.element?.bind?.[slot.modelData] ?? ""
              options: root.slotOptions(slot.modelData)
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

        // A named action (the script's, or a built-in) instead of the
        // commands below
        RowLayout {
          Layout.fillWidth: true
          spacing: Widget.spacing

          StyledLabel {
            Layout.preferredWidth: Widget.textPx(70)
            text: I18n.tr("Action")
          }
          StyledComboEntry {
            Layout.fillWidth: true
            editable: true
            placeholderText: I18n.tr("None (the commands)")
            value: root.element?.action ?? ""
            options: root.actionOptions
            onPicked: value => root.editor.setElement(["action"], value)
          }
        }
        StyledText {
          visible: (root.element?.action ?? "") !== "" && !(root.element.action ?? "").startsWith("axiom:") && !root.editor.selected?.invoke.command
          Layout.fillWidth: true
          text: I18n.tr("Set the action command first")
          tone: "warning"
          overflow: "wrap"
        }

        SchemaPropertiesForm {
          visible: (root.element?.action ?? "") === ""
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
