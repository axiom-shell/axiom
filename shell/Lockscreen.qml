pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.services.session
import qs.components.surfaces.lockscreen

// The built-in locker (Lockscreen.mode "quickshell"): a Wayland session
// lock (ext-session-lock-v1). While it holds, the compositor
// shows only the lock surfaces, one per screen, and routes all input to
// them; if qs dies, the session stays locked. Locking comes from
// LockManager.lock(); the only way out is AuthManager's PAM success.
// Also the layouts editor's preview of the lock screen, which locks
// nothing.
Scope {
  id: root

  // Survives QML reloads, so reloading the config while locked comes back
  // locked (a plain property would reset to false and unlock)
  PersistentProperties {
    id: lockState
    reloadableId: "axiomLockscreen"

    property bool locked: false
  }

  // The lock surfaces built: WlSessionLock builds one per Wayland output
  // while locked, also for an output connected later
  property int surfaces: 0

  Connections {
    target: LockManager

    function onLockRequested() {
      if (LockManager.mode !== "quickshell" || lockState.locked)
        return;
      AuthManager.cancel();
      lockState.locked = true;
    }
  }

  Connections {
    target: AuthManager

    function onAuthenticationSucceeded() {
      lockState.locked = false;
    }
  }

  Binding {
    target: LockManager
    property: "builtinLocked"
    value: lockState.locked
  }

  // The compositor has acknowledged the lock: what axiom waits for before
  // `axiom lock` succeeds
  Binding {
    target: LockManager
    property: "builtinSecure"
    value: lockState.locked && sessionLock.secure
  }

  Binding {
    target: LockManager
    property: "builtinSurfaces"
    value: root.surfaces
  }

  // axiom restarts a shell that died while locked with this set: it locks
  // before anything else shows
  Component.onCompleted: {
    if (Quickshell.env("AXIOM_LOCK_ON_START") === "1")
      LockManager.lock();
  }

  WlSessionLock {
    id: sessionLock
    locked: lockState.locked

    WlSessionLockSurface {
      id: surface
      color: "black"

      Component.onCompleted: root.surfaces++
      Component.onDestruction: root.surfaces--

      LockSurface {
        screen: surface.screen
      }
    }
  }

  LazyLoader {
    active: LockManager.editor.previewing && !lockState.locked

    LockPreviewWindow {
      // Quickshell's list, not General.outputs: there's always a screen to
      // put it on, a stand-in one while no monitor is connected
      screen: Quickshell.screens.find(screen => screen.name === LockManager.editor.previewScreen) ?? Quickshell.screens[0]
    }
  }
}
