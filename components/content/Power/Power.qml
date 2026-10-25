pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.core
import qs.services.session
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// Power buttons for the lock screen and the greeter (x-hosts: those two
// only): suspend, restart and shut down, nothing else (never log out or
// unlock). Restart and shut down ask for a second click. The lock screen
// runs them as the session (ShellManager.sessionAction), the greeter as
// greetd's user (GreetdManager.power); in the layouts editor's preview
// they do nothing.
// properties: { actions: ["suspend" | "reboot" | "poweroff"] }
Card {
  id: root

  readonly property string kind: root.host?.kind ?? ""
  readonly property bool live: root.host?.preview !== true && (root.kind === "greeter" ? Paths.greeter : root.kind === "lockscreen" && !Paths.greeter)
  readonly property var actions: root.properties.actions ?? []

  // i18n: I18n.tr("Suspend") I18n.tr("Restart") I18n.tr("Shut down")
  readonly property var _info: ({
      "suspend": {
        "icon": "bedtime",
        "label": "Suspend",
        "confirm": false
      },
      "reboot": {
        "icon": "restart_alt",
        "label": "Restart",
        "confirm": true
      },
      "poweroff": {
        "icon": "power_settings_new",
        "label": "Shut down",
        "confirm": true
      }
    })

  // The action waiting for its second click
  property string armed: ""

  function press(action) {
    if (root._info[action].confirm && root.armed !== action) {
      root.armed = action;
      disarm.restart();
      return;
    }
    root.armed = "";
    if (!root.live || !root._info[action])
      return;
    if (root.kind === "greeter")
      GreetdManager.power(action);
    else
      ShellManager.sessionAction(action);
  }

  Timer {
    id: disarm
    interval: 3000
    onTriggered: root.armed = ""
  }

  TileGrid {
    id: grid
    anchors.fill: parent
    anchors.margins: root.pad
    count: root.actions.length

    Repeater {
      model: root.actions.length

      ActionTile {
        required property int index
        readonly property string action: root.actions[index] ?? ""

        x: grid.tileX(index)
        y: grid.tileY(index)
        width: grid.tileWidth
        height: grid.tileHeight
        icon: root._info[action]?.icon ?? ""
        label: root._info[action] ? I18n.tr(root._info[action].label) : ""
        active: root.armed === action
        activeColor: action === "suspend" ? Theme.accent : Theme.error
        countdown: root.armed === action ? disarm.interval : 0
        onClicked: root.press(action)
      }
    }
  }
}
