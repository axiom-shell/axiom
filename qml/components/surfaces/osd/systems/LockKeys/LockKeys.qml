pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Lock keys on the OSD: a tile per key `keys` lists (Caps, Num and Scroll
// Lock), lit and unusual while on; either way its icon. Hidden without
// LEDs, and nothing is judged across their appearing or going (each
// key's `available`: LockKeysWatch reads LockKeysManager)
OSDSystem {
  // I18n.tr("Caps Lock") I18n.tr("Num Lock") I18n.tr("Scroll Lock")
  readonly property var _keys: ({
      "capsLock": {
        "icon": "keyboard_capslock",
        "label": "Caps Lock"
      },
      "numLock": {
        "icon": "dialpad",
        "label": "Num Lock"
      },
      "scrollLock": {
        "icon": "swap_vert",
        "label": "Scroll Lock"
      }
    })
  exposes: (options.shows ?? ["capsLock", "numLock"]).filter(key => _keys[key]).map(key => Object.assign({
      "key": key,
      "part": "tile"
    }, _keys[key]))

  // state: { available (LEDs read), value (the LED on) }: the default
  // tile, hidden while no LEDs are read
}
