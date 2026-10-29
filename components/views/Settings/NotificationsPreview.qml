pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.system
import qs.components.reusable

// The top of the Notifications card (the section's `x-intro`): a Show
// button sending a test notification, toasted with the settings as edited,
// as the OSD and dock cards' Show
RowLayout {
  id: root

  spacing: Widget.spacing

  StyledText {
    text: NotificationManager.dnd ? I18n.tr("Do not disturb is on: a test notification goes only to the history.") : I18n.tr("Show sends a test notification, toasted with the settings below as edited.")
    textColor: NotificationManager.dnd ? Theme.warning : Theme.foregroundAlt
    textSize: Appearance.fontSizeBy(-2)
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  StyledTextButton {
    implicitHeight: Widget.height - Widget.px(4)
    iconText: "visibility"
    text: I18n.tr("Show")
    onClicked: NotificationManager.sendNotification("axiom", I18n.tr("A test notification"), I18n.tr("Change the settings below and show another to see them."))
  }
}
