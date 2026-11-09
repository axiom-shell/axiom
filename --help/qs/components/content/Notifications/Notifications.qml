pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

import qs.services.system
import qs.config
import qs.services.ui
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts
import qs.components.content.parts.notifications
import qs.components.methods

// The notification menu (the Notifications widget's popout, or an overlay
// card): a header with do not disturb and clear all, then one card per app
// (the shell's own, per source), newest first, then the Quiet section
// pinned to the end (silent ones, folded shut by default, opening toward
// the alerts up to half the list's room).
Panel {
  id: root

  // A bar popout takes the keyboard while a notification offers a reply
  wantsKeyboardFocus: NotificationManager.replyable

  compactContent: CompactFigure {
    icon: NotificationManager.dnd ? "notifications_off" : "notifications"
    iconColor: NotificationManager.count > 0 ? Theme.accent : Theme.foregroundAlt
    value: String(NotificationManager.count)
    label: I18n.tr(NotificationManager.dnd ? "muted" : "notifications")
  }

  readonly property int maxListHeight: Widget.px(440)
  // One notification's card (a one-line summary and body, no actions:
  // NotificationGroupDelegate's padding, app header and entry), the height
  // empty, so a popout only grows from there and is the same size again
  // after the last one is cleared
  readonly property real oneHeight: Widget.padding * 2 + Math.max(Widget.px(18), Widget.smallHeight, Math.ceil(smallMetrics.height)) + Widget.spacing + Math.ceil(summaryMetrics.height) + 2 + Math.ceil(bodyMetrics.height)
  readonly property real emptyHeight: Math.max(root.oneHeight, emptyState.implicitHeight)
  // In a popout the list grows away from the header, which stays by the
  // bar (Panel.growth)
  flips: true
  readonly property bool hasAlerts: root.groupKeys.length > 0
  readonly property bool hasQuiet: NotificationManager.quietCount > 0
  // The most the open Quiet section's list takes: half the list's room
  readonly property real quietCap: root.embedded ? root.body.height / 2 : root.maxListHeight / 2
  // What the alerts and the Quiet section take now, and the most they can
  // (the alerts' cap leaves the Quiet list its room, and the Quiet heading
  // and separator may come later), so the popout is made big enough once
  readonly property real _listsHeight: (root.hasAlerts ? scroll.height : root.emptyHeight) + (root.hasQuiet ? quietBlock.height + root.spacing : 0)
  readonly property real _listsMaxHeight: root.maxListHeight + quietSeparator.implicitHeight + quietHeader.implicitHeight + root.spacing * 3
  maxImplicitHeight: root.embedded ? 0 : root.implicitHeight - root._listsHeight + root._listsMaxHeight

  FontMetrics {
    id: smallMetrics
    font.family: Appearance.fontFamily
    font.pixelSize: Appearance.fontSizeBy(-2)
  }
  FontMetrics {
    id: summaryMetrics
    font.family: Appearance.fontFamily
    font.pixelSize: Appearance.fontSize
  }
  FontMetrics {
    id: bodyMetrics
    font.family: Appearance.fontFamily
    font.pixelSize: Appearance.fontSizeBy(-1)
  }
  // A header and a notification, else the figure
  fullMinWidth: Appearance.fontSize * 16
  fullMinHeight: Appearance.fontSize * 11

  implicitWidth: Widget.px(400)
  // Grows to show every group and the open Quiet list (from compact, to
  // the full layout); nothing listed, back to its place
  readonly property bool _quietListed: root.hasQuiet && quietFold.open
  wantedHeight: !root.hasAlerts && !root._quietListed ? 0 : root.body.height > 0 ? root.height + (root.hasAlerts ? list.implicitHeight - scroll.height : 0) + (root._quietListed ? quietFold.implicitHeight - quietScroll.height : 0) : 1

  // Groups by key, and their keys newest first, for the alerts and the
  // silent ones. The Repeaters are keyed by the key strings, so a group's
  // card (and whether it's expanded) survives notifications coming and
  // going.
  property var groups: ({})
  property var groupKeys: []
  property var quietGroups: ({})
  property var quietKeys: []

  // Refreshes relative times, each minute
  readonly property real now: clock.date.getTime()

  function rebuildGroups() {
    const alerts = root.groupsOf(NotificationManager.alerts);
    root.groups = alerts.byKey;
    root.groupKeys = alerts.keys;
    const quiet = root.groupsOf(NotificationManager.quiet);
    root.quietGroups = quiet.byKey;
    root.quietKeys = quiet.keys;
    root.seeQuiet();
  }

  // What the open Quiet section shows is seen (its heading's dot)
  function seeQuiet() {
    if (NotificationManager.quietOpen)
      NotificationManager.markQuietSeen();
  }

  Connections {
    target: NotificationManager
    function onQuietOpenChanged() {
      root.seeQuiet();
    }
  }

  // The name a list card shows for one of the shell's sources
  // (NotificationLevel.sources), "axiom" for one not listed there
  function sourceName(desktopEntry) {
    const name = NotificationLevel.sources[desktopEntry];
    return name ? I18n.tr(name) : "axiom";
  }

  // Entries by app (the shell's by source: NotificationLevel.groupKey):
  // { byKey, keys }
  function groupsOf(entries) {
    const byKey = {};
    const keys = [];
    // Entries are newest first, so groups and their entries come out sorted
    for (const entry of entries) {
      const key = NotificationLevel.groupKey(entry);
      if (!byKey[key]) {
        const source = key !== (entry.appName || entry.desktopEntry || "");
        byKey[key] = {
          key: key,
          appName: source ? root.sourceName(key) : entry.appName || entry.desktopEntry || I18n.tr("Unknown"),
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
    return {
      byKey: byKey,
      keys: keys
    };
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

  // The groups slide out one after another, top first, the open Quiet
  // section's after the alerts (later ones together, so a long list
  // doesn't keep the user waiting), then all go
  readonly property int _staggerSteps: 8
  readonly property int _stagger: Appearance.animFast / 2
  readonly property int _leaving: groupRepeater.count + quietRepeater.count
  SequentialAnimation {
    id: clearOut
    ScriptAction {
      script: {
        const cards = [];
        for (let i = 0; i < groupRepeater.count; i++)
          cards.push(groupRepeater.itemAt(i));
        for (let i = 0; i < quietRepeater.count; i++)
          cards.push(quietRepeater.itemAt(i));
        cards.forEach((card, i) => card?.leave(Math.min(i, root._staggerSteps) * root._stagger));
      }
    }
    PauseAnimation {
      duration: Math.min(Math.max(0, root._leaving - 1), root._staggerSteps) * root._stagger + Appearance.animNormal
    }
    ScriptAction {
      script: ActionsManager.run("clearNotifications")
    }
  }

  NotificationHeader {
    onClearAll: root.clearAll()
  }

  StyledSeparator {
    Layout.fillWidth: true
    separatorColor: Theme.backgroundHighlight
  }

  // Empty: centred in whatever room is left (the card's slot above the
  // Quiet section, or one notification's height in a popout)
  Item {
    visible: !root.hasAlerts
    clip: true
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    Layout.preferredHeight: root.embedded ? -1 : root.emptyHeight

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
        // Smaller in a popout, to fit one notification's height
        textSize: Appearance.fontSize * (root.embedded ? 3 : 2)
        opacity: 0.4
      }

      StyledText {
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("All caught up")
        textColor: Theme.foregroundAlt
      }

      StyledText {
        wrapMode: Text.WordWrap
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

  // The alerts, taking what the Quiet section leaves
  StyledScrollView {
    id: scroll
    visible: root.hasAlerts
    Layout.fillWidth: true
    Layout.preferredHeight: root.embedded ? -1 : Math.min(root.maxListHeight - (root.hasQuiet ? quietScroll.height : 0), list.implicitHeight)
    Layout.fillHeight: root.embedded
    contentPadding: 0
    showScrollBar: list.implicitHeight > scroll.height + 1

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

  // The Quiet section, pinned to the end: its heading, then its list
  // (built only while open or folding shut), which grows toward the
  // alerts up to quietCap and scrolls past it
  ColumnLayout {
    id: quietBlock
    visible: root.hasQuiet
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledSeparator {
      id: quietSeparator
      Layout.fillWidth: true
      separatorColor: Theme.backgroundHighlight
    }

    NotificationQuietHeader {
      id: quietHeader
    }

    StyledScrollView {
      id: quietScroll
      visible: quietFold.shown
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(root.quietCap, quietFold.implicitHeight)
      contentPadding: 0
      showScrollBar: quietFold.implicitHeight > root.quietCap + 1

      FoldingColumn {
        id: quietFold
        width: quietScroll.availableWidth
        open: NotificationManager.quietOpen && root.hasQuiet
        spacing: Widget.spacing

        Repeater {
          id: quietRepeater
          model: ScriptModel {
            values: quietFold.shown ? root.quietKeys : []
          }

          NotificationGroupDelegate {
            required property string modelData
            group: root.quietGroups[modelData] ?? null
            now: root.now
            quiet: true
          }
        }
      }
    }
  }
}
