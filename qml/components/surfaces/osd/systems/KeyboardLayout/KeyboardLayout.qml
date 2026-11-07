pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Keyboard layout on the OSD: the keyboard layout tile. A stub until its
// port (`stub`: the timelines skip it); only what it exposes is declared
OSDSystem {
  readonly property bool stub: true

  // I18n.tr("Keyboard layout")
  exposes: [
    {
      "key": "keyboardLayout",
      "part": "tile",
      "icon": "keyboard",
      "label": "Keyboard layout"
    }
  ]
}
