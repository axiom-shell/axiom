pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs.config
import qs.services.core

/*
 * The cursor theme as XCursor readers get it (the compositor's
 * xcursor-theme, XCURSOR_THEME, GTK's cursor-theme). A theme naming its
 * cursors only the X11 way (left_ptr, not default) and inheriting nothing
 * shows the "default" theme's cursors (often Adwaita's) for the standard
 * names it lacks, the arrow among them. So while the Input section's
 * cursor part is on, the daemon (cursor.theme) makes a companion theme
 * (axiom-cursor-<theme> in $XDG_DATA_HOME/icons/) inheriting it, with those names
 * linked to its own cursors, and sets GTK's cursor-theme and cursor-size
 * to what XCursor readers get. CompositorConfigManager hands that name on
 * (compositor.inputs' `xcursor`); Hyprland's setcursor keeps the theme's
 * own. GreeterManager copies the companion into the greeter's bundle, for
 * the greeter's sway (docs/dev/compositor/config-modes.md).
 */
Singleton {
  id: root

  // The name XCursor readers get for the theme set now: the companion
  // theme where it fills names in, else the theme's own; "" while the
  // cursor part is off or until it's known
  readonly property string xcursorTheme: _resolved.theme === _wanted ? _resolved.name : ""
  // Whether xcursorTheme has been known once (CompositorConfigManager
  // waits for it at start, so it writes the name once)
  readonly property bool ready: _wanted === "" || _resolvedOnce || Paths.greeter
  // What a companion theme's name starts with (left out of the themes to
  // pick)
  readonly property string companionPrefix: "axiom-cursor"

  readonly property string _wanted: InputConfig.input.cursor.enabled ? InputConfig.cursorTheme : ""
  readonly property int _size: InputConfig.input.cursor.size
  property var _resolved: ({
      "theme": "",
      "name": ""
    })
  property bool _resolvedOnce: false

  on_WantedChanged: _resolve()
  on_SizeChanged: _resolve()
  Component.onCompleted: _resolve()

  function _resolve() {
    // The greeter writes nothing (services/AGENTS.md)
    const theme = root._wanted;
    if (theme === "" || Paths.greeter)
      return;
    BackendManager.call("cursor.theme", {
      "theme": theme,
      "size": root._size
    }, (error, result) => {
      let name = theme;
      if (error)
        console.warn("[CursorThemeManager] cursor.theme:", error.message);
      else
        name = result.theme || theme;
      if (theme !== root._wanted)
        return;
      root._resolved = {
        "theme": theme,
        "name": name
      };
      root._resolvedOnce = true;
    });
  }
}
