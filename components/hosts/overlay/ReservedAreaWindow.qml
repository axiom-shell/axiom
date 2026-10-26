pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.methods

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

  anchors {
    left: true
    right: true
    top: true
    bottom: true
  }

  // A transparent bar reserves Hyprland's gaps_out less than its extent
  // (see BarPanel) and has no stroke to land on: sit at its invisible
  // inner edge instead, past the reserved space by that gap. A floating
  // bar reserves up to its islands' inner side: land on their stroke, as
  // on any other bar's.
  readonly property var _edges: ScreenEdgeManager.edgesFor(root.screen)
  function _margin(side, location) {
    if (ScreenEdgeManager.screenEdgeOpen(root.screen, location))
      return 0;
    const bar = root._edges[side];
    if (bar?.background === "transparent")
      return CompositorManager.gapsOut[side] ?? 0;
    return (bar ? Bar.reserveTrim(bar, CompositorManager.gapsOut[side] ?? 0) : 0) - Appearance.borderWidth;
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
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0

  Region {
    id: stepAsideMask
  }
}
