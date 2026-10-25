pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

import qs.services.system
import qs.config
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts
import qs.components.content.parts.notifications

// The notification menu (the Notifications widget's popout, or an overlay
// card): a header with do not disturb and clear all, then one card per app,
// newest first.
Panel {
  id: root

  compactContent: CompactFigure {
    icon: NotificationManager.dnd ? "notifications_off" : "notifications"
    iconColor: NotificationManager.count > 0 ? Theme.accent : Theme.foregroundAlt
    value: String(NotificationManager.count)
    label: I18n.tr(NotificationManager.dnd ? "muted" : "notifications")
  }

  readonly property int maxListHeight: Widget.px(440)
  // A header and a notification, else the figure
  fullMinWidth: Appearance.fontSize * 16
  fullMinHeight: Appearance.fontSize * 11

  implicitWidth: Widget.px(400)
  // Grows to show every group (from compact, to the full layout); empty,
  // back to its place
  wantedHeight: root.groupKeys.length === 0 ? 0 : scroll.height > 0 ? root.height + list.implicitHeight - scroll.height : 1

  // Groups by key, and their keys newest first. The Repeater is keyed by
  // the key strings, so a group's card (and whether it's expanded) survives
  // notifications coming and going.
  property var groups: ({})
  property var groupKeys: []

  // Refreshes relative times, each minute
  readonly property real now: clock.date.getTime()

  function rebuildGroups() {
    const byKey = {};
    const keys = [];
    // Entries are newest first, so groups and their entries come out sorted
    for (const entry of NotificationManager.entries) {
      const key = entry.appName || entry.desktopEntry || "";
      if (!byKey[key]) {
        byKey[key] = {
          key: key,
          appName: entry.appName || entry.desktopEntry || I18n.tr("Unknown"),
          appIcon: entry.appIcon,
          desktopEntry: entry.desktopEntry,
          entries: [],
          newestTime: entry.time,
          critical: false
        };
        keys.push(key);
      }
      const group = byKey[key];
      group.entries.push(entry);
      if (entry.urgency === NotificationUrgency.Critical)
        group.critical = true;
      if (!group.appIcon && entry.appIcon)
        group.appIcon = entry.appIcon;
      if (!group.desktopEntry && entry.desktopEntry)
        group.desktopEntry = entry.desktopEntry;
    }
    root.groups = byKey;
    root.groupKeys = keys;
  }

  function clearAll() {
    if (!clearOut.running)
      clearOut.start();
  }

  Connections {
    target: NotificationManager
    function onEntriesChanged() {
      root.rebuildGroups();
    }
  }

  Component.onCompleted: rebuildGroups()

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  // The groups slide out one after another, top first (later ones
  // together, so a long list doesn't keep the user waiting), then all go
  readonly property int _staggerSteps: 8
  readonly property int _stagger: Appearance.animFast / 2
  SequentialAnimation {
    id: clearOut
    ScriptAction {
      script: {
        for (let i = 0; i < groupRepeater.count; i++)
          groupRepeater.itemAt(i)?.leave(Math.min(i, root._staggerSteps) * root._stagger);
      }
    }
    PauseAnimation {
      duration: Math.min(Math.max(0, groupRepeater.count - 1), root._staggerSteps) * root._stagger + Appearance.animNormal
    }
    ScriptAction {
      script: NotificationManager.clearAll()
    }
  }

  NotificationHeader {
    onClearAll: root.clearAll()
  }

  StyledSeparator {
    Layout.fillWidth: true
    separatorColor: Theme.backgroundHighlight
  }

  StyledScrollView {
    id: scroll
    visible: root.groupKeys.length > 0
    Layout.fillWidth: true
    Layout.preferredHeight: root.embedded ? -1 : Math.min(root.maxListHeight, list.implicitHeight)
    Layout.fillHeight: root.embedded
    contentPadding: 0
    showScrollBar: list.implicitHeight > (root.embedded ? scroll.height : root.maxListHeight)
    rightPadding: showScrollBar ? Widget.px(12) : 0
    clip: true

    ColumnLayout {
      id: list
      width: scroll.availableWidth
      spacing: Widget.spacing

      Repeater {
        id: groupRepeater
        model: ScriptModel {
          values: root.groupKeys
        }

        NotificationGroupDelegate {
          required property string modelData
          group: root.groups[modelData] ?? null
          now: root.now
        }
      }
    }
  }

  // Empty: centred in whatever room is left (the card's slot, or a fixed
  // height in a popout)
  Item {
    visible: root.groupKeys.length === 0
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    Layout.preferredHeight: root.embedded ? -1 : emptyState.implicitHeight + Widget.padding * 6

    ColumnLayout {
      id: emptyState
      anchors.centerIn: parent
      width: parent.width
      spacing: Widget.spacing / 2

      StyledIcon {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: NotificationManager.dnd ? "notifications_paused" : "notifications_active"
        textColor: Theme.foregroundAlt
        textSize: Appearance.fontSize * 3
        opacity: 0.4
      }

      StyledText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("All caught up")
        textColor: Theme.foregroundAlt
      }

      StyledText {
        visible: NotificationManager.dnd
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("Do not disturb is on")
        textColor: Theme.foregroundAlt
        textSize: Appearance.fontSizeBy(-2)
        opacity: 0.7
      }
    }
  }
}
