pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.ui
import qs.components.methods

// A surface's shape, registered with BlurManager for the blur window
// (shell/BlurBacking) to draw and blur in its place. `source` is an
// AttachedSurface (`kind: "attached"`) or a Rectangle (`"rect"`), mirrored
// there with its geometry bound live; `x`/`y` are where its top-left sits
// on `screen` (a screen name).
QtObject {
  id: root

  required property Item source
  // The fill its copy draws, and the blur threshold reads: an attached
  // surface's own fillColor unless its site sets one; a rect's or frame's
  // what its site sets
  property color color: root._surface?.fillColor ?? Style.surfacePage
  // The stroke its copy draws over its fill: an attached surface's own
  // strokeColor unless its site sets one (as `shadow` follows its source);
  // a rect has none unless its site sets one; transparent for none
  property color strokeColor: root._surface?.strokeColor ?? "transparent"
  // Where it stands in the backing window's painter's order (PaintOrder.of:
  // lower first; a higher shape's fill hides the stroke of one under it)
  property int paintLevel: PaintOrder.of("base")
  // How far its copy has faded in (a toast or menu tile fading), applied to the copy alone
  property real fade: 1
  property string kind: "attached"
  property string screen: ""
  property real x: 0
  property real y: 0
  // Its window is on the Overlay layer: while the overlay is open on its
  // screen, it's drawn by the blur window over the overlay
  // (BlurManager.aboveOverlay)
  property bool overlayLayer: false
  // Placed (its window found on screen) and showing
  property bool shown: true
  // Its key in BlurManager, set as it registers
  property int uid: -1
  // What of it shows, on screen: its window's rect, for a shape that moves
  // past its window's edges (a hiding dock, an edge popout longer than its
  // window); null for the whole screen
  property var clipRect: null

  // The shadow it casts there (a SurfaceShadow look: BarStyle's or a
  // bar's), null for none. The blur window casts one per look from all
  // the shapes together, so where they join it runs unbroken. An
  // AttachedSurface's follows its castShadow.
  readonly property AttachedSurface _surface: root.kind === "attached" ? root.source as AttachedSurface : null
  property var shadow: root._surface?.castShadow ? root._surface.shadowLook : null

  Component.onCompleted: BlurManager.register(root)
  Component.onDestruction: BlurManager.unregister(root)
}
