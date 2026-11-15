pragma Singleton
import QtQuick

// The Surface whose ink a text inherits: the nearest visual ancestor with an
// `inkScope`. Called inside a binding, so the binding re-runs when any
// ancestor is reparented (docs/dev/core/style.md > Pieces).
QtObject {
  id: root

  // The nearest item from `start` up its visual parents that carries an
  // `inkScope` (a Surface), or null
  function find(start) {
    for (let item = start; item; item = item.parent) {
      if ("inkScope" in item)
        return item;
      // a relay already knows the host above it
      if ("inkHostAbove" in item)
        return item.inkHostAbove;
    }
    return null;
  }
}
