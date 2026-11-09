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

  // Whether logind can hibernate this machine (asked once at start: no
  // swap or a locked-down kernel says "na"), so hibernate is offered only
  // where it works
  property bool canHibernate: false

  Component.onCompleted: {
    CommandManager.run(["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "CanHibernate"], (code, stdout) => {
      // "yes", or "challenge" when polkit asks first
      root.canHibernate = code === 0 && /"(yes|challenge)"/.test(stdout);
    });
  }

  // A session action's icon and label, the same everywhere it's offered
  // (null for one this machine can't do: hibernate without canHibernate)
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
      if (!root.canHibernate)
        return null;
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
      if (!root.canHibernate) {
        console.warn("[SessionManager] This machine can't hibernate (logind's CanHibernate)");
        break;
      }
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
