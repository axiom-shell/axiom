pragma ComponentBehavior: Bound

import QtQuick

import qs.config
import qs.services.system
import qs.services.ui
import qs.components.reusable
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// The notification bell: a badge with the count (or the count or the
// newest alert's app as its label), the do-not-disturb icon
// while it's on. Click toggles do-not-disturb, middle click clears every
// notification; hovering opens the notification list.
BarIconWidget {
  id: root

  icon: NotificationManager.dnd ? "notifications_off" : "notifications"
  readonly property string labelKind: properties.label
  text: labelKind === "count" ? (NotificationManager.count > 0 ? NotificationManager.countLabel : "") : labelKind === "lastApp" ? NotificationManager.alerts[0]?.appName ?? "" : ""
  // With nothing to say (no alerts) it shows the bell alone
  showText: labelKind !== "none" && text !== ""
  minimumText: labelKind === "count" ? "00" : ""
  textFormat: Text.PlainText
  iconColor: NotificationManager.dnd ? Theme.resolveColor(properties.dndColor) : colors.icon

  // News: the unread count rose, with do-not-disturb off
  attentionLevel: NotificationManager.count
  attentionMuted: NotificationManager.dnd

  clickable: true
  acceptedButtons: Qt.LeftButton | Qt.MiddleButton
  onClicked: button => {
    if (button === Qt.MiddleButton)
      ActionsManager.run("clearNotifications");
    else {
      ActionsManager.run("toggleDnd", {
        "fromScreen": true
      });
    }
  }

  // On the icon's top-right corner, which on a narrow bar reaches past
  // the widget's box: drawn in its host (where the widget sits at 0, 0),
  // as the widget clips to its box (BaseWidget)
  CountBadge {
    parent: root.parent
    shown: root.properties.showCount && root.labelKind !== "count" && NotificationManager.count > 0
    x: Math.round(root.iconRect.x + root.iconRect.width - width / 2)
    y: 1
    color: Theme.resolveColor(root.properties.badgeColor)
    text: NotificationManager.countLabel
    // The bar's own text size, not the Interface scale
    textSize: Math.round(root.fontSize * 0.7)
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "Notifications"
    active: EdgeMenusConfig.opensOwnPopout(root.properties)
    openDelay: 150
  }
}
