pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Caffeine on the OSD: one tile, lit and unusual while idle is held off;
// either way its icon (CaffeineWatch reads IdleManager)
OSDSystem {
  // I18n.tr("Caffeine")
  exposes: [
    {
      "key": "caffeine",
      "part": "tile",
      "icon": "coffee",
      "label": "Caffeine",
      "action": "idleInhibit"
    }
  ]

  function tile(key, state) {
    const on = state?.value === true;
    return {
      "on": on,
      "notable": on
    };
  }
}
