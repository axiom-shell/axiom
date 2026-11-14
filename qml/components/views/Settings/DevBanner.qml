pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.components.reusable

// One line atop the settings page while dev mode is on (SettingsContent):
// which tree and checkout run, and on which config. A click opens the
// Development category (turning the developer options on first)
Surface {
  id: root
  tone: "accentContainer"

  // What it says: dev mode, the tree, its checkout, the config it edits
  readonly property string text: {
    const parts = [I18n.tr("Dev mode"), Paths.shortenHome(DevManager.tree)];
    if (DevManager.checkout !== "")
      parts.push(DevManager.checkout);
    parts.push(DevManager.active ? I18n.tr("dev config") : I18n.tr("live config until the dev build runs"));
    return parts.filter(part => part !== "").join(" · ");
  }

  implicitHeight: row.implicitHeight + Widget.smallPadding * 2

  StateLayer {
    anchors.fill: parent
    radius: Style.radius
    hovered: mouse.containsMouse
    pressed: mouse.pressed
  }

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.leftMargin: Widget.padding
    anchors.rightMargin: Widget.padding
    spacing: Widget.spacing

    SpinningIcon {
      text: DevManager.building ? "progress_activity" : DevManager.buildFailed ? "error" : "code"
      textColor: root.ink.icon
      spinning: DevManager.building
    }

    StyledLabel {
      text: root.text
      role: "label"
      overflow: "line"
      elide: Text.ElideMiddle // style-exempt: middle elides an identifier, keeping its end
      Layout.fillWidth: true
    }

    StyledIcon {
      text: "chevron_right"
      tone: "muted"
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: DevManager.openDevelopment()
  }
}
