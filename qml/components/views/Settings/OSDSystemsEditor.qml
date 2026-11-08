pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.ui
import qs.components.forms
import qs.components.methods
import qs.components.reusable
import qs.components.views.Layouts

// i18n: keys from the schema (system labels, group names, titles)
// An OSD's systems in its settings tab (OSDListCard), folding: the list in
// order (its icons' and bars' order), each row its system's icon and label,
// dragged to reorder, clicked to select, removed by its X; Add opens a
// picker of the systems not in it yet, by group, with a search. The
// selected system's form (its schema.yaml: Icon, Card, Quiet, then its own
// settings) is under the list. Every system comes from the schema's
// OSDSystem kind (OSDConfig.systemTypes). Edits are `edited(systems)`,
// the whole list.
ColumnLayout {
  id: root

  // The OSD as edited
  required property var entry
  // The settings group key it folds under
  property string foldKey

  signal edited(var systems)

  readonly property var listSchema: ConfigManager.configSchema.definitions.OSDEntry.properties.systems
  // A type listed twice (by hand) keeps its first item, as OSDConfig.osds
  // does, so an edit writes the list back without the second
  readonly property var systems: (root.entry?.systems ?? []).filter((item, i, all) => all.findIndex(other => other.type === item.type) === i)
  readonly property var typeInfo: OSDConfig.systemTypes.reduce((out, info) => {
    out[info.type] = info;
    return out;
  }, {})
  // The systems the picker offers: those not in the list
  readonly property var addable: OSDConfig.systemTypes.filter(info => !root.systems.some(item => item.type === info.type))

  // The selected system, by type (each is in the list once), so a move
  // keeps it selected; none on another OSD's tab
  property string selectedType: ""
  readonly property string _osdId: root.entry?.id ?? ""
  on_OsdIdChanged: root.selectedType = ""
  readonly property int selectedIndex: root.systems.findIndex(item => item.type === root.selectedType)
  readonly property var selected: root.systems[root.selectedIndex] ?? null
  readonly property var selectedInfo: root.selected ? (root.typeInfo[root.selected.type] ?? null) : null

  function labelOf(type) {
    const info = root.typeInfo[type];
    // (A row past the end for a moment, as one is removed, has none)
    return info ? I18n.tr(info.label) : String(type ?? "");
  }

  function add(type) {
    const info = root.typeInfo[type];
    if (!info)
      return;
    const systems = Utils.clone(root.systems);
    systems.push(SchemaValidation.applyDefaults({
      "type": type
    }, info.schema, ConfigManager.configSchema));
    root.edited(systems);
    root.selectedType = type;
  }

  function remove(index) {
    const systems = Utils.clone(root.systems);
    const [gone] = systems.splice(index, 1);
    if (gone?.type === root.selectedType)
      root.selectedType = "";
    root.edited(systems);
  }

  // Moves the system at `from` to before the one at `to` (the count: the
  // end), counted as if it were still in place
  function move(from, to) {
    if (to === from || to === from + 1)
      return;
    const systems = Utils.clone(root.systems);
    const [moved] = systems.splice(from, 1);
    systems.splice(to > from ? to - 1 : to, 0, moved);
    root.edited(systems);
  }

  function editSelected(key, value) {
    if (root.selectedIndex < 0)
      return;
    const systems = Utils.clone(root.systems);
    systems[root.selectedIndex][key] = value;
    root.edited(systems);
  }

  Layout.fillWidth: true
  spacing: Widget.spacing

  FoldingSection {
    id: fold
    Layout.fillWidth: true
    title: I18n.tr(root.listSchema.title)
    description: I18n.tr(root.listSchema.description)
    collapsed: SettingsManager.isCollapsed(root.foldKey)
    onToggled: SettingsManager.setCollapsed(root.foldKey, !fold.collapsed)

    // Carries the rows
    InlineDragLayer {
      id: carrier
      accepts: (target, drag) => target.takes(drag)
      onDropped: (drag, target, index) => target.dropRequested(drag, index)
    }

    EntryListTarget {
      id: systemList
      dragLayer: carrier
      moveKind: "osd-system-move"
      count: root.systems.length
      onDropRequested: (drag, index) => root.move(drag.index, index)

      Repeater {
        model: systemList.count

        EntryListRow {
          id: systemRow
          readonly property var item: root.systems[systemRow.index] ?? ({})
          readonly property var info: root.typeInfo[systemRow.item.type] ?? null

          list: systemList
          icon: systemRow.info?.icon ?? "help"
          label: root.labelOf(systemRow.item.type)
          selected: systemRow.item.type === root.selectedType
          onClicked: root.selectedType = systemRow.selected ? "" : systemRow.item.type

          badges: TipIcon {
            visible: systemRow.item.quiet === true
            text: "notifications_off"
            textColor: systemRow.ink
            textSize: Appearance.fontSizeBy(-1)
            opacity: 0.7
            tip: I18n.tr("Quiet: its changes don't open the OSD")
          }

          RowAction {
            row: systemRow
            danger: true
            iconText: "close"
            tooltipText: I18n.tr("Remove")
            onClicked: root.remove(systemRow.index)
          }
        }
      }
    }

    StyledText {
      visible: root.systems.length === 0
      Layout.fillWidth: true
      text: I18n.tr("Nothing yet: add what this OSD shows.")
      textColor: Theme.foregroundAlt
      wrapMode: Text.WordWrap
    }

    AddEntryButton {
      id: addButton
      visible: root.addable.length > 0
      Layout.topMargin: Widget.spacing / 2
      text: I18n.tr("Add")
      onClicked: picker.openAt(addButton)
    }

    // The selected system's settings, from its schema
    StyledContainer {
      visible: root.selected !== null
      Layout.fillWidth: true
      implicitHeight: selectedColumn.implicitHeight + Widget.padding * 2

      ColumnLayout {
        id: selectedColumn
        anchors.fill: parent
        anchors.margins: Widget.padding
        spacing: Widget.spacing

        RowLayout {
          Layout.fillWidth: true
          spacing: Widget.spacing

          StyledIcon {
            text: root.selectedInfo?.icon ?? ""
            textColor: Theme.accent
          }

          StyledText {
            Layout.fillWidth: true
            text: root.selected ? root.labelOf(root.selected.type) : ""
            font.bold: true
            elide: Text.ElideRight
          }
        }

        StyledSeparator {
          Layout.fillWidth: true
          separatorHeight: 1
          opacity: 0.3
        }

        // A new form per system, so no row writes onto another
        KeyedLoader {
          id: formSlot
          Layout.fillWidth: true
          Layout.preferredHeight: formSlot.childrenRect.height
          key: root.selected ? root._osdId + ":" + root.selected.type : ""
          sourceComponent: systemForm
        }
      }
    }
  }

  Component {
    id: systemForm

    SchemaPropertiesForm {
      width: formSlot.width
      readonly property var props: root.selectedInfo?.schema.properties ?? ({})
      // Its parts' switches, then whether it's quiet, then its own
      // settings in the schema's order
      propertiesSchema: Object.keys(props).filter(key => key !== "type").reduce((out, key) => {
        out[key] = props[key];
        return out;
      }, {})
      order: ["tile", "card", "quiet"].concat(root.selectedInfo?.schema["x-order"] ?? [])
      values: root.selected ?? ({})
      onEdited: (path, value) => root.editSelected(path[0], value)
    }
  }

  TypePickerPopup {
    id: picker
    parent: root
    types: root.addable
    groups: OverlayConfig.libraryGroups
    // As wide as the Add button it opens from
    matchWidth: true
    placeholderText: I18n.tr("Search")
    onTypeSelected: type => root.add(type)
  }
}
