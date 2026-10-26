pragma Singleton
import QtQuick

import qs.config
import qs.services.compositor

/**
 * The blur behind the shell's chrome: the border's frame, bars and their
 * popouts, edge popouts, integrated edge menus and docks. Each surface
 * registers its shape (BlurShape); one click-through window per screen
 * (shell/BlurBacking) draws them all, filled, and is the only one of them
 * Hyprland blurs. Blurred in one pass, before any chrome is drawn, the
 * blur behind joined surfaces matches exactly; the surfaces themselves
 * draw their outer fill transparent (`backing`). While the overlay is open
 * on a screen, a second blur window there, over it, draws the shapes of
 * the surfaces on the Overlay layer (aboveOverlay).
 * Layer-shell windows don't know where they are on screen: each shape is
 * placed from its window's origin as LayerManager works it out
 * (hosts/popout/LayerOrigin).
 */
QtObject {
  id: root

  // Whether anything blurs now: Appearance.blur where the compositor blurs
  // axiom's surfaces (elsewhere they fill themselves: the blur window
  // couldn't place their shapes without its layer positions), paused while
  // a fullscreen window is open on any screen (Appearance.
  // blurPauseFullscreen; the layer rules are Hyprland-wide). The chrome
  // then fills itself, solid on the screens showing one (opaqueOn).
  readonly property bool _wanted: Appearance.blur && CompositorManager.supports.blur === true
  readonly property bool paused: root._wanted && Appearance.blurPauseFullscreen && General.outputs.some(screen => CompositorManager.hasFullscreen(screen.name))
  readonly property bool active: root._wanted && !root.paused
  // The surfaces leave their fill to the blur window: blurring, and its
  // windows built (BlurBacking waits for the layer rules, as the chrome does)
  readonly property bool backing: root.active && CompositorManager.surfacesReady
  // Whether a surface that blurs itself (LayerStack.blurSurfaces, the
  // chrome's popups) asks the compositor to blur behind its box now, where
  // it blurs only what a window asks (supports.blurRegion: no layer rule
  // decides there), and a backdrop behind all of it (blurBackdrops)
  readonly property bool regions: root.active && CompositorManager.supports.blurRegion === true
  readonly property bool backdropRegions: root.regions && Appearance.blurBackdrops

  function _name(screen) {
    return typeof screen === "string" ? screen : screen?.name ?? "";
  }

  // Whether a chrome surface on `screen` (a ShellScreen or its name) leaves
  // its fill to the blur window. `onOverlay`: its window is on the Overlay
  // layer, over fullscreen windows (where the blur window rises too:
  // overFullscreen) and over the overlay (where the blur window over the
  // overlay draws it: aboveOverlay). Otherwise it's on Top, faded out under
  // a fullscreen window, and its copy goes with it.
  function backsOn(screen, onOverlay) {
    if (!root.backing)
      return false;
    return onOverlay || !CompositorManager.hasFullscreen(root._name(screen));
  }

  // Whether the overlay is open on `screen`, covering the blur window: the
  // Overlay-layer surfaces' shapes (BlurShape.overlayLayer) are then drawn
  // by a second blur window, over the overlay and under them
  function aboveOverlay(screen) {
    return root.backing && ShellManager.surfaceOpenOn("overlay", root._name(screen));
  }

  // Whether the blur window on `screen` stands on the Overlay layer: a
  // fullscreen window shown there hides the Top layer, and the surfaces
  // over it still blur
  function overFullscreen(screen) {
    return root.backing && CompositorManager.hasFullscreen(root._name(screen));
  }

  // Whether surfaces on `screen` fill themselves solid: blur paused for a
  // fullscreen window shown there (elsewhere they stay translucent)
  function opaqueOn(screen) {
    return root.paused && CompositorManager.hasFullscreen(root._name(screen));
  }

  // A surface's own fill on `screen`: at the surface opacity, solid where
  // opaqueOn
  function fillOn(color, screen) {
    return root.opaqueOn(screen) ? color : Appearance.fill(color);
  }

  // The registered BlurShapes; changes only as one comes or goes. Each
  // gets a `uid`, which the blur window keys its copies by (shapeOf).
  property var shapes: []
  property int _lastUid: 0
  property var _byUid: ({})

  function register(shape) {
    if (root.shapes.includes(shape))
      return;
    shape.uid = ++root._lastUid;
    root._byUid[shape.uid] = shape;
    root.shapes = root.shapes.concat([shape]);
  }

  function unregister(shape) {
    if (!root.shapes.includes(shape))
      return;
    delete root._byUid[shape.uid];
    root.shapes = root.shapes.filter(s => s !== shape);
  }

  // The registered shape with that uid, or null once it's gone
  function shapeOf(uid) {
    return root._byUid[uid] ?? null;
  }
}
