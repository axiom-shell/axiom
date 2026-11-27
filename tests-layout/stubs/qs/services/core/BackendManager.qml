pragma Singleton
import QtQuick

// Stand-in for the shell's BackendManager in the layout harness: an IpcTarget registers here (no daemon).
QtObject {
  property var _targets: []

  function addTarget(target) {
    _targets.push(target);
  }

  function removeTarget(target) {
    _targets = _targets.filter(t => t !== target);
  }

  function targetsChanged() {
  }
}
