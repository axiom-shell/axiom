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

  // Survives QML reloads, so a reload never unlocks (a plain property
  // would reset to false); none happens while locked (below)
  PersistentProperties {
    id: lockState
    reloadableId: "axiomLockscreen"

    property bool locked: false
  }

  // No hot reload under the lock: Quickshell 0.3's WlSessionLock hands its
  // lock to the next generation, but builds that generation's lock
  // surfaces anew while the old ones still stand, a second surface on each
  // output the compositor answers with a protocol error ("Output is
  // already locked") that ends qs. So while locked, saved files don't
  // reload the shell (they do from the next save after unlocking), and
  // explicit reloads wait for the unlock (LockManager.reload()).
  // RestoreNone: the old generation's Binding, torn down after a reload,
  // must not turn the watcher back on under the new one
  Binding {
    target: Quickshell
    property: "watchFiles"
    value: !lockState.locked
    restoreMode: Binding.RestoreNone
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

  // What LockManager tells axiom. RestoreNone: a generation torn down
  // after a reload leaves them be, so it reports nothing the new one
  // didn't say
  Binding {
    target: LockManager
    property: "builtinLocked"
    value: lockState.locked
    restoreMode: Binding.RestoreNone
  }

  // The compositor has acknowledged the lock: what axiom waits for before
  // `axiom lock` succeeds
  Binding {
    target: LockManager
    property: "builtinSecure"
    value: lockState.locked && sessionLock.secure
    restoreMode: Binding.RestoreNone
  }

  Binding {
    target: LockManager
    property: "builtinSurfaces"
    value: root.surfaces
    restoreMode: Binding.RestoreNone
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

    // The compositor ended the lock without PAM (its `finished`: it refused
    // the lock, as when another locker holds the session): nothing is
    // locked, so the shell stops holding it. Quickshell tells only `secure`
    // of it, while `locked` still reads true, and `locked` never notifies:
    // checked once the signal is through. A PAM unlock clears lockState
    // first
    onSecureChanged: Qt.callLater(() => {
      if (!sessionLock.locked && lockState.locked)
        lockState.locked = false;
    })

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
