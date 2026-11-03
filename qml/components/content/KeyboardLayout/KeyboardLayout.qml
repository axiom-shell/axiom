pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.session
import qs.components.reusable
import qs.components.content.base

// The greeter's keyboard layout (x-hosts: greeter only): the active one,
// and a click switches to the next (the layouts the greeter's compositor
// has: Input's while its keyboard part is on, else its own). In the layouts
// editor's preview it shows a stand-in.
Card {
  id: root

  readonly property bool live: root.host?.kind === "greeter" && root.host.preview !== true && Paths.greeter
  readonly property bool canSwitch: root.live && GreetdManager.layouts.length > 1

  MouseArea {
    id: area
    anchors.fill: parent
    enabled: root.canSwitch
    hoverEnabled: true
    cursorShape: root.canSwitch ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: GreetdManager.nextLayout()
  }

  RowLayout {
    anchors.centerIn: parent
    width: Math.min(implicitWidth, parent.width - root.pad * 2)
    spacing: Widget.spacing

    StyledIcon {
      text: "keyboard"
      textColor: area.containsMouse ? Theme.accent : Theme.foreground
    }

    StyledText {
      Layout.fillWidth: true
      elide: Text.ElideRight
      text: root.live ? GreetdManager.activeLayout : I18n.tr("Keyboard layout")
      textColor: area.containsMouse ? Theme.accent : Theme.foreground
    }
  }
}
