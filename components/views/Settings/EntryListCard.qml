pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.ui
import qs.components.forms
import qs.components.methods
import qs.components.reusable

// A section's list of entries as one card (the Dock and OSD `x-card`s):
// the entries as tabs, one shown at a time: where it sits (a screen picker
// with `presets`), Show, Duplicate and Delete, then `entryContent` and its
// settings. Edits go through the settings draft like any other row (the
// list as one value), so they show live and wait for Save. Folds like the
// generated cards, under `foldKey`.
FoldingCard {
  id: root

  // Where the list is: config[section][listKey], each item a
  // definitions[entryType]
  required property string sectionKey
  required property string listKey
  required property string entryType
  // The list as saved (the reader's), until the draft has one
  required property var savedEntries
  // The settings group key it folds under, from SettingsContent
  property string foldKey
  // [{ label, values, x, y }]: a dot at (x, y) on the screen (0-1 from the
  // top left) that applies `values`. An entry on a screen edge (`edge`,
  // `position` along it), as docks and OSDs are: an edge's middle, or the
  // bottom edge's ends.
  // I18n.tr("Bottom") I18n.tr("Bottom left") I18n.tr("Bottom right") I18n.tr("Top")
  // I18n.tr("Left") I18n.tr("Right")
  property var presets: [
    {
      "label": "Bottom",
      "values": {
        "edge": "bottom",
        "position": 50
      },
      "x": 0.5,
      "y": 1
    },
    {
      "label": "Bottom left",
      "values": {
        "edge": "bottom",
        "position": 0
      },
      "x": 0.08,
      "y": 1
    },
    {
      "label": "Bottom right",
      "values": {
        "edge": "bottom",
        "position": 100
      },
      "x": 0.92,
      "y": 1
    },
    {
      "label": "Top",
      "values": {
        "edge": "top",
        "position": 50
      },
      "x": 0.5,
      "y": 0
    },
    {
      "label": "Left",
      "values": {
        "edge": "left",
        "position": 50
      },
      "x": 0,
      "y": 0.5
    },
    {
      "label": "Right",
      "values": {
        "edge": "right",
        "position": 50
      },
      "x": 1,
      "y": 0.5
    }
  ]
  // What the picker's hint says
  property string pickerHint
  // A new entry: `idBase` numbered, over `seed`, over the schema defaults
  property string idBase
  property var seed: ({})
  // Functions: an entry's tab name, and where it sits on the screen (0-1
  // from the top left): by default at `position` % along its `edge`
  required property var labelOf
  property var spotOf: entry => ScreenEdge.edgeSpot(entry.edge, entry.position / 100, 0)
  // Between the picker and the settings
  property alias entryContent: entrySlot.data

  // Show was clicked for the entry with this id
  signal show(string id)

  readonly property var entrySchema: ConfigManager.configSchema.definitions[root.entryType]
  readonly property var entries: SettingsManager.localConfig?.[root.sectionKey]?.[root.listKey] ?? root.savedEntries
  property int selected: 0
  readonly property int current: Math.max(0, Math.min(root.selected, root.entries.length - 1))
  readonly property var entry: root.entries[root.current] ?? null
  readonly property point spot: root.entry ? root.spotOf(root.entry) : Qt.point(0.5, 0.5)

  collapsed: SettingsManager.isCollapsed(root.foldKey)
  onToggled: SettingsManager.setCollapsed(root.foldKey, !root.collapsed)

  function _commit(entries) {
    SettingsManager.setValue([root.sectionKey, root.listKey], entries);
  }

  function _freeId(base) {
    return Utils.freeId(base, root.entries.map(entry => entry.id));
  }

  // Merges `values` into the shown entry
  function edit(values) {
    const entries = Utils.clone(root.entries);
    Object.assign(entries[root.current], values);
    root._commit(entries);
  }

  function add() {
    const entries = Utils.clone(root.entries);
    entries.push(SchemaValidation.applyDefaults(Object.assign(Utils.clone(root.seed), {
      "id": root._freeId(root.idBase)
    }), root.entrySchema, ConfigManager.configSchema));
    root._commit(entries);
    root.selected = entries.length - 1;
  }

  function duplicate() {
    const entries = Utils.clone(root.entries);
    const copy = Utils.clone(root.entry);
    copy.id = root._freeId(copy.id);
    entries.splice(root.current + 1, 0, copy);
    root._commit(entries);
    root.selected = root.current + 1;
  }

  function remove() {
    if (root.entries.length <= 1)
      return;
    const entries = Utils.clone(root.entries);
    entries.splice(root.current, 1);
    root._commit(entries);
    root.selected = Math.min(root.current, entries.length - 1);
  }

  headerExtras: StyledTextButton {
    implicitHeight: Widget.height - Widget.px(4)
    iconText: "add"
    text: I18n.tr("Add")
    onClicked: root.add()
  }

  // One tab per entry
  Flow {
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    Repeater {
      model: root.entries.length

      delegate: SegmentButton {
        id: tab
        required property int index
        readonly property var entry: root.entries[tab.index]

        implicitHeight: Widget.height - Widget.px(4)
        text: root.labelOf(tab.entry)
        opacity: tab.entry.enabled ? 1 : 0.6
        active: tab.index === root.current
        onClicked: root.selected = tab.index
      }
    }
  }

  RowLayout {
    visible: root.entry !== null
    Layout.fillWidth: true
    spacing: Widget.spacing * 2

    // The screen, with the shown entry's spot, the presets to click and a
    // drag to place it on an edge
    ScreenSpotPicker {
      Layout.alignment: Qt.AlignTop
      presets: root.presets
      spot: root.spot
      edge: root.entry?.edge ?? "bottom"
      onPicked: values => root.edit(values)
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignTop
      spacing: Widget.spacing

      StyledText {
        text: root.pickerHint
        textColor: Theme.foregroundAlt
        textSize: Appearance.fontSizeBy(-2)
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }

      Flow {
        Layout.fillWidth: true
        spacing: Widget.spacing / 2

        StyledTextButton {
          implicitHeight: Widget.height - Widget.px(4)
          iconText: "visibility"
          text: I18n.tr("Show")
          onClicked: root.show(root.entry.id)
        }

        StyledTextButton {
          implicitHeight: Widget.height - Widget.px(4)
          iconText: "content_copy"
          text: I18n.tr("Duplicate")
          onClicked: root.duplicate()
        }

        StyledTextButton {
          visible: root.entries.length > 1
          implicitHeight: Widget.height - Widget.px(4)
          iconText: "delete"
          text: I18n.tr("Delete")
          hoverColor: Theme.error
          onClicked: root.remove()
        }
      }
    }
  }

  StyledSeparator {
    separatorColor: Theme.accent
    visible: root.entry !== null
    Layout.fillWidth: true
  }

  ColumnLayout {
    id: entrySlot
    visible: root.entry !== null && children.length > 0
    Layout.fillWidth: true
    spacing: Widget.spacing * 1.5
  }

  SchemaPropertiesForm {
    visible: root.entry !== null
    Layout.fillWidth: true
    propertiesSchema: root.entrySchema.properties
    order: root.entrySchema["x-order"] ?? []
    values: root.entry ?? ({})
    onEdited: (path, value) => root.edit({
        [path[0]]: value
      })
  }
}
