pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.config
import qs.services.system
import qs.components.reusable

// One app's notifications as a single card: the app header (icon, name,
// count, newest time, or dismiss-all while hovered), then its entries.
// Collapsed, a group of several shows only the newest, with the rest as
// cards stacked underneath; clicking the header expands it. A lone or
// collapsed card swipes away whole (dismissing what it holds), an
// expanded one entry by entry.
Item {
  id: root

  // { key, appName, appIcon, desktopEntry, entries (NotificationManager
  //   entries, newest first), newestTime, critical }
  required property var group
  property real now: Date.now()
  property bool expanded: false
  property real swipeThreshold: 120

  readonly property var entries: root.group?.entries ?? []
  readonly property int count: root.entries.length
  readonly property bool stacked: !root.expanded && root.count > 1
  readonly property int stackDepth: root.stacked ? Math.min(2, root.count - 1) : 0
  readonly property int stackStep: 5

  function dismissAll() {
    root._slideOut(0, true);
  }

  // Slides out after `delay` without dismissing anything: the list's
  // clear-all staggers its groups out this way, then clears them at once
  function leave(delay) {
    root._slideOut(delay, false);
  }

  // Whether the slide out dismisses the group's entries once it's out
  property bool _dismissing: false
  function _slideOut(delay, dismiss) {
    root._dismissing = root._dismissing || dismiss;
    if (slideOut.running)
      return;
    slideDelay.duration = delay;
    slideOut.start();
  }

  Layout.fillWidth: true
  implicitHeight: card.height + root.stackDepth * root.stackStep
  opacity: 0

  // Glides into place when a group above it comes or goes; not on its
  // own arrival, which `appear` animates
  property bool _placed: false
  Component.onCompleted: {
    appear.start();
    Qt.callLater(() => root._placed = true);
  }
  Glide on y {
    enabled: root._placed
    duration: Appearance.animNormal
  }
  onCountChanged: {
    if (root.count <= 1)
      root.expanded = false;
  }

  transform: Translate {
    id: shift
  }

  DragHandler {
    id: swipe
    enabled: !root.expanded
    target: null
    yAxis.enabled: false
    onTranslationChanged: {
      if (!active || slideOut.running)
        return;
      shift.x = translation.x;
      root.opacity = 1 - Math.min(1, Math.abs(translation.x) / (root.swipeThreshold * 2));
    }
    onActiveChanged: {
      if (active || slideOut.running)
        return;
      if (Math.abs(shift.x) > root.swipeThreshold)
        root.dismissAll();
      else
        snapBack.start();
    }
  }

  // A swipe short of the threshold: slide back and undo the fade
  ParallelAnimation {
    id: snapBack
    NumberAnimation {
      target: shift
      property: "x"
      to: 0
      duration: Appearance.animFast
      easing.type: Appearance.easing
    }
    NumberAnimation {
      target: root
      property: "opacity"
      to: 1
      duration: Appearance.animFast
      easing.type: Appearance.easing
    }
  }

  ParallelAnimation {
    id: appear
    NumberAnimation {
      target: root
      property: "opacity"
      from: 0
      to: 1
      duration: Appearance.animNormal
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: shift
      property: "y"
      from: -8
      to: 0
      duration: Appearance.animNormal
      easing.type: Easing.OutCubic
    }
  }

  SequentialAnimation {
    id: slideOut
    PauseAnimation {
      id: slideDelay
    }
    ParallelAnimation {
      NumberAnimation {
        target: shift
        property: "x"
        to: shift.x < 0 ? -root.width : root.width
        duration: Appearance.animNormal
        easing.type: Easing.InCubic
      }
      NumberAnimation {
        target: root
        property: "opacity"
        to: 0
        duration: Appearance.animNormal
      }
    }
    ScriptAction {
      // Snapshot: each dismiss shrinks the live list
      script: {
        if (root._dismissing)
          root.entries.slice().forEach(e => NotificationManager.dismiss(e.uid));
      }
    }
  }

  // The collapsed rest of the group, peeking out under the card
  Repeater {
    model: root.stackDepth

    Rectangle {
      required property int index
      z: -1 - index
      anchors.horizontalCenter: parent.horizontalCenter
      width: card.width - 16 * (index + 1)
      height: Widget.smallHeight
      y: card.height - height + root.stackStep * (index + 1)
      radius: Widget.radius
      color: Theme.backgroundAlt
      opacity: 0.7 - index * 0.25
    }
  }

  Rectangle {
    id: card
    width: parent.width
    height: body.implicitHeight + Widget.padding * 2
    clip: true
    radius: Widget.radius
    color: hover.hovered ? Qt.tint(Theme.backgroundAlt, Qt.alpha(Theme.backgroundHighlight, 0.4)) : Theme.backgroundAlt
    border.width: root.group?.critical ? Appearance.borderWidth : 0
    border.color: Qt.alpha(Theme.error, 0.6)

    Behavior on height {
      NumberAnimation {
        duration: Appearance.animNormal
        easing.type: Easing.OutCubic
      }
    }
    ColorGlide on color {}

    HoverHandler {
      id: hover
    }

    // Critical urgency
    Rectangle {
      visible: root.group?.critical ?? false
      x: 4
      width: Widget.px(3)
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.margins: Widget.padding
      radius: 1.5
      color: Theme.error
    }

    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Widget.padding
      spacing: Widget.spacing

      // App header
      Item {
        Layout.fillWidth: true
        implicitHeight: header.implicitHeight

        TapHandler {
          enabled: root.count > 1
          onTapped: root.expanded = !root.expanded
        }
        HoverHandler {
          cursorShape: root.count > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        RowLayout {
          id: header
          width: parent.width
          spacing: Widget.spacing

          NotificationAvatar {
            appIcon: root.group?.appIcon ?? ""
            desktopEntry: root.group?.desktopEntry ?? ""
            size: Widget.px(18)
          }

          StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: (root.group?.appName ?? "") + (root.count > 1 ? "  ·  " + root.count : "")
            textColor: Theme.foregroundAlt
            textSize: Appearance.fontSizeBy(-2)
            font.bold: true
          }

          Item {
            implicitWidth: Math.max(newest.implicitWidth, Widget.smallHeight)
            implicitHeight: Widget.smallHeight

            StyledText {
              id: newest
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              opacity: hover.hovered ? 0 : 0.7
              text: {
                void root.now;
                return I18n.formatRelative(root.group?.newestTime ?? Date.now());
              }
              textColor: Theme.foregroundAlt
              textSize: Appearance.fontSizeBy(-3)

              Glide on opacity {}
            }

            StyledIconButton {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Widget.smallHeight
              height: Widget.smallHeight
              visible: opacity > 0
              opacity: hover.hovered ? 1 : 0
              iconText: "close"
              iconSize: Appearance.fontSizeBy(-2)
              borderRadius: width / 2
              iconColor: Theme.foregroundAlt
              hoverColor: Theme.background
              tooltipText: I18n.tr(root.count > 1 ? "Dismiss all" : "Dismiss")
              onClicked: root.dismissAll()

              Glide on opacity {}
            }
          }

          StyledIcon {
            visible: root.count > 1
            text: "expand_more"
            textColor: Theme.foregroundAlt
            rotation: root.expanded ? 180 : 0

            Behavior on rotation {
              NumberAnimation {
                duration: Appearance.animNormal
                easing.type: Easing.OutCubic
              }
            }
          }
        }
      }

      Repeater {
        model: ScriptModel {
          values: root.expanded ? root.entries : root.entries.slice(0, 1)
          objectProp: "uid"
        }

        ColumnLayout {
          id: row
          required property var modelData
          required property int index
          Layout.fillWidth: true
          spacing: Widget.spacing

          // Glides up into the room an entry dismissed above it leaves
          property bool placed: false
          Component.onCompleted: Qt.callLater(() => row.placed = true)
          Glide on y {
            enabled: row.placed
            duration: Appearance.animNormal
          }

          StyledSeparator {
            visible: row.index > 0
            Layout.fillWidth: true
            separatorHeight: 1
            separatorColor: Theme.backgroundHighlight
          }

          NotificationItemDelegate {
            entry: row.modelData
            now: root.now
            showMeta: root.count > 1
            showTime: root.expanded
            swipeable: root.expanded
          }
        }
      }

      StyledText {
        visible: root.stacked
        Layout.fillWidth: true
        text: I18n.tr("+{0} more", root.count - 1)
        textColor: Theme.accent
        textSize: Appearance.fontSizeBy(-3)

        TapHandler {
          onTapped: root.expanded = true
        }
        HoverHandler {
          cursorShape: Qt.PointingHandCursor
        }
      }
    }
  }
}
