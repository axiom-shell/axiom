pragma ComponentBehavior: Bound
import QtQuick
import qs.services.system
import qs.components.surfaces.osd.engine

// Brightness's state for the OSD: a stub until its port, with no state, so
// nothing it watches ever changes. As its OSD opens it picks up brightness
// changed outside axiom on the monitors its bar shows (every one with
// `allMonitors`, else the OSD's; none with its bar off)
OSDWatch {
  id: watch

  state: ({})

  function opened() {
    if (watch.options.tile === false)
      return;
    const names = watch.options.allMonitors ? BrightnessManager.names : watch.screen ? [watch.screen.name] : [];
    names.forEach(name => BrightnessManager.refresh(name));
  }
}
