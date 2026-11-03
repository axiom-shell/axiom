pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.ui
import qs.components.reusable

// One line atop the settings page while dev mode is on (SettingsContent):
// which tree and checkout run, and on which config. A click opens the
// Development category
Rectangle {
  id: root

  // What it says: dev mode, the tree, its checkout, the config it edits
  readonly property string text: {
    const parts = [I18n.tr("Dev mode"), Paths.shortenHome(DevManager.tree)];
    if (DevManager.checkout !== "")
      parts.push(DevManager.checkout);
    parts.push(DevManager.active ? I18n.tr("dev config") : I18n.tr("live config until the dev build runs"));
    return parts.filter(part => part !== "").join(" · ");
  }

  implicitHeight: row.implicitHeight + Widget.smallPadding * 2
  radius: Widget.radius
  color: mouse.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.accent, 0.15)
  border.color: Qt.alpha(Theme.accent, 0.5)
  border.width: Appearance.borderWidth

  ColorGlide on color {}

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.leftMargin: Widget.padding
    anchors.rightMargin: Widget.padding
    spacing: Widget.spacing

    StyledIcon {
      text: DevManager.building ? "progress_activity" : "code"
      textColor: DevManager.buildFailed ? Theme.error : Theme.accent
    }

    StyledText {
      text: root.text
      elide: Text.ElideMiddle
      Layout.fillWidth: true
    }

    StyledIcon {
      text: "chevron_right"
      opacity: 0.6
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: SettingsManager.openCategory("Development")
  }
}
