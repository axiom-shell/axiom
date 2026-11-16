pragma Singleton
import QtQuick

// The row-indent host a FormRow sits in: the nearest visual ancestor with a
// `rowBase` (a FieldGroup, whose block head indents its rows one level; a
// FormRow, a relay with base 0), or null. Called inside a binding, so the
// binding re-runs when any ancestor is reparented (as InkHost).
QtObject {
  id: root

  // The nearest item from `start` up its visual parents that carries a
  // `rowBase`, or null
  function find(start) {
    for (let item = start; item; item = item.parent) {
      if ("rowBase" in item)
        return item;
    }
    return null;
  }
}
