pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.forms
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
  // The binding choices: the output's own key, or any path in the saved
  // samples, what was seen and the output now (a format or a number can be
  // typed), each labelled with its value
  readonly property var bindOptions: [
    {
      "value": "",
      "label": I18n.tr("The output's own")
    }
  ].concat(root.editor.bindPaths.map(p => ({
        "value": p.path,
        "label": p.path + " — " + (p.type === "array" ? I18n.tr("a list of {0}", p.value) : p.preview)
      })))
  // The slot an edit last started in, "<element key>|<slot>": a click in the
  // Data panel binds it
  property string lastSlot: ""
  readonly property string elementKey: root.element ? root.editor.selectedId + "/" + root.editor.viewIndex + "/" + root.element.id : ""
  property bool dataOpen: false
  property bool libraryFolded: false

  // What a slot's binding reads as in the previewed sample: { text, missing }
  // ("" without a binding or a sample; a `=` binding is fixed text)
  function nowOf(binding) {
    if (!binding || root.editor.previewFields === null)
      return {
        "text": "",
        "missing": false
      };
    if (binding.startsWith("="))
      return {
        "text": I18n.tr("fixed text"),
        "missing": false
      };
    const value = CustomWidgetData.elementValue(root.editor.previewFields, binding);
    return {
      "text": value === undefined ? "" : CustomWidgetData.asText(value),
      "missing": value === undefined
    };
  }

  // The action command the selected element runs, as it would for the
  // previewed sample ("" for none, a built-in or no action command)
  readonly property string runsLine: {
    const action = root.element?.action ?? "";
    const command = root.editor.selected?.invoke?.command ?? "";
    if (action === "" || action.startsWith("axiom:") || command === "")
      return "";
    const fields = root.editor.previewFields;
    const values = {
      "action": action,
      "rev": CustomWidgetData.asText(fields?.rev),
      "tree": Paths.treePath
    };
    // The element's own value, when it binds one
    if (root.element.bind?.value && fields)
      values.value = CustomWidgetData.asText(CustomWidgetData.elementValue(fields, root.element.bind.value));
    return CustomWidgetData.fillCommand(command, values);
  }

  // A path clicked in the Data panel: bound to the slot last started in on
  // this element, else to a new Text
  function bindPath(path) {
    const at = root.lastSlot.indexOf("|");
    if (root.element && at > 0 && root.lastSlot.slice(0, at) === root.elementKey) {
      root.editor.setElement(["bind", root.lastSlot.slice(at + 1)], path);
      return;
    }
    root.grid.addModule("Text");
    root.editor.setElement(["bind", "text"], path);
  }

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

  spacing: Widget.spacing * 2

  // Slot names, shown as is: I18n.tr("text") I18n.tr("value")
  // I18n.tr("unit") I18n.tr("label") I18n.tr("icon") I18n.tr("badge")
  // I18n.tr("items") I18n.tr("image") I18n.tr("state") I18n.tr("min")
  // I18n.tr("max") I18n.tr("placeholder") I18n.tr("enabled")

  // The library: drag one onto the module, or click it to add it where
  // there's room. Always there, as a group that folds away
  FoldingSection {
    title: I18n.tr("Elements")
    collapsed: root.libraryFolded
    onToggled: root.libraryFolded = !root.libraryFolded

    Loader {
      active: !root.libraryFolded
      Layout.fillWidth: true
      // A Flow's height comes from its width
      Layout.preferredHeight: (item as Item)?.implicitHeight ?? 0

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

      // Shown on the canvas: empty, the kind
      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing

        StyledLabel {
          Layout.preferredWidth: Widget.textPx(70)
          text: I18n.tr("Name")
        }
        StyledTextEntry {
          id: nameEntry
          Layout.fillWidth: true
          placeholderText: I18n.tr(root.kind?.label ?? "")
          onTextEdited: root.editor.setElement(["name"], nameEntry.text)
          Component.onCompleted: nameEntry.text = root.element?.name ?? ""
        }
      }

      FieldGroup {
        visible: (root.kind?.slots.length ?? 0) > 0
        Layout.fillWidth: true
        title: I18n.tr("Shows")

        Repeater {
          model: root.kind?.slots ?? []

          ColumnLayout {
            id: slot
            required property string modelData
            readonly property var now: root.nowOf(root.element?.bind?.[slot.modelData] ?? "")
            Layout.fillWidth: true
            spacing: Widget.spacing / 2

            RowLayout {
              Layout.fillWidth: true
              spacing: Widget.spacing

              StyledLabel {
                Layout.preferredWidth: Widget.textPx(70)
                text: root.slotTitle(slot.modelData)
              }
              SquareIconButton {
                iconText: "help"
                tooltipText: I18n.tr("What a slot reads")
                onClicked: root.editor.openHelp("slots")
              }
              StyledComboEntry {
                id: combo
                Layout.fillWidth: true
                editable: true
                placeholderText: root.slotOptions(slot.modelData)[0].label
                value: root.element?.bind?.[slot.modelData] ?? ""
                options: root.slotOptions(slot.modelData)
                onPicked: value => {
                  root.lastSlot = root.elementKey + "|" + slot.modelData;
                  root.editor.setElement(["bind", slot.modelData], value === "" ? undefined : value);
                }

                Connections {
                  target: combo.input
                  function onActiveFocusChanged() {
                    if (combo.input.activeFocus)
                      root.lastSlot = root.elementKey + "|" + slot.modelData;
                  }
                }
              }
            }
            // What it reads in the previewed sample
            StyledText {
              visible: slot.now.text !== "" || slot.now.missing
              Layout.fillWidth: true
              Layout.leftMargin: Widget.textPx(70) + Widget.spacing
              text: slot.now.missing ? I18n.tr("Nothing at this path in the previewed sample") : I18n.tr("now: {0}", slot.now.text)
              role: "caption"
              tone: slot.now.missing ? "warning" : "muted"
              textFamily: slot.now.missing ? "" : "monospace"
              overflow: "line"
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
          SquareIconButton {
            iconText: "help"
            tooltipText: I18n.tr("How actions work")
            onClicked: root.editor.openHelp("actions")
          }
          StyledComboEntry {
            Layout.fillWidth: true
            editable: true
            placeholderText: I18n.tr("None (the commands)")
            value: root.element?.action ?? ""
            options: root.editor.actionOptions
            onPicked: value => root.editor.setElement(["action"], value)
          }
        }
        // What pressing it runs, filled from the previewed sample
        StyledText {
          visible: root.runsLine !== ""
          Layout.fillWidth: true
          text: I18n.tr("Runs: {0}", root.runsLine)
          textFamily: "monospace"
          role: "caption"
          tone: "muted"
          elide: Text.ElideMiddle // style-exempt: middle
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

  // What the output holds, by path: a click binds it to the slot last
  // started in, or adds a Text showing it
  FoldingSection {
    visible: root.editor.bindPaths.length > 0
    title: I18n.tr("Data")
    description: I18n.tr("Click a value to bind it to the slot you were in, or to a new text.")
    collapsed: !root.dataOpen
    onToggled: root.dataOpen = !root.dataOpen

    CustomWidgetPaths {
      Layout.fillWidth: true
      paths: root.editor.bindPaths
      maxRows: 100
      pickable: true
      onPicked: path => root.bindPath(path)
    }
  }
}
