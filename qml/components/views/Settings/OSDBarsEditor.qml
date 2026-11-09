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

// i18n: keys from the schema (bar kinds, system labels, titles)
// An OSD's bars in its settings tab (OSDListCard), folding under "Bars":
// every bar it shows, in its order (its `barOrder`, as the host shows
// them: OSDConfig.orderedBarRows), whichever system it's a setting of
// (the systems' `x-barNames`: each entry of Audio's `bars`, Brightness as
// one), dragged to reorder anywhere (a drag writes the whole order to
// `barOrder`, systems mixed), clicked to select, removed by its X; Add
// opens a picker of the bar kinds (OSDConfig.barKinds). The selected
// bar's form (its entry's schema, or a one-bar system's settings) is
// beside the list with the room (SplitColumns), the bars' layout
// (`barLayout`) under the list. The bars stay their systems' settings:
// edits are `edited(values)` for the entry, `{ systems }` (with
// `barOrder` when a key in it changes), `{ barOrder }` or `{ barLayout }`.
ColumnLayout {
  id: root

  // The OSD as edited
  required property var entry
  // The settings group key it folds under
  property string foldKey

  signal edited(var values)

  readonly property var systems: root.entry?.systems ?? []
  // Its bars' order, by key ([] keeps the systems' order)
  readonly property var order: root.entry?.barOrder ?? []
  readonly property var layoutSchema: ConfigManager.configSchema.definitions.OSDEntry.properties.barLayout
  // Every bar, in the OSD's order: { key ("<System>/<its key>"), system
  // (its item's index in `systems`), type, index (in its `from` list, -1
  // for a one-bar system), name, icon, off (its system's bars are
  // switched off) }
  readonly property var rows: OSDConfig.orderedBarRows(root.systems, root.order).map(bar => Object.assign(bar, {
      "type": root.systems[bar.system].type,
      "off": root.systems[bar.system].tile === false
    }))
  // The kinds the picker offers: a list's kinds it may repeat
  // (`x-barNames`' `repeats`) and those it has no bar of yet, and the
  // one-bar systems not in the list yet
  readonly property var addable: OSDConfig.barKinds.filter(kind => {
    const at = kind.type.indexOf(":");
    if (at < 0)
      return !root.systems.some(item => item.type === kind.type);
    const type = kind.type.slice(0, at);
    const spec = OSDConfig.barSpecOf(type);
    const value = kind.type.slice(at + 1);
    return (spec.repeats ?? []).includes(value) || !root.rows.some(row => row.type === type && row.index >= 0 && root.systems[row.system][spec.from][row.index][spec.by] === value);
  })

  // The selected bar, by its system and index there; the first when it
  // isn't there (another OSD's tab, removed)
  property string _pickedType: ""
  property int _pickedIndex: -1
  readonly property string _osdId: root.entry?.id ?? ""
  on_OsdIdChanged: root._pickedType = ""
  readonly property int selectedRow: root.rows.length === 0 ? -1 : Math.max(0, root.rows.findIndex(row => row.type === root._pickedType && row.index === root._pickedIndex))
  readonly property var selected: root.rows[root.selectedRow] ?? null
  // The selected bar's system (OSDListCard's preview highlights it)
  readonly property string selectedType: root.selected?.type ?? ""
  readonly property var _selectedItem: root.selected ? root.systems[root.selected.system] : null
  readonly property var _selectedSchema: root.selected ? OSDConfig.schemaOf(root.selected.type) : null
  readonly property var _selectedSpec: root.selected ? OSDConfig.barSpecOf(root.selected.type) : null

  function _pick(type, index) {
    root._pickedType = type;
    root._pickedIndex = index;
  }

  // `systems`, and `order` with it when given (a key in it changed)
  function _commit(systems, order) {
    const values = {
      "systems": systems
    };
    if (order !== undefined)
      values.barOrder = order;
    root.edited(values);
  }

  // A kind from the picker: "<System>" adds that one-bar system; a list's
  // kind ("<System>:<kind>") adds a bar to its system's item (switching
  // its bars on), or the item with only that bar (its `barOnly`). With an
  // order set, its key goes at its end (shown last, as it would be)
  function add(kindType) {
    const at = kindType.indexOf(":");
    const type = at < 0 ? kindType : kindType.slice(0, at);
    const schema = OSDConfig.schemaOf(type);
    const spec = OSDConfig.barSpecOf(type);
    if (!schema || !spec)
      return;
    const systems = Utils.clone(root.systems);
    if (OSDParts.oneBar(spec)) {
      if (systems.some(item => item.type === type))
        return;
      systems.push(SchemaValidation.applyDefaults({
        "type": type
      }, schema, ConfigManager.configSchema));
      root._commit(systems, root._appended(type + "/" + OSDParts.barKey(spec, null)));
      root._pick(type, -1);
      return;
    }
    // Its stable id (ItemId), free in its list: its kind, else counted on
    const kind = kindType.slice(at + 1);
    let index = systems.findIndex(item => item.type === type);
    const taken = index < 0 ? [] : (systems[index][spec.from] ?? []).map(other => other.id);
    const bar = SchemaValidation.applyDefaults({
      "id": Utils.freeId(kind, taken, "-"),
      [spec.by]: kind
    }, schema.properties[spec.from].items, ConfigManager.configSchema);
    if (index < 0) {
      systems.push(SchemaValidation.applyDefaults(Object.assign({
        "type": type,
        [spec.from]: [bar]
      }, Utils.clone(spec.barOnly ?? {})), schema, ConfigManager.configSchema));
      index = systems.length - 1;
    } else {
      systems[index][spec.from] = (systems[index][spec.from] ?? []).concat([bar]);
      if (systems[index].tile === false)
        systems[index].tile = true;
    }
    root._commit(systems, root._appended(type + "/" + OSDParts.barKey(spec, bar)));
    root._pick(type, systems[index][spec.from].length - 1);
  }

  // The order with `key` added at its end; undefined (unchanged) while
  // there's none
  function _appended(key) {
    return root.order.length > 0 ? root.order.filter(other => other !== key).concat([key]) : undefined;
  }

  // The order without `key`; undefined (unchanged) when it hasn't it
  function _without(key) {
    return root.order.includes(key) ? root.order.filter(other => other !== key) : undefined;
  }

  // Removes a bar, or a one-bar system, and its key from the order; an
  // item left with no bars and nothing but its `barOnly` settings goes
  // too
  function remove(rowIndex) {
    const row = root.rows[rowIndex];
    if (!row)
      return;
    const systems = Utils.clone(root.systems);
    const spec = OSDConfig.barSpecOf(row.type);
    // A bar above the selected one in its list: the selection stays on it
    if (row.index >= 0 && row.type === root._pickedType && row.index < root._pickedIndex)
      root._pickedIndex -= 1;
    if (row.index < 0) {
      systems.splice(row.system, 1);
    } else {
      const item = systems[row.system];
      item[spec.from].splice(row.index, 1);
      const only = spec.barOnly ?? null;
      if (item[spec.from].length === 0 && only && Object.keys(only).every(key => JSON.stringify(item[key]) === JSON.stringify(only[key])))
        systems.splice(row.system, 1);
    }
    root._commit(systems, root._without(row.key));
  }

  // Moves the bar at row `from` to before row `to` (the count: the end),
  // counted as if it were still in place, across systems as anywhere:
  // the order from then on is the whole list's, explicit (`barOrder`)
  function move(from, to) {
    const row = root.rows[from];
    if (!row || to === from || to === from + 1)
      return;
    const keys = root.rows.map(other => other.key);
    const [moved] = keys.splice(from, 1);
    keys.splice(to > from ? to - 1 : to, 0, moved);
    root.edited({
      "barOrder": keys
    });
  }

  // The selected bar's setting `key`: its list entry's, or its system's.
  // A kind changed changes its key (an App bar's is by its id): the order
  // names it by the new one, in its place
  function editSelected(key, value) {
    const row = root.selected;
    if (!row)
      return;
    const systems = Utils.clone(root.systems);
    if (row.index < 0) {
      systems[row.system][key] = value;
      root._commit(systems);
      return;
    }
    const entry = systems[row.system][root._selectedSpec.from][row.index];
    entry[key] = value;
    const renamed = row.type + "/" + OSDParts.barKey(root._selectedSpec, entry);
    root._commit(systems, renamed !== row.key && root.order.includes(row.key) ? root.order.map(other => other === row.key ? renamed : other) : undefined);
  }

  Layout.fillWidth: true
  spacing: Widget.spacing * 1.5

  StyledSeparator {
    Layout.fillWidth: true
  }

  FoldingSection {
    id: fold
    Layout.fillWidth: true
    title: I18n.tr("Bars")
    description: I18n.tr("Every bar this OSD shows, in order, and how they're laid out.")
    collapsed: SettingsManager.isCollapsed(root.foldKey)
    onToggled: SettingsManager.setCollapsed(root.foldKey, !fold.collapsed)

    // The list beside the selected bar's form, with the room
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
          id: barList
          dragLayer: carrier
          moveKind: "osd-bar-move"
          count: root.rows.length
          onDropRequested: (drag, index) => root.move(drag.index, index)

          Repeater {
            model: barList.count

            EntryListRow {
              id: barRow
              readonly property var row: root.rows[barRow.index] ?? ({})

              list: barList
              icon: barRow.row.icon ?? "help"
              label: barRow.row.name ?? ""
              dimmed: barRow.row.off === true
              selected: barRow.index === root.selectedRow
              onClicked: {
                EditsManager.commitTyping();
                root._pick(barRow.row.type, barRow.row.index);
              }

              badges: TipIcon {
                visible: barRow.row.off === true
                text: "visibility_off"
                textColor: barRow.ink
                textSize: Appearance.fontSizeBy(-1)
                opacity: 0.7
                tip: I18n.tr("Hidden: its system's bars are switched off")
              }

              RowAction {
                row: barRow
                danger: true
                iconText: "close"
                tooltipText: I18n.tr("Remove")
                onClicked: root.remove(barRow.index)
              }
            }
          }
        }

        StyledText {
          visible: root.rows.length === 0
          Layout.fillWidth: true
          text: I18n.tr("No bars yet: add one to show a level.")
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

        // How the bars are laid out (its fields at their paths in the
        // entry, so `../edge` reaches the entry's own)
        SchemaPropertiesForm {
          visible: root.entry !== null
          Layout.fillWidth: true
          Layout.topMargin: Widget.spacing
          propertiesSchema: ({
              "barLayout": root.layoutSchema
            })
          values: root.entry ?? ({})
          onEdited: (path, value) => root.edited({
              [path[0]]: value
            })
        }
      }

      // The selected bar's settings, from its schema
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
              text: root.selected?.icon ?? ""
              textColor: Theme.accent
            }

            StyledLabel {
              Layout.fillWidth: true
              text: root.selected?.name ?? ""
              font.bold: true
              elide: Text.ElideRight
            }

            // Whose setting it is (a list's bar)
            StyledLabel {
              visible: (root.selected?.index ?? -1) >= 0
              text: root.selected ? OSDConfig.nameOf(root.selected.type) : ""
              textColor: Theme.foregroundAlt
              textSize: Appearance.fontSizeBy(-1)
            }
          }

          StyledSeparator {
            Layout.fillWidth: true
            separatorHeight: 1
            opacity: 0.3
          }

          // A new form per bar, so no row writes onto another
          KeyedLoader {
            id: formSlot
            Layout.fillWidth: true
            Layout.preferredHeight: formSlot.childrenRect.height
            key: root.selected ? root._osdId + ":" + root.selected.type + ":" + root.selected.index : ""
            sourceComponent: barForm
          }
        }
      }
    }
  }

  Component {
    id: barForm

    SchemaPropertiesForm {
      width: formSlot.width
      readonly property bool isEntry: (root.selected?.index ?? -1) >= 0
      // A list's bar: its entry's schema; a one-bar system: its settings
      // (its bar's switch, quiet, then its own), less its card's switch
      readonly property var props: isEntry ? (root._selectedSchema?.properties[root._selectedSpec?.from]?.items?.properties ?? ({})) : (root._selectedSchema?.properties ?? ({}))
      propertiesSchema: Object.keys(props).filter(key => isEntry || (key !== "type" && key !== "card")).reduce((out, key) => {
        out[key] = props[key];
        return out;
      }, {})
      order: isEntry ? [] : ["tile", "quiet"].concat(root._selectedSchema?.["x-order"] ?? [])
      values: (isEntry ? root._selectedItem?.[root._selectedSpec?.from]?.[root.selected?.index] : root._selectedItem) ?? ({})
      onEdited: (path, value) => root.editSelected(path[0], value)
    }
  }

  TypePickerPopup {
    id: picker
    parent: root
    types: root.addable
    // As wide as the Add button it opens from
    matchWidth: true
    placeholderText: I18n.tr("Search")
    onTypeSelected: type => root.add(type)
  }
}
