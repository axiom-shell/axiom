pragma ComponentBehavior: Bound
import QtQuick

import qs.components.methods

/* The list `fresh` builds, kept the same array and the same objects while
 * its content is equal (Utils.keepEqual by `idOf`), so a rebuild with equal
 * content reaches no reader of `items`. With `oncePerTurn` it is kept once
 * per event turn (Qt.callLater), so the transient states within one turn
 * notify once; [] until it has completed. Not a singleton: each list a
 * service keeps owns one (CompositorManager's four, ScreenEdgeManager.bars). */
QtObject {
  id: root

  // The newly built list (a binding at the site)
  property var fresh: []
  // Which entry is which across rebuilds: function(entry) -> id
  property var idOf: entry => entry.id
  property bool oncePerTurn: false
  // The kept list; notifies only when it is a different array
  readonly property var items: root._items
  property var _items: []
  property var _keys: []
  onFreshChanged: root.oncePerTurn ? Qt.callLater(root.keep) : root.keep()
  Component.onCompleted: root.keep()
  // Keeps `fresh` now
  function keep() {
    const k = Utils.keepEqual({
      "items": root._items,
      "keys": root._keys
    }, root.fresh, root.idOf);
    root._keys = k.keys;
    if (k.items !== root._items)
      root._items = k.items;
  }
}
