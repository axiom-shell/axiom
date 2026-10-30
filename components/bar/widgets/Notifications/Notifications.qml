pragma ComponentBehavior: Bound

import QtQuick

import qs.config
import qs.services.system
import qs.components.reusable
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// The notification bell: a badge with the count, the do-not-disturb icon
// while it's on. Click toggles do-not-disturb, middle click clears every
// notification; hovering opens the notification list.
BarIconWidget {
  id: root

  icon: NotificationManager.dnd ? "notifications_off" : "notifications"
  showText: false
  iconColor: NotificationManager.dnd ? Theme.resolveColor(properties.dndColor) : colors.icon

  clickable: true
  acceptedButtons: Qt.LeftButton | Qt.MiddleButton
  onClicked: button => {
    if (button === Qt.MiddleButton)
      NotificationManager.clearAll();
    else
      NotificationManager.toggleDnd();
  }

  // On the icon's top-right corner, which on a narrow bar reaches past
  // the widget's box: drawn in its host (where the widget sits at 0, 0),
  // as the widget clips to its box (BaseWidget)
  CountBadge {
    parent: root.parent
    shown: root.properties.showCount && NotificationManager.count > 0
    x: Math.round((root.width + root.iconLength) / 2 - width / 2)
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
