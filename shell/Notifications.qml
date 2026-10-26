pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland

import qs.services.compositor
import qs.services.system
import qs.services.ui
import qs.config
import qs.components.surfaces.notifications

// Stacks incoming notifications as toasts from a corner of the work area
// (NotificationsConfig), driven by NotificationManager.showPopup: one stack
// per screen NotificationsConfig.screen builds it on, each showing a toast
// when ShellManager.showsOn its screen. Dismissing a toast only hides it
// (unless closeRemoves / removeOnClick): the notification stays tracked and
// remains visible/actionable from the bell popout.
Scope {
  id: root

  property int stackSpacing: Widget.padding
  property int toastMaxHeight: Widget.px(220)
  property real dragDismissThreshold: 150

  // A toast the user closed on one screen goes on every screen
  signal toastClosed(var notification)

  Variants {
    model: General.screensFor(NotificationsConfig.screen)

    delegate: Scope {
      id: stack
      required property ShellScreen modelData

      property var activeToasts: []

      // Invisible anchor window the toast PopupWindows position relative to,
      // in the chosen corner of the work area. Normal exclusion with no zone of
      // its own keeps it inside the space the bars, the border (and any other
      // app's panels) reserve, as OverlayPanel does, so the gaps are measured
      // from whatever is at each edge. A transparent bar reserves Hyprland's
      // gaps_out less than it draws (see BarPanel) and shows only its widgets,
      // `inset` inside its window: the gap starts at their inner edge instead.
      // Over a fullscreen window nothing else shows, so the gaps are measured
      // from the screen's edges instead.
      readonly property bool fullscreen: CompositorManager.hasFullscreen(stack.modelData?.name ?? "")
      readonly property var _edges: ScreenEdgeManager.edgesFor(stack.modelData)
      function _edgeGap(side, gap) {
        const bar = stack._edges[side];
        if (stack.fullscreen)
          return gap;
        if (bar?.background !== "transparent")
          return gap;
        return gap + (CompositorManager.gapsOut[side] ?? 0) - (bar.inset ?? 0);
      }

      PanelWindow {
        id: anchorPanel
        visible: true
        screen: stack.modelData

        implicitWidth: 1
        implicitHeight: 1

        anchors {
          top: NotificationsConfig.top
          bottom: !NotificationsConfig.top
          left: NotificationsConfig.left
          right: !NotificationsConfig.left
        }
        margins {
          top: stack._edgeGap("top", NotificationsConfig.gapTop)
          bottom: stack._edgeGap("bottom", NotificationsConfig.gapBottom)
          left: stack._edgeGap("left", NotificationsConfig.gapLeft)
          right: stack._edgeGap("right", NotificationsConfig.gapRight)
        }

        color: "transparent"
        focusable: false
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "axiom-notifications"
        exclusionMode: stack.fullscreen ? ExclusionMode.Ignore : ExclusionMode.Normal
        exclusiveZone: 0

        // Where NotificationManager renders images to cache them: grabbing
        // needs an item in a window (items may lie outside this 1x1 one).
        // The first stack lends it; another takes over if that one goes.
        Item {
          id: imageHost
          x: 1
        }
      }

      Component {
        id: toastComponent

        NotificationToast {
          notification: null // set on creation
          anchorWindow: anchorPanel

          toastWidth: NotificationsConfig.width
          toastMaxHeight: root.toastMaxHeight
          dismissDuration: NotificationsConfig.timeout
          dragDismissThreshold: root.dragDismissThreshold
          alignRight: !NotificationsConfig.left
          fromBottom: !NotificationsConfig.top
        }
      }

      Component.onCompleted: {
        if (!NotificationManager.imageHost)
          NotificationManager.imageHost = imageHost;
      }

      Component.onDestruction: {
        if (NotificationManager.imageHost === imageHost)
          NotificationManager.imageHost = null;
      }

      Connections {
        target: NotificationManager

        function onShowPopup(notification) {
          stack.createToast(notification);
        }

        function onImageHostChanged() {
          if (!NotificationManager.imageHost)
            NotificationManager.imageHost = imageHost;
        }
      }

      Connections {
        target: root

        function onToastClosed(notification) {
          stack.activeToasts.filter(t => t.notification === notification).forEach(t => t.dismiss());
        }
      }

      function createToast(notification) {
        if (!ShellManager.showsOn(stack.modelData, NotificationsConfig.screen))
          return;
        const critical = notification.urgency === NotificationUrgency.Critical;
        if (NotificationsConfig.quietFullscreen && stack.fullscreen && !critical)
          return;

        // Make room: the oldest go (they leave the list once faded out)
        const showing = stack.activeToasts.filter(t => !t.closing);
        showing.slice(0, Math.max(0, showing.length - NotificationsConfig.maxToasts + 1)).forEach(t => t.dismiss());

        const toast = toastComponent.createObject(stack, {
          notification: notification,
          uid: NotificationManager.uidOf(notification),
          targetY: stack.calculateTargetY(stack.activeToasts.length)
        });

        if (!toast) {
          console.warn("[Notifications] Could not create a toast for", notification.summary);
          return;
        }

        stack.activeToasts.push(toast);

        // If the notification is dismissed elsewhere (e.g. from the bell
        // popout) while its toast is still showing, animate the toast out too.
        // Disconnected once the toast is gone, so a later close doesn't call
        // into a destroyed toast.
        const onClosed = () => {
          if (stack.activeToasts.includes(toast))
            toast.dismiss();
        };
        notification.closed.connect(onClosed);
        toast.userClosed.connect(() => root.toastClosed(notification));
        toast.dismissed.connect(() => {
          try {
            notification.closed.disconnect(onClosed);
          } catch (e) {
            // The notification itself is already gone
          }
          stack.removeToast(toast);
        });
      }

      function calculateTargetY(index) {
        let y = 0;
        for (let i = 0; i < index && i < stack.activeToasts.length; i++) {
          y += stack.activeToasts[i].implicitHeight + root.stackSpacing;
        }
        return y;
      }

      function removeToast(toast) {
        const index = stack.activeToasts.indexOf(toast);
        if (index === -1)
          return;
        stack.activeToasts.splice(index, 1);
        stack.updateToastPositions();
        Qt.callLater(() => {
          if (!toast.shown)
            toast.destroy();
        });
      }

      function updateToastPositions() {
        for (let i = 0; i < stack.activeToasts.length; i++) {
          stack.activeToasts[i].targetY = stack.calculateTargetY(i);
        }
      }
    }
  }
}
