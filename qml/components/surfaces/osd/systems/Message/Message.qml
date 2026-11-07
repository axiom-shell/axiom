pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Messages on the OSD: the message card (card only). A stub until its port
// (`stub`: the timelines skip it); only what it exposes is declared
OSDSystem {
  readonly property bool stub: true

  // I18n.tr("Messages")
  exposes: [
    {
      "key": "message",
      "part": "card",
      "icon": "chat",
      "label": "Messages"
    }
  ]
}
