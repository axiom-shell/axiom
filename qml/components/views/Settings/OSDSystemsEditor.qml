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
// settings) is beside the list with the room, else under it
// (SplitColumns); one is always selected (the first, on another OSD's
// tab). Bars are the Bars part's (OSDBarsEditor): a system that is only a
// bar (`x-barNames: {bar}`, Brightness) isn't listed here, and a system's
// list of bars (`x-barNames`' `from`, Audio's `bars`) isn't in its form.
// Every system comes from the schema's OSDSystem kind
// (OSDConfig.systemTypes). Edits are `edited(values)` for the entry:
// `{ systems }`, the whole list (removing one, with `barOrder` less its
// bars' keys).
ColumnLayout {
  id: root

  // The OSD as edited
  required property var entry
  // The settings group key it folds under
  property string foldKey

  signal edited(var values)

  readonly property var listSchema: ConfigManager.configSchema.definitions.OSDEntry.properties.systems
  // A type listed twice (by hand) keeps its first item, as OSDConfig.osds
  // does, so an edit writes the list back without the second
  readonly property var systems: (root.entry?.systems ?? []).filter((item, i, all) => all.findIndex(other => other.type === item.type) === i)
  readonly property var typeInfo: OSDConfig.systemTypes.reduce((out, info) => {
    out[info.type] = info;
    return out;
  }, {})
  // A system that is only a bar: the Bars part's alone
  function _onlyBar(type) {
    return OSDParts.oneBar(OSDConfig.barSpecOf(type));
  }
  // The indexes in `systems` of the ones listed here
  readonly property var shown: root.systems.map((item, index) => root._onlyBar(item.type) ? -1 : index).filter(index => index >= 0)
  // The systems the picker offers: those not in the list
  readonly property var addable: OSDConfig.systemTypes.filter(info => !root._onlyBar(info.type) && !root.systems.some(item => item.type === info.type))

  // The selected system, by type (each is in the list once), so a move
  // keeps it selected; the first when it isn't in the list (another OSD's
  // tab, removed)
  property string _picked: ""
  readonly property string _osdId: root.entry?.id ?? ""
  on_OsdIdChanged: root._picked = ""
  readonly property int selectedIndex: {
    const picked = root.shown.find(index => root.systems[index].type === root._picked);
    return picked ?? (root.shown[0] ?? -1);
  }
  readonly property string selectedType: root.systems[root.selectedIndex]?.type ?? ""
  readonly property var selected: root.systems[root.selectedIndex] ?? null
  readonly property var selectedInfo: root.selected ? (root.typeInfo[root.selected.type] ?? null) : null
  // How its bars are kept (`x-barNames`), or null
  readonly property var _barSpec: root.selected ? OSDConfig.barSpecOf(root.selected.type) : null

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
    root._commit(systems);
    root._picked = type;
  }

  function _commit(systems) {
    root.edited({
      "systems": systems
    });
  }

  // Removes a system, and its bars' keys from the OSD's bar order
  function remove(index) {
    const systems = Utils.clone(root.systems);
    const [gone] = systems.splice(index, 1);
    const order = root.entry?.barOrder ?? [];
    const kept = order.filter(key => !key.startsWith(gone.type + "/"));
    const values = {
      "systems": systems
    };
    if (kept.length !== order.length)
      values.barOrder = kept;
    root.edited(values);
  }

  // Moves the system at `from` (its index in `systems`) to before the
  // listed row `to` (the count: just after the last listed), counted as if
  // it were still in place: dropped where it was, nothing moves (not even
  // past a one-bar system between, which would reorder the bars)
  function move(from, to) {
    const at = root.shown.indexOf(from);
    if (at < 0 || to === at || to === at + 1)
      return;
    const before = to < root.shown.length ? root.shown[to] : root.shown[root.shown.length - 1] + 1;
    const systems = Utils.clone(root.systems);
    const [moved] = systems.splice(from, 1);
    systems.splice(before > from ? before - 1 : before, 0, moved);
    root._commit(systems);
  }

  function editSelected(key, value) {
    if (root.selectedIndex < 0)
      return;
    const systems = Utils.clone(root.systems);
    systems[root.selectedIndex][key] = value;
    root._commit(systems);
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

    // The list beside the selected system's form, with the room
    SplitColumns {
      id: split

      ColumnLayout {
        Layout.preferredWidth: split.firstWidth
        Layout.alignment: Qt.AlignTop
        spacing: Widget.spacing

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
          count: root.shown.length
          onDropRequested: (drag, index) => root.move(drag.index, index)

          Repeater {
            model: systemList.count

            EntryListRow {
              id: systemRow
              readonly property int at: root.shown[systemRow.index] ?? -1
              readonly property var item: root.systems[systemRow.at] ?? ({})
              readonly property var info: root.typeInfo[systemRow.item.type] ?? null

              list: systemList
              entryIndex: systemRow.at
              icon: systemRow.info?.icon ?? "help"
              label: root.labelOf(systemRow.item.type)
              selected: systemRow.item.type === root.selectedType
              onClicked: {
                EditsManager.commitTyping();
                root._picked = systemRow.item.type;
              }

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
                onClicked: root.remove(systemRow.at)
              }
            }
          }
        }

        StyledText {
          visible: root.shown.length === 0
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
      }

      // The selected system's settings, from its schema
      StyledContainer {
        visible: root.selected !== null
        Layout.preferredWidth: split.secondWidth
        Layout.alignment: Qt.AlignTop
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

            StyledLabel {
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

          // Its bars are set in the Bars part
          StyledText {
            visible: root._barSpec?.from !== undefined
            Layout.fillWidth: true
            text: I18n.tr("Its bars are set under Bars, below.")
            textColor: Theme.foregroundAlt
            textSize: Appearance.fontSizeBy(-1)
            wrapMode: Text.WordWrap
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
  }

  Component {
    id: systemForm

    SchemaPropertiesForm {
      width: formSlot.width
      readonly property var props: root.selectedInfo?.schema.properties ?? ({})
      // (its list of bars is the Bars part's)
      readonly property string barsKey: root._barSpec?.from ?? ""
      // Its parts' switches, then whether it's quiet, then its own
      // settings in the schema's order
      propertiesSchema: Object.keys(props).filter(key => key !== "type" && key !== barsKey).reduce((out, key) => {
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
