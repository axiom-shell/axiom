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
    textColor: root.hovered ? Theme.accent : Theme.foregroundAlt
    textSize: Appearance.fontSizeBy(-1)
  }

  StyledLabel {
    Layout.fillWidth: true
    elide: Text.ElideRight
    text: I18n.tr("Quiet") + "  ·  " + NotificationManager.quietCount
    textColor: root.hovered ? Theme.accent : Theme.foregroundAlt
    textSize: Appearance.fontSizeBy(-2)
    font.bold: true
  }

  // Something new since it was last seen open
  Rectangle {
    visible: NotificationManager.quietUnseen
    implicitWidth: Widget.px(6)
    implicitHeight: implicitWidth
    radius: width / 2
    color: Theme.accent
  }

  StyledIconButton {
    size: Widget.smallHeight
    iconText: "clear_all"
    iconSize: Appearance.fontSizeBy(-1)
    borderRadius: width / 2
    iconColor: Theme.foregroundAlt
    hoverColor: Theme.background
    tooltipText: I18n.tr("Clear quiet notifications")
    onClicked: NotificationManager.clearQuiet()
  }
}
