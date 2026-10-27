pragma ComponentBehavior: Bound
import QtQuick

// An IPC target: registers with axiom (BackendManager), so
// `axiom ipc <target> <fn>` and the named commands reach it over the
// shell's own connection, without a process per call. Its own functions
// are what it offers (not `_`-prefixed ones); arguments arrive as the
// command line's text, which typed parameters convert. Declared as a
// service's `_ipc` property (IdleManager), or inside a surface.
QtObject {
  id: root

  // The name `axiom ipc` calls it by
  property string target
  // Only the enabled instance of a name answers (one per screen)
  property bool enabled: true

  Component.onCompleted: BackendManager.addTarget(root)
  Component.onDestruction: BackendManager.removeTarget(root)
  onEnabledChanged: BackendManager.targetsChanged()
}
