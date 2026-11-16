pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.reusable
import qs.components.forms

// The Dock section's first card (its `x-card`): the docks as tabs, one
// shown at a time: where it sits (the screen picker), Show, its
// pinned apps (the shared Apps.pinned, or its own with pinnedOwn, with a
// search to add more) and its settings (EntryListCard).
EntryListCard {
  id: root

  readonly property bool ownPinned: root.entry?.pinnedOwn ?? false
  // Apps.pinned as edited, saved or not
  readonly property var sharedPinned: SettingsManager.localConfig?.Apps?.pinned ?? Apps.pinned
  readonly property var pinned: root.ownPinned ? root.entry.pinned : root.sharedPinned

  sectionKey: "Dock"
  listKey: "items"
  entryType: "DockEntry"
  savedEntries: DockConfig.docks
  pickerHint: I18n.tr("Click a spot or drag to place it, to an edge to attach it; fine-tune below. Show brings it in for a moment.")
  idBase: "dock"
  labelOf: dock => DockConfig.labelOf(dock)
  // The dock as edited, saved or not
  onShow: () => DockManager.preview(root.entry)

  // The dock's own list, or the shared one
  function setPinned(list) {
    if (root.ownPinned)
      root.edit({
        "pinned": list
      });
    else
      SettingsManager.setValue(["Apps", "pinned"], list);
  }

  // Its own list starts as a copy of the shared one
  function setOwnPinned(own) {
    root.edit(own && root.entry.pinned.length === 0 ? {
      "pinnedOwn": true,
      "pinned": root.sharedPinned.slice()
    } : {
      "pinnedOwn": own
    });
  }

  function pinApp(id) {
    if (!root.pinned.includes(id))
      root.setPinned(root.pinned.concat([id]));
  }

  function unpinAt(index) {
    root.setPinned(root.pinned.filter((_, i) => i !== index));
  }

  function movePinned(index, by) {
    const to = index + by;
    if (to < 0 || to >= root.pinned.length)
      return;
    const pinned = root.pinned.slice();
    pinned.splice(to, 0, pinned.splice(index, 1)[0]);
    root.setPinned(pinned);
  }

  // The pinned apps, with a search to pin more
  entryContent: [
    StyledText {
      text: I18n.tr("Pinned apps")
      role: "label"
      Layout.fillWidth: true
    },
    FormColumn {
      Layout.fillWidth: true

      // Pushed in, so a click doesn't leave it on the next dock's tab
      SwitchRow {
        label: root.ownPinned ? I18n.tr("Its own pinned apps") : I18n.tr("Global pinned apps")
        checked: root.ownPinned
        onToggled: newValue => root.setOwnPinned(newValue)
      }
    },
    StyledText {
      visible: root.pinned.length === 0
      text: I18n.tr("None yet: search below, or right-click a running app on the dock and pick Keep in dock.")
      role: "caption"
      overflow: "wrap"
      Layout.fillWidth: true
    },
    Repeater {
      model: root.pinned.length

      delegate: ListEntryRow {
        id: pinnedRow
        required property int index
        readonly property string appId: root.pinned[index]
        readonly property var entry: DockManager.entryFor(appId)

        image: DockManager.iconFor(appId, null)
        label: entry?.name || appId
        subtitle: entry ? "" : I18n.tr("No app with this id")
        issue: entry ? "" : "error"
        issueTip: I18n.tr("No app with this id")
        canRemove: true
        onRemoveRequested: root.unpinAt(pinnedRow.index)

        RowAction {
          row: pinnedRow
          iconText: "arrow_upward"
          tooltipText: I18n.tr("Move up")
          enabled: pinnedRow.index > 0
          onClicked: root.movePinned(pinnedRow.index, -1)
        }

        RowAction {
          row: pinnedRow
          iconText: "arrow_downward"
          tooltipText: I18n.tr("Move down")
          enabled: pinnedRow.index < root.pinned.length - 1
          onClicked: root.movePinned(pinnedRow.index, 1)
        }
      }
    },
    StyledTextEntry {
      id: search
      placeholderText: I18n.tr("Search apps to pin…")
      clearable: true
      Layout.fillWidth: true
    },
    Flow {
      Layout.fillWidth: true
      spacing: Widget.spacing / 2

      // Modelled by count, so a keystroke rebinds the rows instead of
      // rebuilding them
      Repeater {
        id: matches
        readonly property var apps: root.entry ? LauncherManager.searchApps(search.text, 24).filter(app => !root.pinned.includes(app.id)).slice(0, 8) : []
        model: matches.apps.length

        delegate: StyledTextButton {
          id: result
          required property int index
          readonly property var app: matches.apps[result.index] ?? {
            "id": "",
            "name": ""
          }
          iconText: "add"
          text: result.app.name
          onClicked: {
            root.pinApp(result.app.id);
            search.text = "";
          }
        }
      }
    },
    StyledSeparator {
      Layout.fillWidth: true
    }
  ]
}
