pragma Singleton
import QtQuick
import qs.services.core

// Reader for the WindowLook section: settings that make windows match
// axiom ({ borders, shape, gaps, surfaceBlur, blur, shadow, dim, opacity },
// each an object with its `enabled`), applied by the compositor's backend
// (its config writer's look layer, render.Look). Named
// WindowLookConfig as the section is a whole object.
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.WindowLook

  // Whether the window look sets the compositor's blur (off, the user's
  // own config's applies)
  readonly property bool blurSet: _c.blur.enabled

  // The border colors: the ones picked, else the theme's
  readonly property color activeBorder: _c.borders.activeColor ? Theme.resolveColor(_c.borders.activeColor) : Theme.borderFocus
  readonly property color inactiveBorder: _c.borders.inactiveColor ? Theme.resolveColor(_c.borders.inactiveColor) : Theme.border
  // The windows' shadow: axiom's (Bar style's shadow, its color and size)
  // while it matches it, where off casts none; else its own. Matched, it
  // is a soft (blurred) shadow, as axiom draws it where nothing caps it
  // (Appearance.shadowAlphaMax keeps the chrome's under the blur
  // threshold; no blur reaches a window's)
  readonly property bool shadowMatched: _c.shadow.matchShell
  // The Bars section's look, its shadow flat
  readonly property var _barLook: BarStyle.look
  readonly property bool shadowOn: _c.shadow.enabled && !(shadowMatched && !_barLook.shadow)
  readonly property int shadowSize: shadowMatched ? _barLook.shadowSize : _c.shadow.size
  // Its color: axiom's, the one picked, or none for the compositor's own
  readonly property bool shadowThemed: shadowMatched || _c.shadow.color !== ""
  readonly property color shadowColor: shadowMatched ? BarsConfig.shadowBaseColor(_barLook) : shadowThemed ? Theme.resolveColor(_c.shadow.color) : "black"
  // (a picked color nearly opaque, as the compositors' own are)
  readonly property real shadowAlpha: shadowMatched ? shadowColor.a : 0.93
  // How strong windows cast it (1 = as above), on top of its alpha
  readonly property real shadowStrength: _c.shadow.strength / 100
  // The shape: axiom's (Look & Feel → Shape) while it matches it, else its own
  readonly property int borderWidth: _c.shape.matchShell ? Appearance.borderWidth : _c.shape.size
  readonly property int radius: _c.shape.matchShell ? Appearance.borderRadius : _c.shape.rounding
}
