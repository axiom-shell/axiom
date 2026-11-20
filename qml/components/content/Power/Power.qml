pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.core
import qs.services.session
import qs.components.content.base
import qs.components.content.parts

// Power buttons for the lock screen and the greeter (x-hosts: those two
// only): suspend, restart and shut down, nothing else (never log out or
// unlock), with SessionManager's icons and words. Restart and shut down
// ask for a second click. The lock screen runs them as the session
// (SessionManager.sessionAction), the greeter as greetd's user
// (GreetdManager.power); in the layouts editor's preview they do nothing.
// properties: { style: "auto" | "tiles" | "pills", labels: "auto" | "show" | "hide",
//               actions: ["suspend" | "hibernate" | "reboot" | "poweroff"] }
Card {
  id: root

  readonly property string kind: root.host?.kind ?? ""
  readonly property bool live: root.host?.preview !== true && (root.kind === "greeter" ? Paths.greeter : root.kind === "lockscreen" && !Paths.greeter)
  // The schema's four, whatever the file says (never log out or lock
  // here), less what this machine can't do (hibernate without
  // SessionManager.canHibernate)
  readonly property var actions: root.properties.actions.filter(a => ["suspend", "hibernate", "reboot", "poweroff"].includes(a) && SessionManager.sessionActionInfo(a) !== null)

  function press(action) {
    if (!gate.pass(action, SessionManager.destructiveActions.includes(action)) || !root.live)
      return;
    if (root.kind === "greeter") // lock-inert: the greeter's alone
      GreetdManager.power(action);
    else
      SessionManager.sessionAction(action); // allowed: the lock screen's, whose x-lockActions cover SessionManager.sessionAction
  }

  ConfirmGate {
    id: gate
  }

  ActionTiles {
    anchors.fill: parent
    anchors.margins: root.pad
    style: root.properties.style
    labels: root.properties.labels
    tiles: root.actions.map(a => ({
          "icon": SessionManager.sessionActionInfo(a).icon,
          "label": SessionManager.sessionActionInfo(a).label,
          "active": gate.armed === a,
          "tone": SessionManager.destructiveActions.includes(a) ? "error" : "accent",
          "countdown": gate.armed === a ? gate.timeout : 0
        }))
    onClicked: index => root.press(root.actions[index])
  }
}
