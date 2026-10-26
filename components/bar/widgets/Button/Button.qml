pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs.config
import qs.services.core
import qs.services.session
import qs.services.ui
import qs.components.reusable
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
  text: properties.labelCommand ? commandLabel : properties.label
  showText: text !== ""

  function runAction() {
    switch (properties.action) {
    case "powerMenu":
      ShellManager.openPowerMenu();
      break;
    case "appLauncher":
      ShellManager.toggleAppLauncher();
      break;
    case "overlay":
      ShellManager.toggleOverlay();
      break;
    case "overlayPage":
      ShellManager.openOverlayPage(properties.page);
      break;
    case "workspaceOverlay":
      ShellManager.toggleWorkspaceOverlay();
      break;
    case "edgeMenu":
      EdgeMenuManager.toggle(properties.menu, root);
      break;
    case "lock":
      SessionManager.sessionAction("lock");
      break;
    case "command":
      runCommand(properties.command);
      break;
    }
  }

  // The surface an action toggles, which hovering never closes
  readonly property var _surfaceFor: ({
      "powerMenu": "powermenu",
      "appLauncher": "launcher",
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
  // the hover popout (popout.enabled), which closes on leave and ranks as one
  Timer {
    interval: PopoutsConfig.openDelay
    running: root.hovered && root.properties.hoverActivate && root.properties.action !== "none" && root.properties.action !== "edgeMenu"
    onTriggered: root.hoverAction()
  }

  // Tooltip after hovering for a moment, on the bar's inner side
  LazyLoader {
    active: root.hovered && root.properties.tooltip !== ""
    StyledToolTip {
      target: root
      text: root.properties.tooltip
      edges: root.barConfig.top ? Edges.Bottom : root.barConfig.bottom ? Edges.Top : root.barConfig.left ? Edges.Right : Edges.Left
    }
  }
}
