pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Audio on the OSD: the volume bars (master, other apps, an app's; the
// microphone's bar, whose key the port settles beside the microphone
// tile's), the output and input device tiles and the device-switch card. A
// stub until its port (`stub`: the timelines skip it); only what it exposes
// is declared
OSDSystem {
  readonly property bool stub: true

  // I18n.tr("An app") I18n.tr("Input") I18n.tr("Other apps") I18n.tr("Output") I18n.tr("System volume")
  exposes: [
    {
      "key": "audio",
      "part": "tile",
      "icon": "volume_up",
      "label": "Output"
    },
    {
      "key": "microphone",
      "part": "tile",
      "icon": "mic",
      "label": "Input"
    },
    {
      "key": "master",
      "part": "bar",
      "icon": "volume_up",
      "label": "System volume"
    },
    {
      "key": "other",
      "part": "bar",
      "icon": "music_note",
      "label": "Other apps"
    },
    {
      "key": "app",
      "part": "bar",
      "icon": "apps",
      "label": "An app"
    }
  ]
}
