pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell

import qs.config
import qs.services.ui
import qs.components.methods

// A soft shade of the theme background behind a bare module on the desktop,
// the lock screen or the greeter (no card box of its own): drawn only as
// strong as the wallpaper under `area` (after the layout's dim) needs for
// `ink` to read there, so a module on a calm wallpaper gets none. A
// `RectangularShadow`, never a layer (it holds no text). Its alpha is
// `Tone.alphaFloor` over the wallpaper's backs (`WallpaperToneManager`:
// cached once the daemon has answered, never waited for): until then none
// (as today), or with `worstCase` (the lock, the greeter) the pole under the
// dim; a wallpaper the daemon can't decode is the pole too. `fixedRegion`
// replaces the wallpaper (a layout's colour backdrop: flat grey levels).
// `area` is in the screen's px; the item sits on it, and the shade reaches
// past by half its blur, so the module's own edge is under the full alpha.
Item {
  id: root

  required property ShellScreen screen
  // Whether there is a module to shade (a bare one); off, it asks for no
  // tone and draws nothing
  property bool shown: true
  // The module's rectangle, screen px
  property rect area: Qt.rect(0, 0, 0, 0)
  // The layout's backdrop dim (0-1: a black veil over the background)
  property real dim: 0
  // The compositor blurs the wallpaper under it (a blurred backdrop)
  property bool blurred: false
  // What reads on the shade: the module's text colour (its `backdropInk`)
  property color ink: Style.text
  property real minContrast: 4.5
  // The wallpaper's tone isn't known yet: assume the worst (the pole), for a
  // host that must never show unreadable text (the lock, the greeter)
  property bool worstCase: false
  // A region ({ mean, low, high } grey levels) in place of the wallpaper's,
  // or null for the wallpaper
  property var fixedRegion: null

  x: root.area.x
  y: root.area.y
  width: root.area.width
  height: root.area.height

  readonly property real _blur: Widget.px(24)
  readonly property real _grow: root._blur / 2

  // The grey levels under the shade (null while unknown)
  readonly property var _region: {
    if (!root.shown)
      return null;
    if (root.fixedRegion)
      return root.fixedRegion;
    const w = Math.max(1, root.screen.width);
    const h = Math.max(1, root.screen.height);
    const g = root._grow;
    return WallpaperToneManager.regionOn(root.screen.name, Qt.rect((root.area.x - g) / w, (root.area.y - g) / h, (root.area.width + g * 2) / w, (root.area.height + g * 2) / h), root.blurred, root.worstCase);
  }

  // The shade's alpha: the least at which `ink` reads on every back under
  // it (0 where it already does, 1 where only the opaque shade could)
  readonly property real alpha: root._region ? Tone.alphaFloor(Style.surfacePage, root.ink, Backdrop.backs(root._region, "#000000", root.dim), root.minContrast + StyleTokens.margin) : 0

  opacity: root.alpha
  visible: root.shown && root.opacity > 0
  Glide on opacity {
    duration: Appearance.animSlow
  }

  RectangularShadow {
    anchors.fill: parent
    anchors.margins: -root._grow
    radius: Style.radiusOuter
    blur: root._blur
    color: Style.surfacePage
  }

  // The wallpaper's tone is asked for while a shade could be drawn
  readonly property bool _needsTone: root.shown && root.fixedRegion === null
  property bool _held: false
  on_NeedsToneChanged: root._hold()
  function _hold() {
    if (root._needsTone && !root._held)
      WallpaperToneManager.retain();
    else if (!root._needsTone && root._held)
      WallpaperToneManager.release();
    root._held = root._needsTone;
  }
  Component.onCompleted: root._hold()
  Component.onDestruction: {
    if (root._held)
      WallpaperToneManager.release();
  }
}
