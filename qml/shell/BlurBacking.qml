pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

import qs.config
import qs.services.compositor
import qs.services.ui

// The blur behind the chrome (BlurManager): per screen, one click-through
// window under every chrome surface drawing each registered shape (the
// border's frame, bars, popouts, edge menus, docks) filled. It's the only
// one of them the compositor blurs (LayerStack.blurSurfaces), in one pass, so where
// surfaces join their blur matches exactly. Their shadows are cast here
// too, from the same copies: one per look (BlurShape.shadow), kept only
// outside every shape, so a shadow runs unbroken round joined surfaces as
// round one (surfaces each casting their own, cut where the others sit,
// never met at a join). They stay under Hyprland's blur threshold
// (Appearance.shadowAlphaMax), so they aren't blurred. A compositor whose
// blur has no such threshold (SwayFX's blur_ignore_transparent leaves out
// only clear pixels; no supports.blurThreshold) would blur every pixel of
// them: a window beside each one, not blurred, casts them instead. Where
// it blurs only what a window asks (niri: supports.blurRegion), the
// window asks for its shapes alone, so its shadows stay in it unblurred.
// One window per part and screen, under every chrome surface and over the
// overlay's page (which sits under the backing window in LayerStack), so
// every shape's blur is the page's content under it.
Scope {
  id: root

  Variants {
    // On every compositor, drawing (plain sway too, where it only holds the
    // order): kept mapped meanwhile (BlurBackingWindow.held), so it keeps its
    // place where layers stack by map order
    model: CompositorManager.surfacesReady ? General.outputs : []

    delegate: Scope {
      id: perScreen
      required property ShellScreen modelData
      readonly property string screenName: perScreen.modelData?.name ?? ""
      readonly property var onScreen: BlurManager.shapes.filter(shape => shape.screen === perScreen.screenName)
      readonly property bool shadowsApart: BlurManager.shadowsApart

      // Its backing windows: the fills and the shadows apart (in that order,
      // as SwayFX stacks by map order) or one drawing both. Its layer is its
      // row's, and the layer service's over a fullscreen window (LayerStack:
      // on Top under the chrome and over the overlay's page; on Overlay,
      // under every surface there, for the surfaces shown over it)
      readonly property var parts: perScreen.shadowsApart ? ["fills", "shadows"] : ["all"]

      Variants {
        model: perScreen.parts

        delegate: BlurBackingWindow {
          id: blurWindow
          required property string modelData
          screen: perScreen.modelData
          part: blurWindow.modelData
          shapes: perScreen.onScreen
          layerNamespace: blurWindow.part === "shadows" ? "axiom-shadows" : "axiom-blur-backing"
        }
      }
    }
  }
}
