pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Camera, microphone and screen in use on the OSD: the camera, microphone
// and screen-sharing tiles and their cards. A stub until its port (`stub`:
// the timelines skip it); only what it exposes is declared
OSDSystem {
  readonly property bool stub: true

  // I18n.tr("Camera") I18n.tr("Microphone in use") I18n.tr("Screen sharing")
  exposes: [
    {
      "key": "camera",
      "part": "tile",
      "icon": "videocam",
      "label": "Camera"
    },
    {
      "key": "micUse",
      "part": "tile",
      "icon": "record_voice_over",
      "label": "Microphone in use"
    },
    {
      "key": "screenShare",
      "part": "tile",
      "icon": "screen_share",
      "label": "Screen sharing"
    }
  ]
}
