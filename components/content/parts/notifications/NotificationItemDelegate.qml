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
  // The card's clock, so relative times refresh
  property real now: Date.now()
  // A lone entry leaves the time and dismiss button to its group's header
  property bool showMeta: true
  // Collapsed, the header's time is already this one's
  property bool showTime: true
  property real swipeThreshold: 120
  // Off while its group's card swipes away whole instead
  property bool swipeable: true

  readonly property bool hovered: hover.hovered

  function dismiss() {
    if (!slideOut.running)
      slideOut.start();
  }

  Layout.fillWidth: true
  implicitHeight: layout.implicitHeight
  opacity: 0

  Component.onCompleted: appear.start()

  transform: Translate {
    id: shift
  }

  HoverHandler {
    id: hover
  }

  DragHandler {
    id: swipe
    enabled: root.swipeable
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
        root.dismiss();
      else
        snapBack.start();
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

  ParallelAnimation {
    id: snapBack
    NumberAnimation {
      target: shift
      property: "x"
      to: 0
      duration: Appearance.animFast
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: root
      property: "opacity"
      to: 1
      duration: Appearance.animFast
    }
  }

  SequentialAnimation {
    id: slideOut
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
      script: NotificationManager.dismiss(root.entry?.uid ?? "")
    }
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
            width: Widget.smallHeight
            height: Widget.smallHeight
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
        notification: root.live
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
