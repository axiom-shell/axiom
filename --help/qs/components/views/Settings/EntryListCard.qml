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
// the entries as tabs, one shown at a time: where it sits (the screen
// picker every placed surface has, ScreenSpotPicker), Show, Duplicate and
// Delete, then `entryContent` and its other settings. Fields the entry's
// schema groups (`x-group`) fold by group: the first under the picker,
// the others beside them (a `wide` card with the room: SplitColumns) or
// stacked under them, `entryContent` below; an entry with no groups shows
// its form as it is, last.
// Edits go through the settings draft like any other row (the list as
// one value), so they show live and wait for Save. Folds like the
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
  // What the picker's hint says
  property string pickerHint
  // A new entry: `idBase` numbered, over `seed`, over the schema defaults
  property string idBase
  property var seed: ({})
  // Functions: an entry's tab name, and where it sits on the screen (0-1
  // from the top left): `position` % along its `edge`, and held off it
  // (`detached`) `distance` % across
  required property var labelOf
  property var spotOf: entry => ScreenEdge.edgeSpot(entry.edge, entry.position / 100, entry.detached ? entry.distance / 100 : 0)
  // Between the picker and the settings
  property alias entryContent: entrySlot.data
  // Keys `entryContent` edits itself, left out of the other settings (an
  // OSD's systems and its bars' layout)
  property var ownKeys: []
  // Spans the page (a wide `x-card`): with the room, the picker and its
  // group, and the other groups, go side by side at the top
  property bool wide: false
  // Buttons in the header before Add (the OSD's Preview)
  property alias headerButtons: headerSlot.data

  // Show was clicked for the entry with this id
  signal show(string id)

  readonly property var entrySchema: ConfigManager.configSchema.definitions[root.entryType]
  readonly property var entries: SettingsManager.localConfig?.[root.sectionKey]?.[root.listKey] ?? root.savedEntries
  property int selected: 0
  readonly property int current: Math.max(0, Math.min(root.selected, root.entries.length - 1))
  readonly property var entry: root.entries[root.current] ?? null
  readonly property point spot: root.entry ? root.spotOf(root.entry) : Qt.point(0.5, 0.5)
  // The other settings by their `x-group`s ([{ title, keys, schema }],
  // SchemaLayout.objectGroups), each a fold; [] when the schema groups none
  readonly property var _groups: {
    const groups = SchemaLayout.objectGroups(root.entrySchema, root.ownKeys);
    return groups.some(group => group.title !== "Other") ? groups : [];
  }

  collapsed: SettingsManager.isCollapsed(root.foldKey)
  onToggled: SettingsManager.setCollapsed(root.foldKey, !root.collapsed)

  function _commit(entries) {
    SettingsManager.setValue([root.sectionKey, root.listKey], entries);
  }

  // The list as it is now, a copy to edit: read from the draft at call
  // time, since the typed text EditsManager.commitTyping writes reaches
  // `entries` only a tick later (ConfigDraft.changed)
  function _entriesNow() {
    return Utils.clone(SettingsManager.localConfig?.[root.sectionKey]?.[root.listKey] ?? root.savedEntries);
  }

  function _freeId(base, entries) {
    return Utils.freeId(base, entries.map(entry => entry.id));
  }

  // Merges `values` into the shown entry
  function edit(values) {
    const entries = root._entriesNow();
    Object.assign(entries[root.current], values);
    root._commit(entries);
  }

  function add() {
    // The typed text in the selected one's form, while it's still selected
    EditsManager.commitTyping();
    const entries = root._entriesNow();
    entries.push(SchemaValidation.applyDefaults(Object.assign(Utils.clone(root.seed), {
      "id": root._freeId(root.idBase, entries)
    }), root.entrySchema, ConfigManager.configSchema));
    root._commit(entries);
    root.selected = entries.length - 1;
  }

  function duplicate() {
    // The typed text in the selected one's form, while it's still selected
    EditsManager.commitTyping();
    const entries = root._entriesNow();
    const copy = Utils.clone(entries[root.current]);
    copy.id = root._freeId(copy.id, entries);
    entries.splice(root.current + 1, 0, copy);
    root._commit(entries);
    root.selected = root.current + 1;
  }

  function remove() {
    if (root.entries.length <= 1)
      return;
    // The typed text in the selected one's form, while it's still selected
    EditsManager.commitTyping();
    const entries = root._entriesNow();
    entries.splice(root.current, 1);
    root._commit(entries);
    root.selected = Math.min(root.current, entries.length - 1);
  }

  headerExtras: RowLayout {
    spacing: Widget.spacing / 2

    RowLayout {
      id: headerSlot
      spacing: Widget.spacing / 2
    }

    StyledTextButton {
      implicitHeight: Widget.height - Widget.px(4)
      iconText: "add"
      text: I18n.tr("Add")
      onClicked: root.add()
    }
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
        onClicked: {
          EditsManager.commitTyping();
          root.selected = tab.index;
        }
      }
    }
  }

  // The picker and the first group under it, and beside them with the
  // room the other groups
  SplitColumns {
    id: placeRow
    visible: root.entry !== null
    minWidth: root.wide ? Widget.px(720) : Infinity
    share: 0.45

    ColumnLayout {
      Layout.preferredWidth: placeRow.firstWidth
      Layout.alignment: Qt.AlignTop
      spacing: placeRow.rowSpacing

      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing * 2

        // The screen, with the shown entry's spot, the presets to click and a
        // drag to place it on an edge
        ScreenSpotPicker {
          Layout.alignment: Qt.AlignTop
          floats: true
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

      GroupFold {
        visible: root.entry !== null && root._groups.length > 0
        group: root._groups[0] ?? null
      }
    }

    ColumnLayout {
      visible: root.entry !== null && root._groups.length > 1
      Layout.preferredWidth: placeRow.secondWidth
      Layout.alignment: Qt.AlignTop
      spacing: placeRow.rowSpacing

      Repeater {
        model: root._groups.slice(1)

        delegate: GroupFold {
          required property var modelData
          group: modelData
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

  // A group of the entry's settings, folding under its title
  component GroupFold: FoldingSection {
    id: fold
    property var group: null
    readonly property string foldKey: root.foldKey + ":" + (fold.group?.title ?? "")
    Layout.fillWidth: true
    // The group's title is its `x-group`, read by check_i18n from the schema
    title: I18n.tr(fold.group?.title ?? "")
    collapsed: SettingsManager.isCollapsed(fold.foldKey)
    onToggled: SettingsManager.setCollapsed(fold.foldKey, !fold.collapsed)

    SchemaPropertiesForm {
      Layout.fillWidth: true
      propertiesSchema: fold.group?.schema ?? ({})
      order: fold.group?.keys ?? []
      // The whole entry, so x-showIf sees keys from other groups
      values: root.entry ?? ({})
      onEdited: (path, value) => root.edit({
          [path[0]]: value
        })
    }
  }

  // An entry with no groups: its other settings as they are
  Loader {
    active: root.entry !== null && root._groups.length === 0
    visible: active
    Layout.fillWidth: true
    sourceComponent: SchemaPropertiesForm {
      propertiesSchema: Object.keys(root.entrySchema.properties).filter(key => !root.ownKeys.includes(key)).reduce((out, key) => {
        out[key] = root.entrySchema.properties[key];
        return out;
      }, {})
      order: root.entrySchema["x-order"] ?? []
      values: root.entry ?? ({})
      onEdited: (path, value) => root.edit({
          [path[0]]: value
        })
    }
  }
}
