pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.services.system
import qs.config
import qs.components.reusable

// The notification menu's Quiet section heading: silent notifications'
// count, a dot while one came in since it was last seen open
// (NotificationManager.quietUnseen), a clear button and a chevron, the row
// folding them open and shut (NotificationManager.quietOpen)
FoldRow {
  id: root

  open: NotificationManager.quietOpen
  onToggled: NotificationManager.setQuietOpen(!NotificationManager.quietOpen)

  StyledIcon {
    text: "notifications_none"
    tone: root.hovered ? "accent" : "muted"
    size: "sm"
  }

  StyledLabel {
    Layout.fillWidth: true
    role: "micro"
    text: I18n.tr("Quiet") + "  ·  " + NotificationManager.quietCount
    tone: root.hovered ? "accent" : "muted"
  }

  // Something new since it was last seen open
  Rectangle {
    visible: NotificationManager.quietUnseen
    implicitWidth: Widget.px(6)
    implicitHeight: implicitWidth
    radius: width / 2
    color: Style.accent
  }

  StyledIconButton {
    size: Math.max(Widget.smallHeight, Style.iconSm + Widget.spacing * 2)
    iconText: "clear_all"
    iconSize: Style.iconSm
    borderRadius: width / 2
    iconColor: Style.textMuted
    tooltipText: I18n.tr("Clear quiet notifications")
    onClicked: NotificationManager.clearQuiet()
  }
}
