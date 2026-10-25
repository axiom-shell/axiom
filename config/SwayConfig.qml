pragma Singleton
import QtQuick
import qs.services.core

// Reader for Compositor.sway: sway's own options in the managed config
// (the daemon's sway writer; each field by its x-compositor.sway annotation),
// read whole.
QtObject {
  readonly property var _c: ConfigManager.config.Compositor.sway

  readonly property string _optionsJson: JSON.stringify(_c)
  readonly property var options: JSON.parse(_optionsJson)
}
