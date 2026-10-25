pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

// An IPC target: Quickshell's IpcHandler (so `qs ipc call` reaches it as
// before) that also registers with axiom (BackendManager), so
// `axiom ipc <target> <fn>` and the named commands reach it over the
// shell's own connection, without a process per call. Declared as an
// IpcHandler is, as a service's `_ipc` property (IdleInhibitManager).
IpcHandler {
  id: root

  Component.onCompleted: BackendManager.addTarget(root)
  Component.onDestruction: BackendManager.removeTarget(root)
  onEnabledChanged: BackendManager.targetsChanged()
}
