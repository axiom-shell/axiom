pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland

import qs.config
import qs.services.compositor
import qs.services.system
import qs.services.ui
import qs.components.reusable
import qs.components.content.parts.notifications

// One notification's toast, anchored to a screen corner by shell/Notifications:
// times out, swipes away, and runs the notification's actions.
PopupWindow {
  id: root

  required property var notification
  // Its history entry's uid ("" for a transient one), taken while it's
  // live: invoking an action can close it
  property string uid: ""
  property var anchorWindow: null

  property int toastWidth: Widget.px(360)
  property int toastMaxHeight: Widget.px(220)
  property int dismissDuration: 5000
  property real dragDismissThreshold: 150
  // The corner it stacks from: the anchor window is a 1px point there, so
  // a right-hand toast ends at it and a bottom one stacks upwards from it
  property bool alignRight: false
  property bool fromBottom: false
  // Distance from the corner along the stack; the host resets it when the
  // stack reflows (an instant move, read as one with the others')
  property int targetY: 0

  signal dismissed
  // The user closed it (not a timeout): the host hides it on every screen
  signal userClosed

  readonly property bool closing: slideOut.running

  implicitWidth: toastWidth
  implicitHeight: Math.min(mainColumn.implicitHeight + Widget.padding * 2, toastMaxHeight)

  // Out until it slides away (hidden meanwhile by a screenshot picker)
  property bool shown: false
  visible: shown && !ShellManager.captureFrozen
  color: "transparent"

  anchor.window: anchorWindow
  // Placed exactly: the compositor mustn't slide it back on screen
  anchor.adjustment: PopupAdjustment.None
  anchor.rect.x: alignRight ? 1 - implicitWidth : 0
  anchor.rect.y: fromBottom ? 1 - targetY - implicitHeight : targetY
  anchor.rect.width: implicitWidth
  anchor.rect.height: implicitHeight

  Component.onCompleted: {
    shown = true;
    slideIn.start();
    // Its blur region, attached only where the compositor blurs regions
    // (attached at all, it claims the window's blur, and Hyprland's layer
    // rules no longer blur it)
    if (CompositorManager.supports.blurRegion === true)
      BackgroundEffect.blurRegion = Qt.binding(() => BlurManager.regions ? cardBlur : null);
  }

  // Only hides the toast — the notification stays tracked so it's still
  // visible/actionable from the bell popout afterwards.
  function dismiss() {
    if (slideOut.running)
      return;
    slideOut.start();
  }

  // Closed by the user; `remove` also takes it out of the history
  function close(remove) {
    if (slideOut.running)
      return;
    if (remove && root.uid)
      NotificationManager.dismiss(root.uid);
    root.userClosed();
    root.dismiss();
  }

  ParallelAnimation {
    id: slideIn
    NumberAnimation {
      target: card
      property: "y"
      from: root.fromBottom ? 16 : -16
      to: 0
      duration: Appearance.animNormal
      easing.type: Appearance.easing
    }
    NumberAnimation {
      target: card
      property: "opacity"
      from: 0
      to: 1
      duration: Appearance.animNormal
      easing.type: Appearance.easing
    }
  }

  NumberAnimation {
    id: slideOut
    target: card
    property: "opacity"
    to: 0
    duration: Appearance.animFast
    easing.type: Appearance.easing
    onFinished: {
      root.shown = false;
      root.dismissed();
    }
  }

  // A drag short of the threshold: slide back and undo the fade
  ParallelAnimation {
    id: snapBack
    NumberAnimation {
      target: dragShift
      property: "x"
      to: 0
      duration: Appearance.animFast
      easing.type: Appearance.easing
    }
    NumberAnimation {
      target: card
      property: "opacity"
      to: 1
      duration: Appearance.animFast
      easing.type: Appearance.easing
    }
  }

  // expireTimeout: 0 is the freedesktop-spec signal for "never expire", a
  // positive one is the app's own duration (ms), -1 leaves it to us
  readonly property bool critical: notification.urgency === NotificationUrgency.Critical
  readonly property bool neverExpires: (NotificationsConfig.appTimeouts && notification.expireTimeout === 0) || (NotificationsConfig.criticalStays && critical)
  readonly property int duration: NotificationsConfig.appTimeouts && notification.expireTimeout > 0 ? notification.expireTimeout : root.dismissDuration

  Timer {
    id: dismissTimer
    interval: root.duration
    running: !root.neverExpires && root.visible && !dragArea.containsMouse
    onTriggered: root.dismiss()
  }

  // Where the compositor blurs only what a window asks: the card, as it
  // slides, fades and is dragged (attached in onCompleted)
  BoxBlurRegion {
    id: cardBlur
    target: content
    moving: [card.y, dragShift.x]
    opacity: card.opacity
  }

  Item {
    id: card
    anchors.fill: parent
    opacity: 0
    // Anchored, so the drag moves it with a transform rather than x
    transform: Translate {
      id: dragShift
    }

    StyledContainer {
      id: content
      anchors.fill: parent
      backgroundColor: Theme.background
      // Solid over a fullscreen window while blur is paused for it
      solid: BlurManager.opaqueOn(root.anchorWindow?.screen ?? null)
      borderColor: root.critical ? Theme.error : Theme.backgroundAlt
      borderWidth: Appearance.borderWidth
      borderRadius: Appearance.borderRadius + 2
      clip: true

      // Critical urgency
      Rectangle {
        visible: root.critical
        x: 4
        width: Widget.px(3)
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Widget.padding
        radius: 1.5
        color: Theme.error
      }

      MouseArea {
        id: dragArea
        anchors.fill: parent
        hoverEnabled: true

        property real pressX: 0
        property real dragDelta: 0

        // In scene coordinates: local ones move with the card being dragged
        function sceneX(mouse) {
          return dragArea.mapToItem(null, mouse.x, mouse.y).x;
        }

        onPressed: mouse => {
          snapBack.stop();
          pressX = sceneX(mouse);
          dragDelta = 0;
        }

        onPositionChanged: mouse => {
          if (!pressed)
            return;
          dragDelta = sceneX(mouse) - pressX;
          dragShift.x = dragDelta * 0.5;
          card.opacity = 1 - Math.abs(dragDelta) / (root.dragDismissThreshold * 2);
          if (Math.abs(dragDelta) > root.dragDismissThreshold)
            root.close(NotificationsConfig.closeRemoves);
        }

        onReleased: {
          if (Math.abs(dragDelta) < root.dragDismissThreshold)
            snapBack.start();
        }

        ColumnLayout {
          id: mainColumn
          anchors.fill: parent
          anchors.margins: Widget.padding
          spacing: Widget.spacing / 2

          RowLayout {
            Layout.fillWidth: true
            spacing: Widget.spacing

            NotificationAvatar {
              Layout.alignment: Qt.AlignTop
              appIcon: root.notification.appIcon ?? ""
              desktopEntry: root.notification.desktopEntry ?? ""
              image: root.notification.image ?? ""
              size: Widget.px(40)
              badge: true
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2

              StyledText {
                Layout.fillWidth: true
                text: root.notification.appName || ""
                textColor: Theme.foregroundAlt
                textSize: Appearance.fontSizeBy(-2)
                font.bold: true
                elide: Text.ElideRight
              }

              NotificationText {
                notification: root.notification
                summaryLines: 2
                bodyLines: 3
                // Without a default action, a click opens its app (as in
                // the history)
                clickable: !!defaultAction || (root.notification.desktopEntry ?? "") !== ""
                onActivated: ranAction => {
                  if (!ranAction)
                    NotificationManager.openApp(root.notification);
                  root.close(NotificationsConfig.removeOnClick);
                }
              }
            }

            StyledIconButton {
              Layout.fillWidth: false
              Layout.fillHeight: false
              Layout.preferredWidth: Widget.smallHeight
              Layout.preferredHeight: Widget.smallHeight
              Layout.alignment: Qt.AlignTop

              iconText: "close"
              iconSize: Appearance.fontSizeBy(-2)
              borderRadius: width / 2
              iconColor: Theme.foregroundAlt
              hoverColor: Theme.backgroundHighlight

              onClicked: root.close(NotificationsConfig.closeRemoves)
            }
          }

          NotificationActions {
            notification: root.notification
            onInvoked: root.close(NotificationsConfig.removeOnClick)
          }
        }
      }
    }
  }
}
