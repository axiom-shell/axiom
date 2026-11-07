pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Screen recording on the OSD: the screen recording tile. A stub until its
// port (`stub`: the timelines skip it); only what it exposes is declared
OSDSystem {
  readonly property bool stub: true

  // I18n.tr("Screen recording")
  exposes: [
    {
      "key": "recording",
      "part": "tile",
      "icon": "screen_record",
      "label": "Screen recording"
    }
  ]
}
