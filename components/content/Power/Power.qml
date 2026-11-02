pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.session
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// Power buttons for the lock screen and the greeter (x-hosts: those two
// only): suspend, restart and shut down, nothing else (never log out or
// unlock), with SessionManager's icons and words. Restart and shut down
// ask for a second click. The lock screen runs them as the session
// (SessionManager.sessionAction), the greeter as greetd's user
// (GreetdManager.power); in the layouts editor's preview they do nothing.
// properties: { actions: ["suspend" | "reboot" | "poweroff"] }
Card {
  id: root

  readonly property string kind: root.host?.kind ?? ""
  readonly property bool live: root.host?.preview !== true && (root.kind === "greeter" ? Paths.greeter : root.kind === "lockscreen" && !Paths.greeter)
  // The schema's three, whatever the file says: never log out or lock here
  readonly property var actions: (root.properties.actions ?? []).filter(a => ["suspend", "reboot", "poweroff"].includes(a))

  function press(action) {
    if (!gate.pass(action, SessionManager.destructiveActions.includes(action)) || !root.live)
      return;
    if (root.kind === "greeter")
      GreetdManager.power(action);
    else
      SessionManager.sessionAction(action);
  }

  ConfirmGate {
    id: gate
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
        readonly property var info: SessionManager.sessionActionInfo(action)

        x: grid.tileX(index)
        y: grid.tileY(index)
        width: grid.tileWidth
        height: grid.tileHeight
        icon: info?.icon ?? ""
        label: info?.label ?? ""
        active: gate.armed === action
        activeColor: SessionManager.destructiveActions.includes(action) ? Theme.error : Theme.accent
        countdown: gate.armed === action ? gate.timeout : 0
        onClicked: root.press(action)
      }
    }
  }
}
