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
  // A group of silent ones (the Quiet section): a fainter card
  property bool quiet: false

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
    swipe.slideOut(delay);
  }

  Layout.fillWidth: true
  implicitHeight: card.height + root.stackDepth * root.stackStep
  opacity: 0

  // Glides into place when a group above it comes or goes; not on its
  // own arrival, which its swipe's fade in animates
  property bool _placed: false
  Component.onCompleted: Qt.callLater(() => root._placed = true)
  Glide on y {
    enabled: root._placed
    duration: Appearance.animNormal
  }
  onCountChanged: {
    if (root.count <= 1)
      root.expanded = false;
  }

  transform: swipe.shift

  NotificationSwipe {
    id: swipe
    enabled: !root.expanded
    onSwiped: root.dismissAll()
    // Snapshot: each dismiss shrinks the live list
    onOut: {
      if (root._dismissing)
        root.entries.slice().forEach(e => NotificationManager.dismiss(e.uid));
    }
  }

  // The collapsed rest of the group, peeking out under the card
  Repeater {
    model: root.stackDepth

    Surface {
      required property int index
      tone: root.quiet ? "sunken" : "raised"
      outlined: true
      z: -1 - index
      anchors.horizontalCenter: parent.horizontalCenter
      width: card.width - 16 * (index + 1)
      height: Widget.smallHeight
      y: card.height - height + root.stackStep * (index + 1)
      radius: Style.radius
    }
  }

  Surface {
    id: card
    tone: root.quiet ? "sunken" : "raised"
    outlined: root.group?.critical ?? false
    width: parent.width
    height: body.implicitHeight + Widget.padding * 2
    clip: true
    radius: Widget.radius
    border.color: Style.error

    Glide on height {
      duration: Appearance.animNormal
    }

    StateLayer {
      anchors.fill: parent
      hovered: hover.hovered
      radius: card.radius
    }

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
      color: Style.error
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

          StyledLabel {
            Layout.fillWidth: true
            role: "caption"
            overflow: "line"
            text: (root.group?.appName ?? "") + (root.count > 1 ? "  ·  " + root.count : "")
            font.weight: Style.weightStrong
          }

          Item {
            implicitWidth: Math.max(newest.implicitWidth, Widget.smallHeight)
            implicitHeight: Math.max(Widget.smallHeight, newest.implicitHeight)

            StyledLabel {
              id: newest
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              opacity: hover.hovered ? 0 : 1
              text: {
                void root.now;
                return I18n.formatRelative(root.group?.newestTime ?? Date.now());
              }
              role: "micro"
              tone: "faint"

              Glide on opacity {}
            }

            StyledIconButton {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              size: Math.max(Widget.smallHeight, Style.iconXs + Widget.spacing * 2)
              visible: opacity > 0
              opacity: hover.hovered ? 1 : 0
              iconText: "close"
              iconSize: Style.iconXs
              borderRadius: width / 2
              iconColor: Style.textMuted
              tooltipText: I18n.tr(root.count > 1 ? "Dismiss all" : "Dismiss")
              onClicked: root.dismissAll()

              Glide on opacity {}
            }
          }

          StyledIcon {
            visible: root.count > 1
            text: "expand_more"
            tone: "muted"
            rotation: root.expanded ? 180 : 0

            Glide on rotation {
              duration: Appearance.animNormal
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
            backTone: root.quiet ? "sunken" : "raised"
            Layout.fillWidth: true
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
        role: "micro"
        tone: "accent"

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
