pragma Singleton
import QtQuick
import qs.services.core

// Reader for Compositor.niri: niri's own options in the managed config
// (the daemon's niri writer; each field by its x-compositor.niri annotation),
// read whole.
QtObject {
  readonly property var _c: ConfigManager.config.Compositor.niri

  readonly property string _optionsJson: JSON.stringify(_c)
  readonly property var options: JSON.parse(_optionsJson)
}
