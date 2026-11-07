pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Lock keys on the OSD: Caps, Num and Scroll Lock tiles. A stub until its
// port (`stub`: the timelines skip it); only what it exposes is declared
OSDSystem {
  readonly property bool stub: true

  // I18n.tr("Caps Lock") I18n.tr("Num Lock") I18n.tr("Scroll Lock")
  exposes: [
    {
      "key": "capsLock",
      "part": "tile",
      "icon": "keyboard_capslock",
      "label": "Caps Lock"
    },
    {
      "key": "numLock",
      "part": "tile",
      "icon": "dialpad",
      "label": "Num Lock"
    },
    {
      "key": "scrollLock",
      "part": "tile",
      "icon": "swap_vert",
      "label": "Scroll Lock"
    }
  ]
}
