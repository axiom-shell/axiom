pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Keybinds section: axiom's own binds, edited on the
// Keybinds page (KeybindManager) and applied by the compositor's config
// writer (the daemon's)
QtObject {
  id: root

  readonly property var _c: ConfigManager.config.Keybinds

  // [{ key, action, argument, call, compositor, description, … }]. Goes
  // through a string so a reload that leaves the list unchanged doesn't
  // re-apply the binds.
  readonly property string _bindsJson: JSON.stringify(_c.binds)
  readonly property var binds: JSON.parse(_bindsJson)
  // The binds to bind: all but the paused ones, which stay in the list
  readonly property var activeBinds: binds.filter(bind => !bind.paused)
  // Bind sets saved on the Keybinds page: [{ id, name, binds }]
  readonly property var presets: _c.presets
}
