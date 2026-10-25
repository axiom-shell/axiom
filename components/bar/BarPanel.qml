pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import QtQuick

import qs.config
import qs.services.core
import qs.services.compositor
import qs.services.ui
import qs.components.hosts.popout

// One bar's layer-shell window (shell/Bar makes one per BarManager.bars
// entry): its screen, layer and exclusive zone, holding the bar's BarContainer.
PanelWindow {
  id: root

  required property var barConfig

  // BarManager.bars has resolved the monitor (an empty one is the primary)
  readonly property ShellScreen targetScreen: General.outputs.find(s => s.name === barConfig.monitor) ?? General.outputs[0] ?? null
  screen: targetScreen
  // A solid bar sits at the screen edge, and the screen border's strip
  // (arranged after it) overlaps its inner part, drawing the bar's inner
  // stroke. Any other bar (transparent, pills or floating, with the border
  // on) sits inside the border instead (`insideBorder`): its
  // axiom-bar-pill, -transparent or -floating layer rule orders it after
  // the border (arranged inside it, drawn over it), with its outer edge on
  // the border's stroke so pills can cover it. Bars along the screen's
  // longer edge have rules of their own (-long), arranged after the shorter
  // edge's bars of their kind, so which bar takes a shared corner never
  // depends on which mapped first (BarEnds). All are on the Top layer, so a fullscreen window covers
  // them.
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.exclusiveZone: root.reservedZone
  // On a transparent or pill bar, how far in from its outer edge it
  // reserves (floating edge menus place themselves against that)
  readonly property int reservedZone: Bar.reservedZone(barConfig, CompositorManager.gapsOut[Bar.edgeName(barConfig.location)] ?? 0)
  WlrLayershell.namespace: root.layerNamespace
  readonly property string layerNamespace: Bar.layerNamespace(barConfig)
  // The bar container paints the background (or not, when transparent)
  color: "transparent"

  anchors {
    top: (barConfig.top || barConfig.vertical)
    bottom: (barConfig.bottom || barConfig.vertical)
    left: (barConfig.left || !barConfig.vertical)
    right: (barConfig.right || !barConfig.vertical)
  }

  // A bar inside the border reaches onto its strokes: its own edge (so
  // pills cover it) and the stroke at either end (so a pill at an end can
  // join the perpendicular edge), but not onto a bar it makes way for at a
  // corner (BarEnds' `reach`). Margins on the unanchored side are ignored.
  readonly property int _outerReach: barConfig.insideBorder ? Appearance.borderWidth : 0
  margins {
    top: -(root.barConfig.vertical ? root.barConfig.ends.start.reach : root._outerReach)
    bottom: -(root.barConfig.vertical ? root.barConfig.ends.end.reach : root._outerReach)
    left: -(root.barConfig.vertical ? root._outerReach : root.barConfig.ends.start.reach)
    right: -(root.barConfig.vertical ? root._outerReach : root.barConfig.ends.end.reach)
  }

  // Once the windows before it in the stack have mapped (LayerSlot)
  visible: slot.shown
  LayerSlot {
    id: slot
    window: root
    namespace: root.layerNamespace
    wanted: root.barConfig.enabled
  }

  // With pills, room past the bar for the fillet where an end pill meets
  // the perpendicular edge, and for a shadow; click-through (see mask),
  // and not reserved
  readonly property int thickness: barConfig.extent + Math.max(barConfig.pills ? Appearance.borderRadius : 0, barConfig.shadowReach)
  implicitHeight: barConfig.vertical ? 0 : thickness
  implicitWidth: barConfig.vertical ? thickness : 0

  mask: Region {
    item: bar
  }

  Component.onCompleted: {
    ShellManager.registerGrabPartner(root, root.screen?.name);
    ShellManager.registerBar(root);
  }
  // The overlay's focus grab lets input through to the bar (see
  // ShellManager.grabPartners)
  onScreenChanged: ShellManager.registerGrabPartner(root, root.screen?.name)
  Component.onDestruction: {
    ShellManager.unregisterGrabPartner(root);
    ShellManager.unregisterBar(root);
  }

  // Where the window is on its screen (LayerOrigin; null until it's
  // mapped): the blur window draws the bar's shapes and popouts from it
  readonly property var screenOrigin: placeOnScreen.origin
  // ...else where it most likely is, for its popouts' footprints
  // (PopoutManager)
  readonly property point screenPlaced: placeOnScreen.placed
  LayerOrigin {
    id: placeOnScreen
    window: root
    namespace: root.layerNamespace
    edge: root.barConfig.location
    estimatedStart: BarManager.barStartOn(root.screen, root.barConfig.location, true)
  }

  // What PopoutAnchors in it open their popouts in
  readonly property var popoutHost: barPopouts

  // The widget area, where the pills are
  readonly property var container: bar.barContainer

  BarPopouts {
    id: barPopouts
    barConfig: root.barConfig
    panel: root
    screen: root.screen
  }

  // The bar's own extent, at its outer edge. Placed by plain geometry, not
  // conditional anchors: when a bar changes orientation, a `width:
  // undefined` binding resets width to the implicit 300 after the anchors
  // have sized it, and the anchors don't reapply until the window resizes,
  // leaving a 300px bar that hides most of its widgets as overflow.
  StandaloneBar {
    id: bar
    x: root.barConfig.right ? parent.width - width : 0
    y: root.barConfig.bottom ? parent.height - height : 0
    width: root.barConfig.vertical ? root.barConfig.extent : parent.width
    height: root.barConfig.vertical ? parent.height : root.barConfig.extent
    barConfig: root.barConfig
    panel: root
    screen: root.screen
  }
}
