pragma ComponentBehavior: Bound
import QtQuick
import qs.services.system
import qs.components.surfaces.osd.engine

// Brightness's state for the OSD: the level of this screen's monitor
// (every one's mean with `allMonitors`), whether it has a controller, and
// the bar's icon (`icon`, else the level's), and when axiom last set one
// of them (`setAt`: BrightnessManager.brightnessChanged, which a refresh
// or idle dimming's silent set never sends, and which a set at the limit
// still sends): the definition counts a level only just after it. As
// its OSD opens it picks up brightness changed outside axiom on the
// monitors its bar shows (none with its bar off)
OSDWatch {
  id: watch

  // The monitors its bar shows: every one with a controller, or this
  // screen's
  readonly property var targets: watch.options.allMonitors === true ? BrightnessManager.names : watch.screen ? [watch.screen.name] : []
  readonly property bool _available: watch.options.allMonitors === true ? BrightnessManager.names.length > 0 : (watch.screen ? BrightnessManager.available(watch.screen.name) : false)
  // When axiom last set one of them (Date.now())
  property double _setAt: 0

  state: {
    const all = watch.options.allMonitors === true;
    const level = all ? BrightnessManager.average(watch.targets) : watch.screen ? BrightnessManager.valueFor(watch.screen.name) : 0;
    return {
      "brightness": {
        "available": watch._available,
        "level": level,
        "setAt": watch._setAt,
        "icon": watch.options.icon || BrightnessManager.icon(level)
      }
    };
  }

  function setLevel(key, level) {
    BrightnessManager.setMany(watch.targets, level);
  }

  function opened() {
    if (watch.options.tile === false)
      return;
    watch.targets.forEach(name => BrightnessManager.refresh(name));
  }

  Connections {
    target: BrightnessManager
    function onBrightnessChanged(name) {
      if (watch.targets.includes(name))
        watch._setAt = Date.now();
    }
  }
}
