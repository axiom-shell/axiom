pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// The power profile on the OSD: one tile, the profile's own icon, lit and
// unusual off balanced (PowerProfileWatch reads BatteryManager). The
// profiles daemon answering or going away ("" to a profile and back) is
// no change; its tooltip names it alone (on and off say nothing)
OSDSystem {
  onAdd: "none"
  onRemove: "none"
  // Its look changes only with a profile (the icon, `on`): that's the
  // change's own, not an update (the daemon answering lights nothing)
  onUpdate: "none"

  // I18n.tr("Power profile")
  exposes: [
    {
      "key": "powerProfile",
      "part": "tile",
      "icon": "speed",
      "label": "Power profile",
      "action": "powerSaver"
    }
  ]

  readonly property var _icons: ({
      "powerSaver": "energy_savings_leaf",
      "balanced": "balance",
      "performance": "speed"
    })

  // state: { value ("powerSaver" | "balanced" | "performance", "" with no
  // daemon) }; hidden with none
  function tile(key, state) {
    const p = state?.value ?? "";
    return {
      "icon": _icons[p] ?? _icons.balanced,
      "on": p !== "" && p !== "balanced",
      "notable": p === "powerSaver" || p === "performance",
      "hidden": p === "",
      "nameOnly": true
    };
  }
}
