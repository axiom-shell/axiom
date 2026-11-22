pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
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
// While the overlay is open on a screen it covers that window, so a second
// one, over the overlay and under the surfaces on the Overlay layer (bar
// and edge popouts, submenus, the OSD), draws those surfaces' shapes
// (BlurShape.overlayLayer, BlurManager.aboveOverlay), blurring the overlay
// under them. Bars' fills can't move up with them: drawn over the Top
// layer, they'd cover the bars' content.
Scope {
  id: root

  Variants {
    // On every compositor that blurs, drawing while BlurManager.backingOn
    // its screen: kept mapped meanwhile (BlurBackingWindow.held), so it
    // keeps its place where layers stack by map order
    model: CompositorManager.supports.blur === true && CompositorManager.surfacesReady ? General.outputs : []

    delegate: Scope {
      id: perScreen
      required property ShellScreen modelData
      readonly property string screenName: perScreen.modelData?.name ?? ""
      readonly property var onScreen: BlurManager.shapes.filter(shape => shape.screen === perScreen.screenName)
      // The overlay open here covers the backing window: the Overlay-layer
      // surfaces' shapes go to the one over it
      readonly property bool aboveOverlay: BlurManager.aboveOverlay(perScreen.screenName)
      // The hand-off, so some window draws those surfaces' boxes in every
      // frame: the window over the overlay has drawn them (its first frame
      // after it was made while the overlay was open), and the main one
      // hasn't yet drawn them back (its first frame after the overlay
      // closed, which has them). The main window gives them up, and erases
      // them, only while both this and the overlay are; on close it draws
      // them at once, while the other still does, and the window over the
      // overlay goes once this falls
      property bool overlayTaken: false
      // nothing to hand back where the main window doesn't draw: the surfaces
      // draw their own boxes
      onAboveOverlayChanged: if (!perScreen.aboveOverlay && !BlurManager.backingOn(perScreen.screenName))
        perScreen.overlayTaken = false
      readonly property bool overlayWindows: perScreen.aboveOverlay || perScreen.overlayTaken
      readonly property bool overlayGivenUp: perScreen.aboveOverlay && perScreen.overlayTaken
      readonly property var overlayShapes: perScreen.overlayWindows ? perScreen.onScreen.filter(shape => shape.overlayLayer) : []
      readonly property var otherShapes: perScreen.overlayGivenUp ? perScreen.onScreen.filter(shape => !shape.overlayLayer) : perScreen.onScreen
      readonly property bool shadowsApart: BlurManager.shadowsApart

      // Its backing windows: the fills and the shadows apart (in that order,
      // as SwayFX stacks by map order) or one drawing both. Below the
      // overlay: on Top, under the chrome; on Overlay (under every surface
      // there, by its order) while a fullscreen window hides the Top
      // layer, for the surfaces shown over it (BlurManager.overFullscreen).
      // Over the overlay ("-overlay") and under the surfaces on the Overlay
      // layer (by its order), while the overlay is open here: their blur is
      // the overlay's content, not what the overlay covers
      readonly property var parts: perScreen.shadowsApart ? ["fills", "shadows"] : ["all"]

      Variants {
        model: perScreen.parts.concat(perScreen.overlayWindows ? perScreen.parts.map(part => part + "-overlay") : [])

        delegate: BlurBackingWindow {
          id: blurWindow
          required property string modelData
          readonly property bool over: blurWindow.modelData.endsWith("-overlay")
          screen: perScreen.modelData
          part: blurWindow.modelData.replace("-overlay", "")
          shapes: blurWindow.over ? perScreen.overlayShapes : BlurManager.backingOn(perScreen.screenName) ? perScreen.otherShapes : []
          cutBy: blurWindow.over ? perScreen.otherShapes : perScreen.overlayShapes
          // Only the window under the overlay gives way (to what the one over
          // it draws): it holds the overlay's shapes as erasers while the
          // windows over the overlay exist, and erases each only once it
          // leaves `shapes` (`otherShapes`, while `overlayGivenUp`), so a
          // hand-off changes one list, never both; the one over it gives way
          // to nothing
          erasers: blurWindow.over ? [] : perScreen.overlayShapes
          wanted: blurWindow.over || BlurManager.backingOn(perScreen.screenName)
          held: !blurWindow.over
          stackLayer: blurWindow.over || BlurManager.overFullscreen(perScreen.screenName) ? WlrLayer.Overlay : WlrLayer.Top
          layerNamespace: (blurWindow.part === "shadows" ? "axiom-shadows" : "axiom-blur-backing") + (blurWindow.over ? "-overlay" : "")

          // The hand-off's two edges, read from the windows that draw the shapes
          Connections {
            target: blurWindow.contentItem?.Window.window ?? null
            function onFrameSwapped() {
              if (blurWindow.part === "shadows")
                return;
              if (blurWindow.over && perScreen.aboveOverlay)
                perScreen.overlayTaken = true;
              else if (!blurWindow.over && !perScreen.aboveOverlay)
                perScreen.overlayTaken = false;
            }
          }
        }
      }
    }
  }
}
