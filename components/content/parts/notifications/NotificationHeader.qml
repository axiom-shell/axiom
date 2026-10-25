pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.services.system
import qs.config
import qs.components.reusable

// The notification menu's title row: bell, title, count pill, then the do
// not disturb toggle and clear all
RowLayout {
  id: root

  signal clearAll

  Layout.fillWidth: true
  spacing: Widget.spacing

  StyledIcon {
    text: NotificationManager.dnd ? "notifications_paused" : "notifications"
    textColor: Theme.accent
    textSize: Appearance.fontSizeBy(2)
  }

  // Shrinks (eliding) before the buttons are pushed out of a narrow card
  StyledText {
    Layout.fillWidth: true
    Layout.maximumWidth: Math.ceil(implicitWidth)
    elide: Text.ElideRight
    text: I18n.tr("Notifications")
    font.bold: true
    textColor: Theme.accent
  }

  Rectangle {
    visible: NotificationManager.count > 0
    implicitWidth: Math.max(implicitHeight, countLabel.implicitWidth + Widget.px(12))
    implicitHeight: countLabel.implicitHeight + Widget.px(4)
    radius: height / 2
    color: Theme.accent

    StyledText {
      id: countLabel
      anchors.centerIn: parent
      text: NotificationManager.countLabel
      textSize: Appearance.fontSizeBy(-3)
      textColor: Theme.background
      font.bold: true
    }
  }

  Item {
    Layout.fillWidth: true
  }

  StyledRectButton {
    size: Widget.iconButton
    iconText: NotificationManager.dnd ? "notifications_paused" : "notifications_off"
    iconColor: NotificationManager.dnd ? Theme.background : Theme.foreground
    backgroundColor: Qt.alpha(Theme.accent, NotificationManager.dnd ? 1 : 0)
    borderHoverColor: Theme.accent
    tooltipText: I18n.tr(NotificationManager.dnd ? "Do not disturb is on" : "Do not disturb")
    onClicked: NotificationManager.toggleDnd()
  }

  StyledRectButton {
    size: Widget.iconButton
    enabled: NotificationManager.count > 0
    opacity: enabled ? 1 : 0.4
    iconText: "clear_all"
    backgroundColor: "transparent"
    borderHoverColor: Theme.error
    tooltipText: I18n.tr("Clear all")
    onClicked: root.clearAll()
  }
}
