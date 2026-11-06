pragma Singleton
import QtQuick

import qs.config
import qs.services.compositor
import qs.services.core

/* The session actions (lock, suspend, hibernate, log out, restart, shut
   down), shared by the power menu, the QuickActions and Power modules and
   the launcher */
QtObject {
  id: root

  // The destructive ones ask for a second click first (on a tile, the
  // power menu, the launcher; a keybind runs them at once)
  readonly property var destructiveActions: ["logout", "reboot", "poweroff"]

  // A session action's icon and label, the same everywhere it's offered
  function sessionActionInfo(action) {
    switch (action) {
    case "lock":
      return {
        icon: "lock",
        label: I18n.tr("Lock")
      };
    case "suspend":
      return {
        icon: "bedtime",
        label: I18n.tr("Suspend")
      };
    case "hibernate":
      return {
        icon: "ac_unit",
        label: I18n.tr("Hibernate")
      };
    case "logout":
      return {
        icon: "logout",
        label: I18n.tr("Log out")
      };
    case "reboot":
      return {
        icon: "restart_alt",
        label: I18n.tr("Restart")
      };
    case "poweroff":
      return {
        icon: "power_settings_new",
        label: I18n.tr("Shut down")
      };
    }
    return null;
  }

  function sessionAction(action) {
    switch (action) {
    case "lock":
      LockManager.lock();
      break;
    case "suspend":
      CommandManager.runDetached("systemctl suspend");
      break;
    case "hibernate":
      CommandManager.runDetached("systemctl hibernate");
      break;
    case "logout":
      CompositorManager.exitSession();
      break;
    case "reboot":
      CommandManager.runDetached("systemctl reboot");
      break;
    case "poweroff":
      CommandManager.runDetached("systemctl poweroff");
      break;
    default:
      console.warn("[SessionManager] Unknown session action:", action);
    }
  }

  // Keybind actions suspend, hibernate, reboot and poweroff: axiom ipc
  // session <action>, at once (a key is picked on purpose; hot corners
  // can't run the destructive ones). Log out is the compositor's own
  // exitSession bind; lock is lockscreen's
  property IpcTarget _ipc: IpcTarget {
    target: "session"
    enabled: !Paths.greeter

    function suspend(): void {
      root.sessionAction("suspend");
    }

    function hibernate(): void {
      root.sessionAction("hibernate");
    }

    function logout(): void {
      root.sessionAction("logout");
    }

    function reboot(): void {
      root.sessionAction("reboot");
    }

    function poweroff(): void {
      root.sessionAction("poweroff");
    }
  }
}
