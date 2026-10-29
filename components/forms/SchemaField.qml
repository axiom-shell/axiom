pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.core
import qs.services.compositor
import qs.services.system
import qs.services.ui
import qs.services.apps
import qs.components.methods
import qs.components.reusable

// i18n: keys from callers and the schema (titles, descriptions, type labels)
// One row of a schema-driven form: picks the control for the row's schema
// type (or a list editor for an array of objects), hidden while its
// `x-showIf` doesn't hold. `form` provides valueAt(path) and
// edit(path, value) (SchemaPropertiesForm, SettingRows, or the settings
// page's SettingsContent).
Loader {
  id: root

  required property var row
  required property var form
  // Shown after the field's label (SettingsField's unsaved dot and reset)
  property Component headerExtra: null

  readonly property var fieldSchema: row.schema ?? ({})
  readonly property var current: form?.valueAt(row.path)
  // Null on a setting marked `x-inherit`: it follows another, shown here
  readonly property bool inheriting: root.current === null && !!fieldSchema["x-inherit"]
  // A row may relabel its field (`x-card.perField`'s, whose card carries
  // the title and description)
  readonly property string label: row.label ?? row.title
  readonly property string description: {
    const own = row.description ?? fieldSchema.description ?? "";
    // I18n.tr("Follows {0} until set.")
    const follows = root.inheriting ? I18n.tr("Follows {0} until set.", I18n.tr(SettingsManager.schemaAt(fieldSchema["x-inherit"].split("."))?.title ?? fieldSchema["x-inherit"])) : "";
    const notes = [root.disabledNote, follows].filter(note => note !== "").join("\n");
    if (notes === "")
      return own;
    return own !== "" ? notes + "\n" + I18n.tr(own) : notes;
  }
  readonly property bool isColor: fieldSchema["x-options"] === "colors"
  // `x-enumShowIf` hides options whose condition doesn't hold (the current
  // value stays listed)
  readonly property var options: {
    const all = SettingsManager.optionsFor(fieldSchema);
    const conditions = fieldSchema["x-enumShowIf"];
    if (!all || !conditions)
      return all;
    return all.filter(value => value === root.current || SchemaLayout.showIfHolds(conditions[value], root._valueOf));
  }
  // Labels shown for option values (`x-enumLabels`, or language names)
  readonly property var optionLabels: {
    if (fieldSchema["x-options"] === "languages")
      return I18n.languages.reduce((labels, l) => {
        labels[l.code] = l.name;
        return labels;
      }, {});
    if (fieldSchema["x-options"] === "edgeMenus")
      return EdgeMenusConfig.menus.reduce((labels, menu) => {
        labels[menu.id] = menu.name || menu.id;
        return labels;
      }, {});
    if (fieldSchema["x-options"] === "customWidgets")
      return CustomWidgetsConfig.items.reduce((labels, item) => {
        labels[item.id] = item.name || item.id;
        return labels;
      }, {});
    if (fieldSchema["x-options"] === "overlayPages")
      return OverlayConfig.views.reduce((labels, view, index) => {
        const key = OverlayConfig.pageKey(view);
        if (key !== "")
          labels[key] = OverlayConfig.viewLabel(view, index);
        return labels;
      }, {});
    // An empty monitor is the primary one, except in the primary monitor's
    // own field (`x-emptyLabel`). I18n.tr("First screen")
    if (fieldSchema["x-options"] === "screens")
      return {
        "": I18n.tr(fieldSchema["x-emptyLabel"] ?? "Primary monitor"),
        "*": I18n.tr("All monitors")
      };
    if (fieldSchema["x-options"] === "notes")
      return {
        "": I18n.tr("Last opened")
      };
    // I18n.tr("The first calendar")
    if (fieldSchema["x-options"] === "calendars")
      return CalendarManager.calendars.reduce((labels, calendar) => {
        labels[calendar.id] = CalendarConfig.accounts.length > 1 ? I18n.tr("{0} · {1}", calendar.name, calendar.accountName) : calendar.name;
        return labels;
      }, {
        "": I18n.tr(fieldSchema["x-emptyLabel"] ?? "The first calendar")
      });
    // Schema labels are English, translated like titles; `x-emptyLabel`
    // names an empty value (a color picked automatically: I18n.tr("Auto"))
    // An enum value without a label shows as words (Utils.enumLabel)
    const values = fieldSchema.enum ?? fieldSchema.items?.enum ?? [];
    const labels = Object.assign(Array.prototype.reduce.call(values, (out, value) => {
      out[value] = Utils.enumLabel(value);
      return out;
    }, {}), fieldSchema["x-enumLabels"] ?? {});
    if (fieldSchema["x-emptyLabel"])
      labels[""] = fieldSchema["x-emptyLabel"];
    const out = Object.keys(labels).reduce((out, value) => {
      out[value] = I18n.tr(labels[value]);
      return out;
    }, {});
    // A color without Auto marks its default, listed first
    if (root.isColor && !fieldSchema["x-emptyLabel"] && fieldSchema.default)
      out[fieldSchema.default] = I18n.tr("{0} (default)", fieldSchema.default);
    return out;
  }

  // A sibling key of this row's path (dotted, or climbing with `../`:
  // SchemaLayout.keyPath), or a `/`-rooted config path, or a `$` key from
  // the form's `context`, for `x-showIf` and `x-enumShowIf`, in any form
  function _valueOf(key) {
    return root._valueFrom(root.row.path.slice(0, -1), key);
  }

  function _valueFrom(parent, key) {
    if (key.startsWith("/"))
      return SettingsManager.configValueAt(key.slice(1));
    if (key.startsWith("$"))
      return root.form?.context?.[key];
    return root.form?.valueAt(SchemaLayout.keyPath(parent, key));
  }

  // `x-showIf` (a group row's object's own), and those of the objects the
  // row is inside (`groupShowIf`), checked against _valueOf
  readonly property bool shown: SchemaLayout.showIfHolds(row.kind === "group" ? row.showIf : fieldSchema["x-showIf"], root._valueOf) && (row.groupShowIf ?? []).every(outer => SchemaLayout.showIfHolds(outer.condition, key => root._valueFrom(outer.path, key)))

  // `x-enabledIf` (as x-showIf): while it doesn't hold the row is greyed
  // out, its value kept, and says why (`x-disabledNote`, else what the
  // compositor can't do, CompositorManager.unsupportedNote). Only a row
  // shown on its own says it: one shown by a sibling (a part's fields,
  // under its switch) is greyed with it, without repeating it.
  readonly property string _blockedBy: SchemaLayout.failingKey(fieldSchema["x-enabledIf"], root._valueOf)
  readonly property bool allowed: _blockedBy === ""
  // Shown by a sibling's value (a part's fields, under its switch)
  readonly property bool followsSibling: Object.keys(fieldSchema["x-showIf"] ?? {}).some(key => !key.startsWith("/"))
  // I18n.tr("{0} only.")
  readonly property string disabledNote: {
    // (A field one compositor alone has says so even under its part's
    // switch: the switch itself isn't greyed out for it)
    if (root.allowed || (root.followsSibling && _blockedBy !== "/$compositor"))
      return "";
    // false: none (the section's intro says why)
    const own = fieldSchema["x-disabledNote"] ?? "";
    if (own === false)
      return "";
    if (own !== "")
      return I18n.tr(own);
    if (_blockedBy.startsWith("/$supports."))
      return CompositorManager.unsupportedNote(_blockedBy.slice("/$supports.".length));
    if (_blockedBy === "/$compositor")
      return I18n.tr("{0} only.", CompositorManager.nameOf(String(fieldSchema["x-enabledIf"]["/$compositor"])));
    return "";
  }

  visible: shown
  enabled: allowed
  opacity: allowed ? 1 : 0.5

  Layout.fillWidth: true

  function commit(value) {
    // Arrays (a string list) are new each time: compare their contents
    const same = Array.isArray(value) ? JSON.stringify(value) === JSON.stringify(root.current) : value === root.current;
    // A typed number commits as it loses focus, which can be as its form
    // is torn down
    if (!same && root.form)
      root.form.edit(root.row.path, value);
  }

  // A text or number box's keystroke, for a form with `typed` (the
  // settings page) to hold as unsaved without applying it. Others apply
  // it on commit (the box shows Save meanwhile: EditsManager.holdTyping)
  function type(value) {
    if (root.form && typeof root.form.typed === "function")
      root.form.typed(root.row.path, value);
  }

  // A typed commit (Enter, focus loss, Save): always passed on, since
  // `typed` may have put the value in already
  function commitTyped(value) {
    if (root.form)
      root.form.edit(root.row.path, value);
  }

  // Array rows: every edit commits a modified copy of the whole array
  function _arrayCopy() {
    return Utils.clone(root.current ?? []);
  }

  function addItem() {
    const items = _arrayCopy();
    items.push(SchemaValidation.applyDefaults({}, root.fieldSchema.items, ConfigManager.configSchema));
    root.commit(items);
  }

  function removeItem(index) {
    const items = _arrayCopy();
    items.splice(index, 1);
    root.commit(items);
  }

  function moveItem(from, to) {
    const items = _arrayCopy();
    items.splice(to, 0, items.splice(from, 1)[0]);
    root.commit(items);
  }

  function editItem(index, key, value) {
    const items = _arrayCopy();
    items[index][key] = value;
    root.commit(items);
  }

  sourceComponent: {
    if (row.kind === "group")
      return groupHeader;
    if (row.kind === "array")
      return arrayField;
    // Shown, not edited, whatever its type
    if (fieldSchema["x-control"] === "readonly")
      return readonlyField;
    switch (fieldSchema.type) {
    case "array":
      // Strings only: from a fixed set (chips), or free text
      return fieldSchema.items?.enum ? chipsField : stringListField;
    case "boolean":
      return switchField;
    case "integer":
      return fieldSchema["x-auto"] ? autoSpinField : spinField;
    default:
      // A long list (`x-control: "search"`) is typed into to filter it
      if (root.options && fieldSchema["x-control"] === "search")
        return searchField;
      return root.options ? comboField : textField;
    }
  }

  Component {
    id: groupHeader
    StyledText {
      text: I18n.tr(root.label)
      font.bold: true
      textColor: Theme.accent
      topPadding: Widget.spacing
    }
  }

  Component {
    id: switchField
    SchemaSwitch {
      label: root.label
      description: root.description
      headerExtra: root.headerExtra
      checked: root.current === true
      onToggled: value => root.commit(value)
    }
  }

  Component {
    id: spinField
    SchemaNumberField {
      label: root.label
      description: root.description
      currentConfigValue: root.current ?? SettingsManager.inheritedValue(root.fieldSchema) ?? 0
      minimum: root.fieldSchema.minimum ?? 0
      maximum: root.fieldSchema.maximum ?? 9999
      stepSize: root.fieldSchema.multipleOf ?? 1
      headerExtra: root.headerExtra
      unit: root.fieldSchema["x-unit"] ?? ""
      unitScale: SchemaLayout.unitScale(unit)
      mode: root.form?.numberMode || (root.fieldSchema["x-control"] ?? "auto")
      onValueTyped: value => root.type(value)
      onCommitted: (value, typed) => typed ? root.commitTyped(value) : root.commit(value)
    }
  }

  // An integer with an automatic value (`x-auto`: { value, start }): a
  // switch for setting it by hand, then the number. Turning it on starts
  // at `start`; off stores `value`.
  Component {
    id: autoSpinField
    ColumnLayout {
      id: autoField
      // (While the row is torn down its schema can go first)
      readonly property var auto: root.fieldSchema["x-auto"] ?? ({
          "value": 0,
          "start": 0
        })
      readonly property bool custom: root.current !== undefined && root.current !== autoField.auto.value
      spacing: Widget.spacing
      SchemaSwitch {
        label: root.label
        description: root.description
        headerExtra: root.headerExtra
        checked: autoField.custom
        onToggled: value => root.commit(value ? autoField.auto.start : autoField.auto.value)
      }
      SchemaNumberField {
        visible: autoField.custom
        label: ""
        currentConfigValue: autoField.custom ? root.current : autoField.auto.start
        minimum: Math.max(root.fieldSchema.minimum ?? 0, autoField.auto.value + 1)
        maximum: root.fieldSchema.maximum ?? 9999
        stepSize: root.fieldSchema.multipleOf ?? 1
        unit: root.fieldSchema["x-unit"] ?? ""
        unitScale: SchemaLayout.unitScale(unit)
        mode: root.form?.numberMode || (root.fieldSchema["x-control"] ?? "auto")
        onValueTyped: value => root.type(value)
        onCommitted: (value, typed) => typed ? root.commitTyped(value) : root.commit(value)
      }
    }
  }

  // A value shown, not edited (`x-control: "readonly"`), with a copy button
  Component {
    id: readonlyField
    RowLayout {
      spacing: Widget.spacing
      FieldHeader {
        label: root.label
        description: root.description
        trailing: root.headerExtra
        // Centred on a control taller than it (a label alone)
        Layout.alignment: Qt.AlignVCenter
      }
      StyledText {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        horizontalAlignment: Text.AlignRight
        text: String(root.current ?? "")
        elide: Text.ElideMiddle
        opacity: 0.8
      }
      SquareIconButton {
        Layout.alignment: Qt.AlignVCenter
        size: Widget.height - Widget.px(6)
        iconText: "content_copy"
        tooltipText: I18n.tr("Copy")
        onClicked: ClipboardManager.copyText(String(root.current ?? ""))
      }
    }
  }

  Component {
    id: comboField
    SchemaComboBox {
      label: root.label
      description: root.description
      headerExtra: root.headerExtra
      options: root.options
      optionLabels: root.optionLabels
      swatches: root.isColor
      currentValue: root.current ?? ""
      onSelectionChanged: value => root.commit(value)
    }
  }

  Component {
    id: searchField
    ColumnLayout {
      spacing: Widget.spacing
      FieldHeader {
        label: root.label
        description: root.description
        trailing: root.headerExtra
      }
      StyledComboEntry {
        Layout.fillWidth: true
        editable: true
        placeholderText: root.optionLabels[""] ?? ""
        options: root.options.map(value => ({
              "value": value,
              "label": root.optionLabels[value] ?? value
            }))
        value: root.current ?? ""
        // Only what's listed: anything else typed shows the value again
        onPicked: value => {
          if (root.options.includes(value))
            root.commit(value);
        }
      }
    }
  }

  Component {
    id: arrayField
    SchemaObjectArray {
      label: root.label
      description: root.description
      headerExtra: root.headerExtra
      items: root.current ?? []
      itemDelegate: Component {
        SchemaArrayItem {
          itemSchema: root.fieldSchema.items
          numberMode: root.form?.numberMode ?? ""
          onItemEdited: (index, key, value) => root.editItem(index, key, value)
        }
      }
      onItemAdded: root.addItem()
      onItemRemoved: index => root.removeItem(index)
      onItemMoved: (from, to) => root.moveItem(from, to)
    }
  }

  Component {
    id: textField
    SchemaTextField {
      label: root.label
      description: root.description
      headerExtra: root.headerExtra
      multiline: root.fieldSchema["x-multiline"] === true
      browse: root.fieldSchema["x-control"] === "folder" ? "folder" : ""
      // Text that doesn't match yet (a half-typed time) isn't committed
      pattern: root.fieldSchema.pattern ?? null
      suggestions: SettingsManager.suggestionsFor(root.fieldSchema)
      currentConfigValue: root.current ?? ""
      onValueTyped: value => root.type(value)
      onValueEdited: value => root.commitTyped(value)
    }
  }

  // An array of strings from `items.enum`: one toggle chip per option,
  // committed in the enum's order
  Component {
    id: chipsField
    ColumnLayout {
      spacing: Widget.spacing
      FieldHeader {
        label: root.label
        description: root.description
        trailing: root.headerExtra
      }
      Flow {
        Layout.fillWidth: true
        spacing: Widget.spacing / 2
        Repeater {
          model: root.fieldSchema.items.enum
          SegmentButton {
            id: chip
            required property string modelData
            readonly property bool selected: (root.current ?? []).includes(chip.modelData)
            text: root.optionLabels[chip.modelData] ?? I18n.tr(chip.modelData)
            active: chip.selected
            onClicked: {
              const current = root.current ?? [];
              const next = chip.selected ? current.filter(v => v !== chip.modelData) : current.concat([chip.modelData]);
              root.commit(root.fieldSchema.items.enum.filter(v => next.includes(v)));
            }
          }
        }
      }
    }
  }

  // A free array of strings, edited as a comma-separated list
  Component {
    id: stringListField
    SchemaTextField {
      label: root.label
      description: root.description
      headerExtra: root.headerExtra
      suggestions: SettingsManager.suggestionsFor(root.fieldSchema)
      commaList: true
      currentConfigValue: (root.current ?? []).join(", ")
      function listOf(value) {
        return value.split(",").map(v => v.trim()).filter(v => v !== "");
      }
      onValueTyped: value => root.type(listOf(value))
      onValueEdited: value => root.commitTyped(listOf(value))
    }
  }
}
