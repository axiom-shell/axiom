pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// VPN on the OSD: the VPN tile and its cards. A stub until its port (`stub`:
// the timelines skip it); only what it exposes is declared
OSDSystem {
  readonly property bool stub: true

  // I18n.tr("VPN")
  exposes: [
    {
      "key": "vpn",
      "part": "tile",
      "icon": "vpn_key",
      "label": "VPN"
    }
  ]
}
