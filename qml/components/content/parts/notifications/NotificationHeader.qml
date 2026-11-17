pragma ComponentBehavior: Bound
import QtQuick

import qs.services.system
import qs.services.ui
import qs.config
import qs.components.reusable
import qs.components.content.parts

// The notification menu's title row: bell, title, then the count pill, the
// do not disturb toggle and clear all
ModuleHeader {
  id: root

  signal clearAll

  icon: NotificationManager.dnd ? "notifications_paused" : "notifications"
  title: I18n.tr("Notifications")

  CountBadge {
    shown: NotificationManager.count > 0
    text: NotificationManager.countLabel
    color: Style.accent
    textColor: Style.inkAccent.text
  }

  StyledIconButton {
    kind: NotificationManager.dnd ? "primary" : "text"
    size: Widget.iconButton
    iconText: NotificationManager.dnd ? "notifications_paused" : "notifications_off"
    tooltipText: I18n.tr(NotificationManager.dnd ? "Do not disturb is on" : "Do not disturb")
    onClicked: ActionsManager.run("toggleDnd", {
      "fromScreen": true
    })
  }

  StyledIconButton {
    kind: "text"
    size: Widget.iconButton
    enabled: NotificationManager.count > 0
    iconText: "clear_all"
    tooltipText: I18n.tr("Clear all")
    onClicked: root.clearAll()
  }
}
