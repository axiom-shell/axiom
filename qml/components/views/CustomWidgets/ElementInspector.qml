pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.forms
import qs.components.content.base
import qs.components.views.Layouts

// Custom widgets page, Module tab: while nothing is selected the element
// library and the module's own settings (lock screen, font); the selected
// element's settings in their place: its text fields
// (Shows: a ValueField per slot of its kind), the actions it runs, when it is
// shown (Visible), its colours (a ColorField each) and its look (the rest of
// its kind's options, CustomWidgetsConfig.elementKinds).
ColumnLayout {
  id: root

  // The GridDragLayer library elements are carried in
  required property var dragLayer
  readonly property var editor: CustomWidgetsManager.editor
  readonly property var grid: root.editor.elements
  readonly property var element: root.editor.element
  readonly property var definition: root.editor.selected
  readonly property var views: root.definition?.module?.views ?? []
  // What the lock screen does to this definition, while it is offered there
  // ("" when it holds nothing affected): CustomWidgetData.lockIssues
  readonly property string lockWarning: {
    const issues = root.definition?.module?.lockscreen ? CustomWidgetData.lockIssues(root.definition) : [];
    const parts = [];
    if (issues.some(i => i === "actions" || i === "entry"))
      parts.push(I18n.tr("Actions and entries do nothing there."));
    if (issues.includes("text"))
      parts.push(I18n.tr("Text the script prints is readable by anyone who sees the lock screen."));
    return parts.join(" ");
  }
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

  // The keys a colour rule or Visible can read: the output's paths, for a
  // List the keys of its rows (a rule reads each row's own item, and the
  // row's `state`)
  readonly property var colorKeys: {
    if (root.element?.type !== "List")
      return root.editor.bindPaths.map(p => p.path);
    const fields = root.editor.previewFields;
    const rows = CustomWidgetData.rows(root.element.bind?.items ? CustomWidgetData.elementValue(fields, root.element.bind.items) : fields?.sample?.items, root.element.options?.row);
    const keys = Object.keys(rows.find(row => row.raw !== null && typeof row.raw === "object")?.raw ?? ({}));
    return keys.includes("state") ? keys : ["state"].concat(keys);
  }

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

  // The library and the module's own settings: what the column holds while
  // nothing is selected
  ColumnLayout {
    visible: !root.element
    Layout.fillWidth: true
    spacing: Widget.spacing * 2

    CardHeader {
      icon: "category"
      title: I18n.tr("Elements")
      showActions: false
    }

    StyledText {
      Layout.fillWidth: true
      text: I18n.tr("Drag one onto the module, or click it to add it where there's room.")
      role: "caption"
      tone: "muted"
      overflow: "wrap"
    }

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

    // The font is a setting of the module's Text elements, so it sits here
    FieldGroup {
      Layout.fillWidth: true
      title: I18n.tr("Module")

      SchemaPropertiesForm {
        Layout.fillWidth: true
        propertiesSchema: Utils.pick(ConfigManager.configSchema.definitions.CustomWidget.properties.module.properties, ["lockscreen", "font"])
        order: ["lockscreen", "font"]
        values: root.definition?.module ?? ({})
        onEdited: (path, value) => root.editor.set(["module"].concat(path), value)
      }
      // Offered on the lock screen: what doesn't work there
      Notice {
        visible: root.lockWarning !== ""
        Layout.fillWidth: true
        status: "warning"
        title: I18n.tr("On the lock screen")
        text: root.lockWarning
      }
      StyledTextButton {
        visible: root.editor.layerElements.length === 0 && root.views.length === 0
        implicitHeight: Widget.height
        iconText: "auto_awesome"
        text: I18n.tr("Start from the default layout")
        onClicked: root.editor.useDefaultElements()
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
        visible: (root.kind?.slots ?? []).length > 0
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
            model: (root.kind?.slots ?? [])

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
        headerExtras: TipIcon {
          text: "help"
          tip: I18n.tr("Never on the lock screen.")
        }

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
        Layout.fillWidth: true
        title: I18n.tr("Visible")
        headerExtras: TipIcon {
          text: "help"
          tip: I18n.tr("Show it only while a value in the output holds.")
        }

        ColumnLayout {
          id: vis
          readonly property var when: root.element?.showWhen ?? ({})
          readonly property bool on: (vis.when.test ?? "always") !== "always"
          readonly property bool needsValue: ["is", "isNot", "above", "below"].includes(vis.when.test ?? "")
          Layout.fillWidth: true
          spacing: 0

          InspectorRow {
            first: true
            label: I18n.tr("Show")

            StyledToggle {
              Layout.fillWidth: true
              options: ["always", "when"]
              labels: ({
                  "always": I18n.tr("Always"),
                  "when": I18n.tr("When")
                })
              value: vis.on ? "when" : "always"
              onPicked: value => root.editor.setElement(["showWhen", "test"], value === "always" ? "always" : "is")
            }
          }

          InspectorRow {
            indented: true
            shown: vis.on

            KeyField {
              Layout.fillWidth: true
              keys: root.colorKeys
              value: vis.when.key ?? ""
              onPicked: value => root.editor.setElement(["showWhen", "key"], value)
            }
          }

          InspectorRow {
            indented: true
            shown: vis.on

            RowLayout {
              Layout.fillWidth: true
              spacing: Widget.spacing

              StyledComboEntry {
                Layout.preferredWidth: Widget.px(120)
                Layout.fillWidth: !vis.needsValue
                value: vis.when.test ?? "always"
                options: root.editor.ruleTests.concat([
                  {
                    "value": "set",
                    "label": I18n.tr("has a value")
                  },
                  {
                    "value": "unset",
                    "label": I18n.tr("is empty")
                  }
                ])
                // Always has no row of its own: the toggle above is its place
                onPicked: value => root.editor.setElement(["showWhen", "test"], value)
              }

              StyledTextEntry {
                id: whenValue
                visible: vis.needsValue
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                placeholderText: I18n.tr("Value")
                onTextEdited: root.editor.setElement(["showWhen", "value"], whenValue.text)
                Binding {
                  target: whenValue
                  property: "text"
                  value: vis.when.value ?? ""
                  when: !whenValue.input.activeFocus
                  restoreMode: Binding.RestoreNone
                }
              }
            }
          }
        }
      }

      FieldGroup {
        visible: (root.kind?.colors.length ?? 0) > 0
        Layout.fillWidth: true
        title: I18n.tr("Colors")
        headerExtras: TipIcon {
          text: "help"
          tip: I18n.tr("Pick a color, or turn on Color by state to pick it from a value.")
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          // By count over the kind's colours (the schema's)
          Repeater {
            model: root.kind?.colors ?? []

            ColorField {
              id: color
              required property var modelData
              required property int index
              readonly property var schema: root.kind?.options?.[color.modelData.key] ?? ({})
              first: color.index === 0
              key: color.modelData.key
              statesKey: color.modelData.statesKey
              label: I18n.tr(color.schema.title ?? "")
              description: color.schema.description ? I18n.tr(color.schema.description) : ""
              emptyLabel: color.schema["x-emptyLabel"] ?? "Auto"
              value: root.element?.options?.[color.key] ?? ""
              statesValue: root.element?.options?.[color.statesKey] ?? ({})
              keys: root.colorKeys
              write: (path, value) => root.editor.setElement(["options"].concat(path), value)
            }
          }
        }
      }

      FieldGroup {
        visible: (root.kind?.lookOrder.length ?? 0) > 0
        Layout.fillWidth: true
        title: I18n.tr("Look")

        SchemaPropertiesForm {
          Layout.fillWidth: true
          propertiesSchema: Utils.pick(root.kind?.options ?? ({}), order)
          order: root.kind?.lookOrder ?? []
          values: root.element?.options ?? ({})
          onEdited: (path, value) => root.editor.setElement(["options"].concat(path), value)
        }
      }

      StyledTextButton {
        Layout.alignment: Qt.AlignRight
        implicitHeight: Widget.height
        kind: "text"
        text: I18n.tr("More in Help")
        onClicked: root.editor.openHelp("text")
      }
    }
  }
}
