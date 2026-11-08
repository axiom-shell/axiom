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
// Delete, then `entryContent`, its `sections` (each a folding part of its
// own; `lastSections` after the rest) and its other settings (folding
// under `otherTitle` when it has one). A `wide` card with the room puts
// the picker and the other settings' fold side by side at the top
// (SplitColumns), `entryContent` under both; narrow, they stack as usual.
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
  // Keys of object settings each shown as a folding part of its own, titled
  // and described by its schema, before the others (an OSD's bars, status
  // icons and now playing). Their fields' `x-showIf` reach the entry's own
  // through `../`
  property var sections: []
  // Of `sections`, those shown after the other settings, at the bottom
  property var lastSections: []
  // Keys `entryContent` edits itself, left out of the other settings (an
  // OSD's systems)
  property var ownKeys: []
  // Titles the entry's other settings, folding under it; "" shows them
  // as they are
  property string otherTitle
  // Spans the page (a wide `x-card`): with the room, the picker and the
  // other settings' fold go side by side at the top
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
  // The other settings fold under `otherTitle`, and sit beside the picker
  readonly property bool _otherFolds: root.otherTitle !== ""
  readonly property bool _otherBeside: root._otherFolds && placeRow.split

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
        onClicked: root.selected = tab.index
      }
    }
  }

  // The picker, and beside it with the room the other settings' fold
  SplitColumns {
    id: placeRow
    visible: root.entry !== null
    minWidth: root.wide ? Widget.px(720) : Infinity
    share: 0.45

    RowLayout {
      Layout.preferredWidth: placeRow.firstWidth
      Layout.alignment: Qt.AlignTop
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

    Loader {
      active: root.entry !== null && root._otherBeside
      visible: active
      Layout.preferredWidth: placeRow.secondWidth
      Layout.alignment: Qt.AlignTop
      sourceComponent: othersFold
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

  // One of `sections`: a line, then a folding part, its fields at their
  // paths in the entry
  Component {
    id: sectionPart

    ColumnLayout {
      id: part
      required property string modelData
      readonly property var schema: root.entrySchema.properties[part.modelData]
      readonly property string foldKey: root.foldKey + ":" + part.modelData

      Layout.fillWidth: true
      spacing: Widget.spacing * 1.5

      // (The first, with no entryContent, sits under the accent line
      // already)
      StyledSeparator {
        visible: entrySlot.visible || part.modelData !== root.sections.filter(key => !root.lastSections.includes(key))[0]
        Layout.fillWidth: true
      }

      FoldingSection {
        Layout.fillWidth: true
        title: I18n.tr(part.schema.title ?? part.modelData)
        description: part.schema.description ? I18n.tr(part.schema.description) : ""
        collapsed: SettingsManager.isCollapsed(part.foldKey)
        onToggled: SettingsManager.setCollapsed(part.foldKey, !collapsed)

        SchemaPropertiesForm {
          Layout.fillWidth: true
          propertiesSchema: ({
              [part.modelData]: part.schema
            })
          values: root.entry ?? ({})
          onEdited: (path, value) => root.edit({
              [path[0]]: value
            })
        }
      }
    }
  }

  Repeater {
    model: root.entry !== null ? root.sections.filter(key => !root.lastSections.includes(key)) : []

    delegate: sectionPart
  }

  // The entry's other settings: folding under `otherTitle`, else as they
  // are
  Component {
    id: otherForm

    SchemaPropertiesForm {
      propertiesSchema: Object.keys(root.entrySchema.properties).filter(key => !root.sections.includes(key) && !root.ownKeys.includes(key)).reduce((out, key) => {
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

  // Their fold, beside the picker or down here
  Component {
    id: othersFold

    FoldingSection {
      id: others
      readonly property string foldKey: root.foldKey + ":other"
      title: root.otherTitle
      collapsed: SettingsManager.isCollapsed(others.foldKey)
      onToggled: SettingsManager.setCollapsed(others.foldKey, !others.collapsed)

      Loader {
        Layout.fillWidth: true
        sourceComponent: otherForm
      }
    }
  }

  Loader {
    active: root.entry !== null && !root._otherFolds
    visible: active
    Layout.fillWidth: true
    sourceComponent: otherForm
  }

  StyledSeparator {
    visible: othersBelow.active
    Layout.fillWidth: true
  }

  Loader {
    id: othersBelow
    active: root.entry !== null && root._otherFolds && !root._otherBeside
    visible: active
    Layout.fillWidth: true
    sourceComponent: othersFold
  }

  Repeater {
    model: root.entry !== null ? root.sections.filter(key => root.lastSections.includes(key)) : []

    delegate: sectionPart
  }
}
