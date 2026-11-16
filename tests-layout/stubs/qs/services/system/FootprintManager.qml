pragma Singleton
import QtQuick

// Stand-in for the shell's FootprintManager in the layout harness: no
// recorded, inferred or system changes for any setting.
QtObject {
  function undoableFor(owner) {
    return [];
  }

  function inferredFor(owner) {
    return [];
  }

  function systemFor(owner) {
    return [];
  }
}
