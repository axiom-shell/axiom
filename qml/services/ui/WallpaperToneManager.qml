pragma Singleton
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core

/* What the shown wallpaper is under a surface: theme.backdrop's luminance
 * grid per shown wallpaper (a call when a screen's wallpaper changes, only
 * while something needs it: a bar with no surface, translucent surfaces, a
 * bare module on the desktop, lock screen or greeter), mapped onto a
 * surface's rectangle through the wallpaper's placement (`regionOn`, what the
 * bars and BackdropScrim read) and the edge family's floored alpha
 * (`edgeFloor`: Appearance.wallpaperEdgeFloor), the least opacity the bars'
 * fill needs so their content reads on the wallpapers, the same on every
 * screen. Nothing is polled; the daemon decodes each wallpaper once. On a wallpaper change the previous
 * wallpaper's grid stands in until the new one's arrives. */
QtObject {
  id: root

  // Bumped whenever a grid arrives or fails: what `regionOn` and `edgeFloor`
  // depend on
  property int revision: 0

  // Something reads the wallpaper's tone: a bar with no surface,
  // translucent surfaces, or a bare module (retain)
  readonly property bool needed: root._barsNeed || Appearance.translucent || root._moduleUsers > 0
  // The bars' config (the greeter has no Bars section, nor bars)
  readonly property var _bars: Paths.greeter ? [] : ConfigManager.live.Bars.items
  readonly property bool _barsNeed: root._bars.some(bar => bar.surface === "none")

  // The grey level the wallpaper is taken to be where it can't be known
  // (a format the daemon can't decode, no daemon): the pole under the theme,
  // white behind a dark one, black behind a light one (the worst case)
  readonly property int pole: Appearance.darkMode ? 255 : 0

  // The least alpha the edge family's fill needs over every screen's
  // wallpaper for the bars' content to read (0 until the tone is known);
  // changes glide, so a new wallpaper never steps every edge surface at once
  property real edgeFloor: root._edgeTarget
  Behavior on edgeFloor {
    enabled: Appearance.animations

    NumberAnimation {
      duration: Appearance.animSlow
      easing.type: Appearance.easing
    }
  }

  // Appearance's readers read no service: the floor is handed over
  property Binding _appearanceFloor: Binding {
    target: Appearance
    property: "wallpaperEdgeFloor"
    value: root.edgeFloor
  }
  // And its settled value (not glided)
  property Binding _appearanceTarget: Binding {
    target: Appearance
    property: "wallpaperEdgeTarget"
    value: root._edgeTarget
  }

  // A bare module on a desktop, lock or greeter layout (BackdropScrim) needs
  // the tone while it exists
  function retain() {
    root._moduleUsers++;
  }
  function release() {
    root._moduleUsers--;
  }
  property int _moduleUsers: 0

  // The grey levels { mean, low, high } the wallpaper is under `rect` (screen
  // units, 0-1 both ways) on the screen `screenName`: null while unknown (no
  // grid has been ready on that screen yet), or, with `worstCase`, the pole. A wallpaper
  // that can't be decoded is the pole; no wallpaper is the theme's
  // background. `blurred`: the compositor blurs what's behind the surface.
  function regionOn(screenName, rect, blurred, worstCase) {
    void root.revision;
    const screen = General.outputs.find(s => s.name === screenName);
    if (!screen)
      return worstCase ? Backdrop.flat(root.pole) : null;
    const path = root._pathOf(ThemeManager.wallpaperFor(screenName));
    if (path === "")
      return Backdrop.flat(Style.surfacePage);
    let entry = root._grids[path];
    if (!entry || entry.state === "pending")
      entry = root._grids[root._lastReady[screenName]];
    if (!entry || entry.state !== "ready" && entry.state !== "failed")
      return worstCase ? Backdrop.flat(root.pole) : null;
    if (entry.state === "failed")
      return Backdrop.flat(root.pole);
    const share = Appearance.wallpaperParallax ? Appearance.wallpaperParallaxStrength / 100 : 0;
    const px = WallpaperFill.travelPx(share, screen.width, screen.height);
    const image = WallpaperFill.rect(Appearance.wallpaperFill, entry.grid.width, entry.grid.height, screen.width, screen.height, share, 0, 0);
    return Backdrop.region(entry.grid, image, rect, {
      "x": screen.width > 0 ? px / 2 / screen.width : 0,
      "y": screen.height > 0 ? px / 2 / screen.height : 0
    }, blurred, Backdrop.greyOf(Style.surfacePage));
  }

  // ---- the edge floor ----

  // Over every bar that draws a fill (the ones with no surface get a shade
  // instead): its band's bare backs and the ink its text colour is, from
  // config geometry, never the drawn bars (ScreenEdgeManager.bars reads this
  // floor back: a binding loop)
  readonly property real _edgeTarget: root._edgeFloorOf(root._barPalettes, root.revision)
  // Each bar's palette as it draws it (an enrich per bar), kept apart from
  // `revision` so a grid arriving re-runs only the floor, never the enrich:
  // it follows the bars' config and the theme and appearance the enrich reads
  readonly property var _barPalettes: BarsConfig.expandBars(root._bars).filter(bar => bar.enabled && bar.surface !== "none").map(bar => ({
        "bar": bar,
        "palette": BarsConfig.enrichBarConfig(bar, {}, {}).palette
      }))
  function _edgeFloorOf(entries, revision) {
    if (!Appearance.translucent)
      return 0;
    const bg = Style.surfacePage;
    const min = Tone.textContrast + StyleTokens.margin;
    let floor = 0;
    for (const {
      bar,
      palette
    } of entries) {
      const screen = General.outputs.find(s => s.name === bar.monitor);
      if (!bar.enabled || bar.surface === "none" || !screen)
        continue;
      const region = root.regionOn(bar.monitor, Backdrop.band(bar.edge, bar.thickness, Appearance.screenMargin, screen), Appearance.blur, false);
      if (!region)
        continue;
      // The text colour as the bar draws it (palette: Auto's or the user's
      // pick, as BarEnrich takes it)
      const ref = palette.override ?? Tone.nudged([bg], palette.barText, min);
      floor = Math.max(floor, Tone.alphaFloor(bg, ref, Backdrop.backs(region, bg, 0), min));
    }
    return floor;
  }

  // ---- the grids ----

  // path -> { state: "pending" | "ready" | "failed", grid }, mutated in place
  property var _grids: ({})
  // screen name -> the path of the last grid that was ready on it, held while
  // a new wallpaper's is pending, so nothing drops to "unknown" on a
  // wallpaper change; mutated in place, read through `revision`
  property var _lastReady: ({})
  readonly property string _pathsKey: JSON.stringify(General.outputs.map(s => root._pathOf(ThemeManager.wallpaperFor(s.name))))
  on_PathsKeyChanged: Qt.callLater(root._sync)
  onNeededChanged: Qt.callLater(root._sync)
  Component.onCompleted: Qt.callLater(root._sync)

  // A wallpaper's URL as the file path the daemon reads
  function _pathOf(url) {
    return url ? decodeURIComponent(url.toString().replace("file://", "")) : "";
  }

  // Ask for the wallpapers shown while the tone is needed, drop the rest
  function _sync() {
    const wanted = root.needed ? JSON.parse(root._pathsKey).filter(path => path !== "") : [];
    let changed = false;
    if (!root.needed) {
      root._lastReady = ({});
      changed = true;
    } else {
      const names = General.outputs.map(s => s.name);
      for (const name of Object.keys(root._lastReady)) {
        if (!names.includes(name)) {
          delete root._lastReady[name];
          changed = true;
        }
      }
      for (const name of names) {
        const path = root._pathOf(ThemeManager.wallpaperFor(name));
        if (path !== "" && root._grids[path]?.state === "ready" && root._lastReady[name] !== path) {
          root._lastReady[name] = path;
          changed = true;
        }
      }
    }
    const kept = Object.values(root._lastReady);
    for (const path of Object.keys(root._grids)) {
      if (!wanted.includes(path) && !kept.includes(path)) {
        delete root._grids[path];
        changed = true;
      }
    }
    for (const path of wanted) {
      if (!(path in root._grids))
        root._fetch(path);
    }
    if (changed)
      root.revision++;
  }

  // rpc: theme.backdrop
  function _fetch(path) {
    const pending = {
      "state": "pending",
      "grid": null
    };
    root._grids[path] = pending;
    BackendManager.call("theme.backdrop", {
      "wallpaper": path
    }, (error, result) => {
      // Gone, or asked again, meanwhile
      if (root._grids[path] !== pending)
        return;
      const grid = error ? null : Backdrop.decode(result);
      if (error)
        console.log("[WallpaperToneManager] No backdrop for", path, "-", error.message);
      root._grids[path] = grid ? {
        "state": "ready",
        "grid": grid
      } : {
        "state": "failed",
        "grid": null
      };
      if (grid) {
        for (const s of General.outputs) {
          if (root._pathOf(ThemeManager.wallpaperFor(s.name)) === path)
            root._lastReady[s.name] = path;
        }
        Qt.callLater(root._sync);
      }
      root.revision++;
    }, {
      "repeatable": true
    });
  }
}
