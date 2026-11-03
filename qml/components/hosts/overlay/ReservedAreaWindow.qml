pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.hosts.popout

// A full-screen Overlay-layer window placed inside the border's and bars'
// reserved area (the overlay, the onboarder). Normal exclusion with no zone
// of its own puts it inside that area, wherever the bars are, so its content
// centers in the free space and the bars stay reachable; the -borderWidth
// margin lines it up with their inner stroke (as EdgePopout). A bare screen
// edge (no border, no bar) has no stroke to land on: it meets the edge. The
// window is transparent: the screen's backdrop (BackdropRequest) dims the
// monitor under it.
//
// While SurfaceManager.steppedAside (another polkit agent's prompt, which
// opens under the Overlay layer) it stays mapped, so nothing in it is
// rebuilt, but takes no input or keys; its content hides (`content`).
PanelWindow {
  id: root

  // Stepped aside: subclasses hide their content on it
  readonly property bool steppedAside: SurfaceManager.steppedAside
  // Its layer-shell namespace
  required property string layerNamespace
  // Its top-left on its screen, or null while unknown (a wallpaper
  // picker's click point)
  readonly property var screenOrigin: placeOnScreen.origin

  anchors {
    left: true
    right: true
    top: true
    bottom: true
  }

  // A transparent bar facing the windows reserves Hyprland's gaps_out
  // less than its extent (its `trim`, BarEnds.placeStack) and has no
  // stroke to land on: sit at its invisible inner edge instead, past the
  // reserved space by that gap (none with an inner accent line, which it
  // reserves up to). A floating bar reserves up to its islands' inner
  // side: land on their stroke, as on any other bar's. The innermost
  // reserving bar on the edge decides (BarEnds.edgeOf's facing), where
  // the reserved space ends.
  function _margin(side, location) {
    if (ScreenEdgeManager.screenEdgeOpen(root.screen, location))
      return 0;
    const bar = ScreenEdgeManager.edgeOn(root.screen, location).facing;
    if (bar?.background === "transparent")
      return bar.trim;
    return -Appearance.borderWidth;
  }
  margins {
    left: root._margin("left", ScreenEdge.Left)
    right: root._margin("right", ScreenEdge.Right)
    top: root._margin("top", ScreenEdge.Top)
    bottom: root._margin("bottom", ScreenEdge.Bottom)
  }

  color: "transparent"
  focusable: !root.steppedAside
  mask: root.steppedAside ? stepAsideMask : null
  WlrLayershell.keyboardFocus: root.steppedAside ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: root.layerNamespace
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0

  Region {
    id: stepAsideMask
  }

  LayerOrigin {
    id: placeOnScreen
    window: root
    namespace: root.layerNamespace
    layer: WlrLayer.Overlay
  }
}
