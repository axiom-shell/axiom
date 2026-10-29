pragma Singleton
import QtQuick
import Quickshell

import qs.config
import qs.services.core
import qs.services.ui

// The one way to lock the session, whatever locks it (Lockscreen.mode):
//   "quickshell"  the built-in locker (shell/Lockscreen.qml: Wayland
//                 session lock + PAM through AuthManager)
//   "none"        the user's own locker: runs Lockscreen.lockCommand
// Lock buttons call lock(); idle daemons call the `lockscreen` IPC target
// (`axiom ipc lockscreen lock`), which exists only when axiom
// provides the locker, so "none" can't loop through loginctl lock-session.
//
// Also holds the layouts editor's draft of the built-in lock screen
// (Lockscreen.layout, `editor`: its modules on a bounded grid) and its
// preview on screen. The lock itself only ever shows the
// saved layout (LockscreenConfig.layout).
QtObject {
  id: root

  readonly property string mode: LockscreenConfig.mode

  // The built-in lock is up (set by shell/Lockscreen.qml, which owns it)
  property bool builtinLocked: false
  // …and the compositor has acknowledged it (the session is locked)
  property bool builtinSecure: false
  // …and how many lock surfaces it built (set by shell/Lockscreen.qml)
  property int builtinSurfaces: 0

  // Run by axiom: it hears of every change, to confirm `axiom lock` and to
  // relock a shell that dies while locked. Never the other way: nothing
  // axiom says unlocks
  onBuiltinSecureChanged: _report()
  onBuiltinLockedChanged: {
    _report();
    if (!root.builtinLocked && root._reloadWhenUnlocked)
      Quickshell.reload(false);
  }
  onBuiltinSurfacesChanged: _report()

  // The surfaces actually built against the monitors connected (not Qt's
  // stand-ins), so a monitor without a lock surface keeps `axiom lock`
  // from confirming, and with none connected the session lock alone does
  function _report() {
    if (!BackendManager.active)
      return;
    BackendManager.call("lock.state", {
      "locked": root.builtinLocked && root.builtinSecure,
      "holding": root.builtinLocked,
      "surfaces": root.builtinSecure ? root.builtinSurfaces : 0,
      "outputs": General.outputs.length
    }, null);
  }

  property Connections _outputs: Connections {
    target: General
    function onOutputsChanged() {
      root._report();
    }
  }

  property Connections _backend: Connections {
    target: BackendManager
    // A reconnect (axiom re-exec'd): tell it again
    function onGreeted() {
      root._report();
    }
  }

  // For the built-in locker
  signal lockRequested
  // Any lock started: menus and popups can close
  signal lockStarted

  function lock() {
    root.editor.stopPreview(false);
    GreeterManager.editor.stopPreview(false);
    switch (root.mode) {
    case "quickshell":
      root.lockRequested();
      break;
    default:
      CommandManager.runDetached(LockscreenConfig.lockCommand);
    }
    root.lockStarted();
  }

  // The one way to reload the shell's QML (Quickshell.reload). Never under
  // the built-in lock, which a reload ends (shell/Lockscreen.qml, its
  // watchFiles): then it waits for the unlock
  function reload() {
    if (root.builtinLocked)
      root._reloadWhenUnlocked = true;
    else
      Quickshell.reload(false);
  }
  property bool _reloadWhenUnlocked: false

  // --- The layouts editor's draft (Lockscreen.layout) and its preview ---

  property ScreenLayoutEditor editor: ScreenLayoutEditor {
    path: ["Lockscreen", "layout"]
    host: "lockscreen"
    name: I18n.tr("Lock screen")
  }

  property IpcTarget _ipc: IpcTarget {
    target: "lockscreen"
    enabled: root.mode !== "none"

    function lock(): void {
      root.lock();
    }
  }
}
