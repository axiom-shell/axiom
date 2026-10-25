pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.reusable

// The Dock section's first card (its `x-card`): the docks as tabs, one
// shown at a time: where it sits (a screen picker with presets), Show, its
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
  pickerHint: I18n.tr("Click a spot to place it; fine-tune below. Show slides it in for a moment.")
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
      font.bold: true
      Layout.fillWidth: true
    },
    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledSwitch {
        id: ownSwitch
        checked: root.ownPinned
        onToggled: {
          root.setOwnPinned(checked);
          // A click sets checked itself, which would leave it on the next
          // dock's tab
          ownSwitch.checked = Qt.binding(() => root.ownPinned);
        }
      }

      StyledText {
        text: root.ownPinned ? I18n.tr("Its own pinned apps") : I18n.tr("Global pinned apps")
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    },
    StyledText {
      visible: root.pinned.length === 0
      text: I18n.tr("None yet: search below, or right-click a running app on the dock and pick Keep in dock.")
      textColor: Theme.foregroundAlt
      textSize: Appearance.fontSizeBy(-2)
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    },
    Repeater {
      model: root.pinned.length

      delegate: AppRow {
        id: pinnedRow
        required property int index
        readonly property string appId: root.pinned[index]
        readonly property var entry: DockManager.entryFor(appId)

        Layout.fillWidth: true
        iconSource: DockManager.iconFor(appId, null)
        name: entry?.name || appId
        detail: entry ? "" : I18n.tr("No app with this id")

        StyledIconButton {
          iconText: "arrow_upward"
          tooltipText: I18n.tr("Move up")
          enabled: pinnedRow.index > 0
          Layout.fillWidth: false
          Layout.preferredWidth: Widget.height - Widget.px(4)
          Layout.preferredHeight: Widget.height - Widget.px(4)
          onClicked: root.movePinned(pinnedRow.index, -1)
        }

        StyledIconButton {
          iconText: "arrow_downward"
          tooltipText: I18n.tr("Move down")
          enabled: pinnedRow.index < root.pinned.length - 1
          Layout.fillWidth: false
          Layout.preferredWidth: Widget.height - Widget.px(4)
          Layout.preferredHeight: Widget.height - Widget.px(4)
          onClicked: root.movePinned(pinnedRow.index, 1)
        }

        StyledIconButton {
          iconText: "close"
          tooltipText: I18n.tr("Remove")
          hoverColor: Theme.error
          Layout.fillWidth: false
          Layout.preferredWidth: Widget.height - Widget.px(4)
          Layout.preferredHeight: Widget.height - Widget.px(4)
          onClicked: root.unpinAt(pinnedRow.index)
        }
      }
    },
    StyledTextEntry {
      id: search
      placeholderText: I18n.tr("Search apps to pin…")
      Layout.fillWidth: true
      Layout.preferredHeight: Widget.height
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
          implicitHeight: Widget.height - Widget.px(4)
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
      separatorColor: Theme.accent
      Layout.fillWidth: true
    }
  ]

  // A pinned app: its icon and name, then the buttons given as children
  component AppRow: RowLayout {
    id: row
    property string iconSource: ""
    property string name: ""
    property string detail: ""
    default property alias buttons: extra.data

    spacing: Widget.spacing

    Image {
      Layout.preferredWidth: Widget.height - Widget.px(8)
      Layout.preferredHeight: Widget.height - Widget.px(8)
      sourceSize: Qt.size(64, 64)
      source: row.iconSource
      asynchronous: true
    }

    StyledText {
      text: row.name
      elide: Text.ElideRight
      Layout.fillWidth: true
    }

    StyledText {
      visible: row.detail !== ""
      text: row.detail
      textColor: Theme.error
      textSize: Appearance.fontSizeBy(-2)
    }

    RowLayout {
      id: extra
      spacing: 2
    }
  }
}
