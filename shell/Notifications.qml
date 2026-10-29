pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.services.system
import qs.config
import qs.components.surfaces.notifications

// The notification toasts: one ToastStack per screen NotificationsConfig.
// screen builds them on, each showing a toast when ShellManager.showsOn
// its screen, driven by NotificationManager.showPopup. Closing a toast only
// hides it (unless closeRemoves / removeOnClick): the notification stays in
// the history. One the user closes, or its app or the list closes, goes on
// every screen. Once no screen shows a notification any more,
// NotificationManager.toastsGone hears of it.
Scope {
  id: root

  signal hideEverywhere(var notification)

  // Tells NotificationManager when no stack holds a toast of it
  function _released(notification) {
    if (stacks.instances.some(s => s.toasts.some(t => t.notification === notification)))
      return;
    NotificationManager.toastsGone(notification);
  }

  Connections {
    target: NotificationManager
    function onShowPopup(notification) {
      notification.closed.connect(() => root.hideEverywhere(notification));
      // (a stack shows none on a screen it doesn't show on, or over a
      // fullscreen window with quietFullscreen)
      Qt.callLater(() => root._released(notification));
    }
  }

  Variants {
    id: stacks
    model: General.screensFor(NotificationsConfig.screen)

    delegate: ToastStack {
      id: stack
      required property ShellScreen modelData
      screen: modelData

      onUserClosed: notification => root.hideEverywhere(notification)
      onDropped: notification => root._released(notification)

      Connections {
        target: NotificationManager
        function onShowPopup(notification) {
          stack.show(notification);
        }
      }

      Connections {
        target: root
        function onHideEverywhere(notification) {
          stack.hideNotification(notification);
        }
      }
    }
  }
}
