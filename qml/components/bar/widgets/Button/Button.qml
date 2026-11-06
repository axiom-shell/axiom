pragma ComponentBehavior: Bound

import QtQuick

import qs.config
import qs.services.core
import qs.services.ui
import qs.components.bar.widgets.base

// An icon (and optional label) that runs a built-in shell action or a
// shell command. Right and middle click can run their own commands, and
// the label can come from a command re-run on an interval.
BarIconWidget {
  id: root

  // First line of the label command's output (CommandManager runs it)
  readonly property string commandLabel: (CommandManager.outputs[properties.labelCommand] ?? "").split("\n")[0]

  readonly property var labelRequest: ({
      "command": root.properties.labelCommand,
      "interval": root.properties.labelInterval
    })
  onLabelRequestChanged: CommandManager.acquire(root, labelRequest)
  Component.onCompleted: CommandManager.acquire(root, labelRequest)
  Component.onDestruction: CommandManager.release(root)

  icon: properties.icon
  text: gate.armed !== "" ? I18n.tr("Confirm?") : properties.labelCommand ? commandLabel : properties.label
  showText: text !== ""

  // Log out, restart and shut down ask for a second click, as on a tile
  ConfirmGate {
    id: gate
  }

  // Its click: a page, an edge menu (at the button) or a command of its
  // own, else the shell's action (ActionsManager)
  function runAction() {
    switch (properties.action) {
    case "overlayPage":
      ShellManager.openOverlayPage(properties.page);
      break;
    case "edgeMenu":
      EdgeMenuManager.toggle(properties.menu, root);
      break;
    case "command":
      runCommand(properties.command);
      break;
    case "none":
      break;
    default:
      if (gate.pass(properties.action, ActionsManager.destructive(properties.action)))
        ActionsManager.run(properties.action, {
          "fromScreen": true
        });
    }
  }

  // The surface an action toggles, which hovering never closes
  readonly property var _surfaceFor: ({
      "powerMenu": "powermenu",
      "launcher": "launcher",
      "overlay": "overlay",
      "overlayPage": "overlay"
    })

  function hoverAction() {
    const surface = _surfaceFor[properties.action];
    if (surface && SurfaceManager.surfaceOpen(surface))
      return;
    runAction();
  }

  function runCommand(command) {
    if (!command)
      return;
    CommandManager.runDetached(command);
    // The command may change what the label shows (e.g. a toggle)
    if (properties.labelCommand)
      labelRefresh.restart();
  }

  // Shortly after a click, so the command has had time to act
  Timer {
    id: labelRefresh
    interval: 250
    onTriggered: CommandManager.refresh(root.properties.labelCommand)
  }

  clickable: true
  hoverOutline: true
  acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
  onClicked: button => {
    if (button === Qt.RightButton)
      root.runCommand(root.properties.rightCommand);
    else if (button === Qt.MiddleButton)
      root.runCommand(root.properties.middleCommand);
    else
      root.runAction();
  }

  // "Activate on hover": the click action once per hover, after the
  // popout open delay. Not an edge menu's (as the schema shows it): that's
  // the hover popout (popout.enabled), which closes on leave and ranks as one.
  // Never a session action's: resting the pointer on the button mustn't
  // lock the screen or end the session
  Timer {
    interval: PopoutsConfig.openDelay
    running: root.hovered && root.properties.hoverActivate && !["none", "edgeMenu"].concat(ActionsManager.sessionActions).includes(root.properties.action)
    onTriggered: root.hoverAction()
  }

  BarToolTip {
    widget: root
    text: root.properties.tooltip
  }
}
