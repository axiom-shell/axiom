pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Airplane mode on the OSD: one tile, lit and unusual while on; either
// way its icon (AirplaneWatch reads NetworkingManager). Wi-Fi and
// Bluetooth switching just after are its knock-on (their `knockOnOf`)
OSDSystem {
  // A connection's state settles seconds after the click
  userWindow: 8000

  // I18n.tr("Airplane mode")
  exposes: [
    {
      "key": "airplane",
      "part": "tile",
      "icon": "airplanemode_active",
      "label": "Airplane mode",
      "action": "airplane"
    }
  ]
  // state: { value (on) }: the default tile, lit and unusual while on
}
