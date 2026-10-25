pragma Singleton
import QtQuick
import Quickshell
import qs.services.core

// Shared on/off state for keeping the session awake. The Wayland idle
// inhibitor itself needs a mapped surface, so shell/IdleInhibit holds one
// while `enabled` is on. Kept across QML reloads, but a restart always
// starts with idle allowed.
//
//   axiom ipc idleInhibit toggle
Singleton {
  id: root

  property alias enabled: _run.enabled

  PersistentProperties {
    id: _run
    reloadableId: "axiomIdleInhibit"
    property bool enabled: false
  }

  function toggle() {
    root.enabled = !root.enabled;
  }

  property IpcTarget _ipc: IpcTarget {
    target: "idleInhibit"

    function toggle(): void {
      root.toggle();
    }

    function enable(): void {
      root.enabled = true;
    }

    function disable(): void {
      root.enabled = false;
    }

    function status(): bool {
      return root.enabled;
    }
  }
}
