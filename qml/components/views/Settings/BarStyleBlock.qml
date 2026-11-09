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
// page's Bar style card, Bars.style's `x-row`). Its sections, by the
// schema's `x-group`s: Look full width, its rows marked
// `x-keepsPlace` (the style, then the shape and grouping beside it) kept
// in place, greyed with why while they don't apply, and under them the
// rows placed there (`x-placeUnder`: tab sides, ends); then the chosen style's own
// options in one panel (Look's other fields). Every other row shows only
// while its `x-showIf` holds. Then Colors, Accents, Size and Shadow, one
// under another; on the settings page each a fold, shut until opened.
// Each look tile shows its look (BarLookSample). It holds no style rules:
// what shows, greys and why is the schema's. Edits leave through
// `edited`; on the settings page (given `row` and `form`) they go
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
  // The bar whose spacing the tiles take
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

  onEdited: (path, value) => {
    if (root.form)
      root.form.edit(root.row.path.concat(path), value);
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

  // Each tile's preview: the look with the tile's value (BarLookSample),
  // over a copy of the values (the settings draft changes its own in
  // place, so the tiles could never tell an edit had changed them)
  readonly property var _sampleValues: Utils.clone(root.values)
  readonly property var _tilePreview: path => ({
        "component": sample,
        "properties": {
          "key": path[0],
          "values": root._sampleValues,
          "bar": root.bar
        }
      })

  Component {
    id: sample
    BarLookSample {}
  }

  Layout.fillWidth: true
  spacing: Widget.spacing * 2

  // A jump made before it was built (a link from another category)
  Component.onCompleted: root._openFoldFor(SettingsManager.pendingJump)

  // One section: its heading (with the bar's own switch) and its form;
  // with `folds`, a fold instead, its form built only while open
  component Section: ColumnLayout {
    id: piece

    property string title: ""
    // The heading's text, else the title's
    property string heading: ""
    property var keys: []
    // A fold, shut until opened (kept with the page's folds), and open in
    // search results and the changed list
    property bool folds: false
    readonly property string foldKey: root.row ? root.row.path.join(".") + ":" + piece.title : ""
    readonly property bool open: !piece.folds || root.form?.listing === true || SettingsManager.isFoldOpen(piece.foldKey)
    // The bar editor's section the bar doesn't own: its heading and where
    // it's set, no form
    readonly property bool shared: root.owned !== null && root.owned[piece.title] !== true
    // Whether it's shown here (not `visible`, false while an ancestor is
    // hidden: the form would be rebuilt each time)
    property bool shown: root.sections.includes(piece.title)

    visible: piece.shown
    Layout.fillWidth: true
    spacing: Widget.spacing

    FoldHeader {
      visible: piece.folds
      title: I18n.tr(piece.title)
      collapsed: !piece.open
      // Shut, a dot while any of its settings has an unsaved edit
      marked: piece.keys.some(key => root.changedAt?.([key]) === true)
      onToggled: SettingsManager.setFoldOpen(piece.foldKey, !piece.open)
    }

    RowLayout {
      visible: !piece.folds
      Layout.fillWidth: true
      spacing: Widget.spacing * 2

      SectionHeading {
        title: piece.heading !== "" ? piece.heading : I18n.tr(piece.title)
      }

      // (Not on the style's options: they're Look's too)
      SchemaSwitch {
        visible: root.owned !== null && piece.heading === ""
        Layout.fillWidth: false
        label: I18n.tr("This bar's own")
        checked: root.owned?.[piece.title] === true
        onToggled: value => root.ownToggled(piece.title, value)
      }
    }

    // Owned, but some of its keys still shared: they can all be the bar's
    RowLayout {
      visible: !piece.shared && piece.heading === "" && root.partlyOwned?.[piece.title] === true
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
        onClicked: root.ownAllRequested(piece.title)
      }
    }

    // Where the shared values are set: the settings page's Bar style card
    RowLayout {
      visible: piece.shared && piece.heading === ""
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
        setting: "Bars.style." + (piece.keys[0] ?? "")
        text: I18n.tr("{0} in {1}", I18n.tr(piece.title), I18n.tr(sharedLink.target?.category ?? ""))
      }
    }

    FoldingColumn {
      id: body
      open: piece.open
      Layout.fillWidth: true

      // Built only while the section is edited here (and open, or still
      // folding shut). Hidden when not built: an unloaded Loader keeps
      // its last height, which left a gap where a section's form had been
      Loader {
        Layout.fillWidth: true
        active: !piece.shared && piece.shown && body.shown
        visible: active
        sourceComponent: SchemaPropertiesForm {
          propertiesSchema: piece.keys.reduce((schema, key) => {
            schema[key] = root._properties[key];
            return schema;
          }, {})
          order: piece.keys
          keepsPlace: true
          values: root.values
          changedAt: root.changedAt
          tilePreview: root._tilePreview
          onEdited: (path, value) => root.edited(path, value)
          onDiscardAt: path => root.discardAt(path)
        }
      }
    }
  }

  // A jump to a setting in a shut fold (a link, Changed from default)
  // opens it first
  function _openFoldFor(jump) {
    if (!root.row || !jump?.setting)
      return;
    const path = jump.setting;
    const base = root.row.path;
    if (path.length <= base.length || base.some((key, index) => path[index] !== key))
      return;
    const title = root._groups.find(group => group.keys.includes(path[base.length]))?.title ?? "";
    if (root._folding.includes(title))
      SettingsManager.setFoldOpen(base.join(".") + ":" + title, true);
  }
  // The sections that fold: all but Look, on the settings page
  readonly property var _folding: root.owned === null ? ["Colors", "Accents", "Size", "Shadow"] : []

  Connections {
    target: SettingsManager
    function onJumpRequested() {
      root._openFoldFor(SettingsManager.pendingJump);
    }
  }

  Section {
    title: "Look"
    keys: root._top
  }

  // The chosen style's own options, those that apply
  Section {
    shown: root._hasOptions && root.sections.includes("Look") && root.owned?.Look !== false
    title: "Look"
    heading: I18n.tr("{0} options", root._styleLabel)
    keys: root._options
  }

  Repeater {
    model: ["Colors", "Accents", "Size", "Shadow"]

    delegate: Section {
      required property string modelData
      title: modelData
      keys: root._keysOf(modelData)
      folds: root._folding.includes(modelData)
    }
  }
}
