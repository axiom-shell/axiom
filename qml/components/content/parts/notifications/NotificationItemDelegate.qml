pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.system
import qs.components.reusable

// One history entry inside a group card: image, summary and body, its time
// (or a dismiss button while hovered) and, while its notification is live,
// its actions and inline reply. Clicking runs the default action, or else opens the app
// (and with NotificationsConfig.removeOnClick dismisses it, as an action
// does). Swipe sideways or press the button to dismiss; it slides out first.
Item {
  id: root

  // A NotificationManager entry
  required property var entry
  readonly property var live: root.entry?.live ? NotificationManager.liveNotification(root.entry.uid) : null
  // A filed one's buttons (no notification behind it), shaped as a live
  // one's for NotificationActions: run by its desktop entry's handler
  readonly property var _filed: !root.live && (root.entry?.actions?.length ?? 0) > 0 ? {
    "actions": root.entry.actions.map(a => ({
          "identifier": a.id,
          "text": a.label,
          "invoke": () => NotificationManager.invokeFiled(root.entry, a.id)
        })),
    "hasActionIcons": false
  } : null
  // The card's clock, so relative times refresh
  property real now: Date.now()
  // A lone entry leaves the time and dismiss button to its group's header
  property bool showMeta: true
  // Collapsed, the header's time is already this one's
  property bool showTime: true
  // Off while its group's card swipes away whole instead
  property bool swipeable: true

  readonly property bool hovered: hover.hovered

  function dismiss() {
    swipe.slideOut(0);
  }

  Layout.fillWidth: true
  implicitHeight: layout.implicitHeight
  opacity: 0

  transform: swipe.shift

  HoverHandler {
    id: hover
  }

  NotificationSwipe {
    id: swipe
    enabled: root.swipeable
    onSwiped: root.dismiss()
    onOut: NotificationManager.dismiss(root.entry?.uid ?? "")
  }

  RowLayout {
    id: layout
    width: parent.width
    spacing: Widget.padding

    NotificationAvatar {
      id: thumb
      visible: thumb.showImage
      Layout.alignment: Qt.AlignTop
      image: root.entry?.image ?? ""
      size: Widget.px(44)
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing / 2

      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing

        NotificationText {
          notification: root.entry
          live: root.live
          clickable: !!defaultAction || (root.entry?.desktopEntry ?? "") !== ""
          onActivated: {
            NotificationManager.activate(root.entry, root.live);
            if (NotificationsConfig.removeOnClick)
              root.dismiss();
          }
          summaryLines: 2
          bodyLines: 3
        }

        Item {
          visible: root.showMeta
          Layout.alignment: Qt.AlignTop
          implicitWidth: Math.max(time.implicitWidth, Widget.smallHeight)
          implicitHeight: Widget.smallHeight

          StyledText {
            id: time
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.hovered || !root.showTime ? 0 : 0.7
            text: {
              void root.now;
              return I18n.formatRelative(root.entry?.time ?? Date.now());
            }
            textColor: Theme.foregroundAlt
            textSize: Appearance.fontSizeBy(-3)

            Glide on opacity {}
          }

          StyledIconButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            size: Widget.smallHeight
            visible: opacity > 0
            opacity: root.hovered ? 1 : 0
            iconText: "close"
            iconSize: Appearance.fontSizeBy(-2)
            borderRadius: width / 2
            iconColor: Theme.foregroundAlt
            hoverColor: Theme.background
            tooltipText: I18n.tr("Dismiss")
            onClicked: root.dismiss()

            Glide on opacity {}
          }
        }
      }

      NotificationActions {
        Layout.topMargin: 2
        notification: root.live ?? root._filed
        onInvoked: {
          if (NotificationsConfig.removeOnClick)
            root.dismiss();
        }
      }

      Loader {
        Layout.fillWidth: true
        active: root.live?.hasInlineReply ?? false
        visible: active
        sourceComponent: NotificationReply {
          notification: root.live
          onSent: {
            if (NotificationsConfig.removeOnClick)
              root.dismiss();
          }
        }
      }
    }
  }
}
