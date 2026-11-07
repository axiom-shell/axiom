pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Do not disturb on the OSD: one tile, lit and unusual while on; either
// way its icon (DndWatch reads NotificationManager)
OSDSystem {
  // I18n.tr("Do not disturb")
  exposes: [
    {
      "key": "dnd",
      "part": "tile",
      "icon": "do_not_disturb_on",
      "label": "Do not disturb",
      "action": "toggleDnd"
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
