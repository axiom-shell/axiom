pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Now playing on the OSD: the now playing card (card only). A stub until its
// port (`stub`: the timelines skip it); only what it exposes is declared
OSDSystem {
  readonly property bool stub: true

  // I18n.tr("Now playing")
  exposes: [
    {
      "key": "media",
      "part": "card",
      "icon": "music_note",
      "label": "Now playing"
    }
  ]
}
