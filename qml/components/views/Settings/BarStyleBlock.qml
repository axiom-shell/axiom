pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.ui
import qs.components.methods
import qs.components.forms
import qs.components.reusable

// The Bar style block: every BarStyle setting in one place (the settings
// page's Bar style card, Bars.style's `x-row`). On top, a strip of the
// bar's own widgets, live, in the look being edited. Then its sections, by
// the schema's `x-group`s: Look full width, its rows marked
// `x-keepsPlace` (the style, then the shape and grouping beside it) kept
// in place, greyed with why while they don't apply, and under them the
// rows placed there (`x-placeUnder`: tab sides, ends); then the chosen style's own
// options in one panel (Look's other fields). Every other row shows only
// while its `x-showIf` holds. Then Colors and Accents,
// Size and Shadow, side by side from Widget.px(720) wide, else stacked.
// Each look tile shows its look (BarLookSample). It holds no style rules:
// what shows, greys and why is the schema's. Its header's Presets menu
// sets the values of one of the schema's presets (BarStyle's
// `x-presets`) in one edit. Edits leave through `edited` and
// `presetPicked`; on the settings page (given `row` and `form`) they go
// through the settings draft as the page's own rows' do. In the bar
// editor (`owned`) each section is the bar's own or shared: shared, it
// shows only its heading and a link to where it's set; owned with some
// keys still shared (`partlyOwned`), a line saying so and a button to own
// them all.
ColumnLayout {
  id: root

  // The settings row (SettingsField's `x-row`) and its form, handed in as
  // it loads; null elsewhere (the bar editor sets the rest itself)
  property var row: null
  property var form: null

  // The BarStyle definition, and the values edited ({ key: value }, the
  // schema's defaults for what's missing)
  property var schema: root.row?.schema ?? ConfigManager.configSchema?.definitions?.BarStyle ?? null
  property var values: root.form && root.row ? (root.form.valueAt(root.row.path) ?? ({})) : ({})
  // Whether the field at a path ([key]) has an unsaved edit (its change
  // marks), or null for none
  property var changedAt: root.row ? (path => SettingsManager.isChanged(root.row.path.concat(path))) : null
  // Per section title, whether the bar has its own (a "This bar's own"
  // switch on each section's heading), or null for none (the settings page)
  property var owned: null
  // Per section title, whether the bar owns it but some of its keys still
  // follow the shared style (one saved before the sections were these),
  // or null for none
  property var partlyOwned: null
  // The sections shown, by title (all of them unless set)
  property var sections: ["Look", "Colors", "Accents", "Size", "Shadow"]
  // The bar whose widgets the strip shows and whose spacing the tiles take
  // (an entry of Bars.items): the first bar, else a new one's defaults
  property var bar: BarsConfig.savedBars[0] ?? SchemaValidation.newItem(ConfigManager.configSchema.definitions.Bar, [], ConfigManager.configSchema)

  // A field ([key], a nested one as its whole top-level object) edited
  signal edited(var path, var value)
  // A field's unsaved-edit dot was clicked
  signal discardAt(var path)
  // A section's "This bar's own" switch (with `owned`)
  signal ownToggled(string group, bool value)
  // A partly owned section's "Make all this bar's own" (with `partlyOwned`)
  signal ownAllRequested(string group)
  // A preset picked: its values ({ key: value }, its shadow's parts as an
  // object), to set at once, keys it doesn't name kept
  signal presetPicked(var values)

  onEdited: (path, value) => {
    if (root.form)
      root.form.edit(root.row.path.concat(path), value);
  }
  // Every key at once (SettingsManager.setValues), one Discard puts back;
  // the shadow as its whole object, as the form edits it
  onPresetPicked: values => {
    if (!root.form)
      return;
    EditsManager.discardTypingIn(root);
    SettingsManager.setValues(Object.keys(values).map(key => ({
          "path": root.row.path.concat([key]),
          "value": key === "shadow" ? Object.assign({}, root._valueOf("shadow"), values.shadow) : Utils.clone(values[key])
        })));
  }
  onDiscardAt: path => {
    if (!root.row)
      return;
    EditsManager.discardTypingIn(root);
    SettingsManager.discard([root.row.path.concat(path)]);
  }

  // Its sections (SchemaLayout.objectGroups), by title. Titles:
  // I18n.tr("Look") I18n.tr("Colors") I18n.tr("Accents") I18n.tr("Size")
  // I18n.tr("Shadow")
  readonly property var _groups: root.schema ? SchemaLayout.objectGroups(root.schema, []) : []
  function _keysOf(title) {
    return root._groups.find(group => group.title === title)?.keys ?? [];
  }
  readonly property var _properties: root.schema?.properties ?? ({})
  // The presets ([{ label, values }], the schema's `x-presets`), the
  // labels English
  readonly property var _presets: root.schema?.["x-presets"] ?? []
  // Look's rows kept in place (`x-keepsPlace`, in x-order: the style, the
  // shape, the grouping), its top rows (those and the rows placed under
  // one of them, `x-placeUnder`: tab sides and ends under the shape), and
  // the rest: the style's own options
  readonly property var _kept: root._keysOf("Look").filter(key => root._properties[key]?.["x-keepsPlace"] === true)
  readonly property var _top: SchemaLayout.placedUnder(root._keysOf("Look").filter(key => root._kept.includes(key) || root._kept.includes(root._properties[key]?.["x-placeUnder"])), root._properties)
  readonly property var _options: root._keysOf("Look").filter(key => !root._top.includes(key))
  function _valueOf(key) {
    return root.values[key] ?? root._properties[key]?.default;
  }
  // Whether any of the chosen style's options applies (its `x-showIf`)
  readonly property bool _hasOptions: root._options.some(key => SchemaLayout.showIfHolds(root._properties[key]?.["x-showIf"], root._valueOf))
  // The chosen style's label: Look's first kept field's (the style)
  readonly property string _styleLabel: {
    const field = root._properties[root._kept[0]] ?? {};
    const value = root._valueOf(root._kept[0]) ?? "";
    return I18n.tr(field["x-enumLabels"]?.[value] ?? Utils.enumLabel(value));
  }

  // Each tile's preview: the look with the tile's value (BarLookSample)
  readonly property var _tilePreview: path => ({
        "component": sample,
        "properties": {
          "key": path[0],
          "values": root.values,
          "bar": root.bar
        }
      })

  Component {
    id: sample
    BarLookSample {}
  }

  Layout.fillWidth: true
  spacing: Widget.spacing * 2

  // The header: the Presets menu, at its end
  RowLayout {
    visible: root._presets.length > 0
    Layout.fillWidth: true
    spacing: Widget.spacing

    Item {
      Layout.fillWidth: true
    }

    StyledTextButton {
      id: presetsButton
      text: I18n.tr("Presets")
      iconText: "expand_more"
      iconAfter: true
      tooltipText: I18n.tr("Set a whole look at once; what it leaves out stays as it is")
      // Under it, their right edges lined up
      onClicked: presetsMenu.openAt(presetsButton, presetsButton.width - presetsMenu.width, presetsButton.height)
    }
  }

  StyledContextMenu {
    id: presetsMenu
    items: root._presets.map((preset, index) => ({
          "id": String(index),
          "text": I18n.tr(preset.label)
        }))
    onTriggered: id => root.presetPicked(root._presets[Number(id)].values)
  }

  // The bar's widgets as the look draws them
  StreamedLoader {
    Layout.fillWidth: true
    label: "bar style strip"
    wanted: root.bar !== null
    sourceComponent: BarLookSample {
      value: null
      values: root.values
      bar: root.bar
      liveConfig: BarManager.previewConfigOf(Object.assign({}, root.bar, {
        "style": root.values
      }))
    }
  }

  // One section: its heading (with the bar's own switch) and its form
  component Section: ColumnLayout {
    id: section

    property string title: ""
    // The heading's text, else the title's
    property string heading: ""
    property var keys: []
    // The bar editor's section the bar doesn't own: its heading and where
    // it's set, no form
    readonly property bool shared: root.owned !== null && root.owned[section.title] !== true

    visible: root.sections.includes(section.title)
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
    spacing: Widget.spacing

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing * 2

      SectionHeading {
        title: section.heading !== "" ? section.heading : I18n.tr(section.title)
      }

      // (Not on the style's options: they're Look's too)
      SchemaSwitch {
        visible: root.owned !== null && section.heading === ""
        Layout.fillWidth: false
        label: I18n.tr("This bar's own")
        checked: root.owned?.[section.title] === true
        onToggled: value => root.ownToggled(section.title, value)
      }
    }

    // Owned, but some of its keys still shared: they can all be the bar's
    RowLayout {
      visible: !section.shared && section.heading === "" && root.partlyOwned?.[section.title] === true
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledText {
        Layout.fillWidth: true
        text: I18n.tr("Some of these follow the shared style.")
        textColor: Theme.foreground
        opacity: 0.7
        wrapMode: Text.WordWrap
      }

      StyledTextButton {
        text: I18n.tr("Make all this bar's own")
        onClicked: root.ownAllRequested(section.title)
      }
    }

    // Where the shared values are set: the settings page's Bar style card
    RowLayout {
      visible: section.shared && section.heading === ""
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledText {
        text: I18n.tr("Shared with every bar.")
        textColor: Theme.foreground
        opacity: 0.7
      }

      SettingsLink {
        id: sharedLink
        Layout.fillWidth: true
        setting: "Bars.style." + (section.keys[0] ?? "")
        text: I18n.tr("{0} in {1}", I18n.tr(section.title), I18n.tr(sharedLink.target?.category ?? ""))
      }
    }

    // Built only while the section is edited here
    Loader {
      Layout.fillWidth: true
      active: !section.shared && section.visible
      sourceComponent: SchemaPropertiesForm {
        propertiesSchema: section.keys.reduce((schema, key) => {
          schema[key] = root._properties[key];
          return schema;
        }, {})
        order: section.keys
        // Side by side only as wide as the two columns (not the bar
        // editor's panel): the tiles keep their room
        pairs: root.width >= Widget.px(720)
        keepsPlace: true
        values: root.values
        changedAt: root.changedAt
        tilePreview: root._tilePreview
        onEdited: (path, value) => root.edited(path, value)
        onDiscardAt: path => root.discardAt(path)
      }
    }
  }

  Section {
    title: "Look"
    keys: root._top
  }

  // The chosen style's own options, those that apply
  Section {
    visible: root._hasOptions && root.sections.includes("Look") && root.owned?.Look !== false
    title: "Look"
    heading: I18n.tr("{0} options", root._styleLabel)
    keys: root._options
  }

  SplitColumns {
    id: columns
    minWidth: Widget.px(720)
    share: 0.5

    Section {
      Layout.preferredWidth: columns.firstWidth
      title: "Colors"
      keys: root._keysOf("Colors")
    }

    Section {
      Layout.preferredWidth: columns.secondWidth
      title: "Accents"
      keys: root._keysOf("Accents")
    }

    Section {
      Layout.preferredWidth: columns.firstWidth
      title: "Size"
      keys: root._keysOf("Size")
    }

    Section {
      Layout.preferredWidth: columns.secondWidth
      title: "Shadow"
      keys: root._keysOf("Shadow")
    }
  }
}
