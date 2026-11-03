pragma ComponentBehavior: Bound
import QtQuick

// An IPC target: registers with axiom (BackendManager), so
// `axiom ipc <target> <fn>` and the named commands reach it over the
// shell's own connection, without a process per call. Its own functions
// are what it offers (not `_`-prefixed ones); arguments arrive as the
// command line's text, so parameters are strings (check_structure): a
// number is read through _int, which refuses a word. Declared as a
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

  // An argument as a whole number; anything else is the caller's mistake,
  // answered as a bad request (a typed `int` would make a word 0)
  function _int(text: string): int {
    if (!/^\s*[-+]?\d+\s*$/.test(text))
      throw {
        "kind": "bad_request",
        "message": "not a whole number: " + text
      };
    return parseInt(text);
  }
}
