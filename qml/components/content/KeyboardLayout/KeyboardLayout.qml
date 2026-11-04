pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.system
import qs.components.reusable
import qs.components.content.base

// The input source in use (InputSourceManager), by its full name: a click
// switches to the next one, a right click or the wheel steps either way.
// On the lock screen and the login screen only the xkb sources: a password
// field types through the compositor's layout alone, never an input
// method. In the layouts editor's preview it shows a stand-in.
Card {
  id: root

  readonly property bool live: root.host?.preview !== true
  readonly property bool xkbOnly: ["lockscreen", "greeter"].includes(root.host?.kind ?? "")
  readonly property string current: InputSourceManager.currentFor(root.xkbOnly)
  readonly property bool canSwitch: root.live && InputSourceManager.sourcesFor(root.xkbOnly).length > 1

  function _step(direction) {
    if (direction < 0)
      InputSourceManager.prev(root.xkbOnly);
    else
      InputSourceManager.next(root.xkbOnly);
  }

  MouseArea {
    id: area
    anchors.fill: parent
    enabled: root.canSwitch
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: root.canSwitch ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: mouse => root._step(mouse.button === Qt.RightButton ? -1 : 1)
  }

  NotchWheel {
    enabled: root.canSwitch
    onStepped: direction => root._step(direction)
  }

  RowLayout {
    anchors.centerIn: parent
    width: Math.min(implicitWidth, parent.width - root.pad * 2)
    spacing: Widget.spacing

    StyledIcon {
      text: root.live ? InputSourceManager.iconFor(root.current) : "keyboard"
      textColor: area.containsMouse ? Theme.accent : Theme.foreground
    }

    StyledText {
      Layout.fillWidth: true
      elide: Text.ElideRight
      text: root.live && root.current !== "" ? InputSourceManager.labelFor(root.current, "full") : I18n.tr("Keyboard layout")
      textColor: area.containsMouse ? Theme.accent : Theme.foreground
    }
  }
}
