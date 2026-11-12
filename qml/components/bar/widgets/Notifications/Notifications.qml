pragma ComponentBehavior: Bound

import QtQuick

import qs.config
import qs.services.system
import qs.services.ui
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// The notification bell: a badge with the count (the base's, over the
// icon's corner, a ring on a fill; or the count or the newest alert's app as
// its label), the do-not-disturb icon (an icon field) while it's on. Click toggles do-not-disturb, middle click clears every
// notification; hovering opens the notification list.
BarWidget {
  id: root

  icon: NotificationManager.dnd ? "notifications_off" : "notifications"
  readonly property string labelKind: properties.label
  text: labelKind === "count" ? (NotificationManager.count > 0 ? NotificationManager.countLabel : "") : labelKind === "lastApp" ? NotificationManager.alerts[0]?.appName ?? "" : ""
  // With nothing to say (no alerts) it shows the bell alone
  showText: labelKind !== "none" && text !== ""
  minimumText: labelKind === "count" ? "00" : ""
  textFormat: Text.PlainText
  iconField: NotificationManager.dnd ? "dndColor" : ""

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

  badge: root.properties.showCount && root.labelKind !== "count" && NotificationManager.count > 0 ? ({
      "text": NotificationManager.countLabel,
      "field": "badgeColor"
    }) : null

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "Notifications"
    active: MenusConfig.opensOwnPopout(root.properties)
    openDelay: 150
  }
}
