pragma Singleton
import QtQuick
import qs.services.core

// Reader for the HotCorners section: the screen corners that run an axiom
// action (shell/HotCorners). Named HotCornersConfig because HotCorners is
// the surface.
QtObject {
  readonly property var _c: ConfigManager.live.HotCorners

  // [{ id, corner, action, argument, screen, delay }] (see the schema).
  // Goes through a string so a reload that leaves the list unchanged
  // doesn't rebuild the corners.
  readonly property string _itemsJson: JSON.stringify(_c.items)
  readonly property var items: JSON.parse(_itemsJson)
  readonly property var ids: items.map(item => item.id)

  function itemById(id) {
    return items.find(item => item.id === id) ?? null;
  }
}
