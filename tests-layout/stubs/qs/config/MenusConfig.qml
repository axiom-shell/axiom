pragma Singleton
import QtQuick

// Stand-in for qs.config MenusConfig in the layout harness: every menu hangs
// on an edge.
QtObject {
  function isFree(menu) {
    return false;
  }
}
