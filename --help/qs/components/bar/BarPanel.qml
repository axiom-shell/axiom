pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import QtQuick

import qs.config
import qs.services.ui
import qs.services.compositor
import qs.components.hosts.popout
import qs.components.methods
import qs.components.reusable

// One bar's layer-shell window (shell/Bar makes one per ScreenEdgeManager.bars
// entry): its screen, layer and exclusive zone, holding the bar's BarContainer.
PanelWindow {
  id: root

  required property var barConfig

  // ScreenEdgeManager.bars has resolved the monitor (an empty one is the primary)
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
  // them. Bars sharing an edge stack, each laid out past what the ones
  // arranged before it reserve (BarEnds.placeStack); bars of one rule on
  // an edge map in list order (`layerRank`), as the compositor breaks
  // their tie by map order.
  WlrLayershell.layer: WlrLayer.Top
  // How far in from its outer edge it reserves (BarEnds.placeStack: a
  // transparent bar facing the windows less gaps_out, a solid bar under
  // the border's strip less the strip; an auto-hiding bar nothing, unless
  // pinned)
  WlrLayershell.exclusiveZone: root.barConfig.zone
  WlrLayershell.namespace: root.layerNamespace
  readonly property string layerNamespace: BarsConfig.layerNamespace(barConfig)
  // The bar container paints the background (or not, when transparent)
  color: "transparent"

  anchors {
    top: (barConfig.top || barConfig.vertical)
    bottom: (barConfig.bottom || barConfig.vertical)
    left: (barConfig.left || !barConfig.vertical)
    right: (barConfig.right || !barConfig.vertical)
  }

  // A bar inside the border reaches onto its strokes: its own edge (so
  // pills cover it; a pill bar on the border reaches back over the whole
  // frame, so it lies as a solid bar does: BarEnds.placeStack's
  // outerReach) and the stroke at either end (so a pill at an end can
  // join the perpendicular edge), but not onto a bar it makes way for at a
  // corner (BarEnds' `reach`). Margins on the unanchored side are ignored.
  readonly property int _outerReach: root.barConfig.outerReach
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
    rank: root.barConfig.layerRank
    rankGroup: ScreenEdge.name(root.barConfig.location)
    wanted: root.barConfig.enabled
  }

  // With pills, room past the bar for the fillet where an end pill meets
  // the perpendicular edge, and for a shadow; click-through (see mask),
  // and not reserved
  readonly property int thickness: barConfig.extent + Math.max(barConfig.pills ? Appearance.borderRadius : 0, barConfig.shadowReach)
  implicitHeight: barConfig.vertical ? 0 : thickness
  implicitWidth: barConfig.vertical ? thickness : 0

  // Its bar where it rests (not where it has slid to, so the pointer on
  // it as it slides in still holds it); hidden, only its edge strip takes
  // the pointer
  mask: Region {
    item: root.revealed ? barSlot : edgeStrip
  }

  // --- Auto-hide (BarRevealManager) ---

  // Shown: always unless it auto-hides; hidden, it slides out of its
  // window toward its edge, behind the bars outside it, keeping its slot
  // (it reserves nothing either way, unless pinned)
  readonly property bool revealed: BarRevealManager.shownOf(root.barConfig)
  property real _shown: root.revealed ? 1 : 0
  Glide on _shown {
    duration: Appearance.animNormal
  }
  // How far it has slid out: its window's whole depth, shadow included
  readonly property real slide: (1 - root._shown) * root.thickness
  // Mapped and not hiding: what surfaces on its edge stand on (a dock's
  // or a popout's attach point) and what a bar beside it merges into.
  // Hidden, they take it as absent: the frame, or the bar outside it.
  readonly property bool present: root.visible && root.revealed
  // Mapped with any of it still in view (sliding in or out): the border's
  // stroke stays open under it until it has gone
  readonly property bool onScreen: root.visible && root._shown > 0

  // A window over its slot, or a fullscreen one on its screen
  // (whenCovered). Fullscreen, it stays on its layer under that window:
  // nothing maps or remaps for it
  readonly property bool covered: root.barConfig.autoHide === "whenCovered" && !!root.screen && (CompositorManager.hasFullscreen(root.screen.name) || CompositorManager.windowsCover(root.screen, root._slotRect()))
  onCoveredChanged: BarRevealManager.setCovered(root.barConfig.id, root.covered)

  // Its slot on the screen, screen-local: along its whole edge, across
  // from its outer edge for its extent
  function _slotRect() {
    const across = root.barConfig.outer;
    const depth = root.barConfig.extent;
    const w = root.screen.width, h = root.screen.height;
    if (root.barConfig.top)
      return Qt.rect(0, across, w, depth);
    if (root.barConfig.bottom)
      return Qt.rect(0, h - across - depth, w, depth);
    if (root.barConfig.left)
      return Qt.rect(across, 0, depth, h);
    return Qt.rect(w - across - depth, 0, depth, h);
  }

  // What holds it shown: an open popout of its own, an edge menu opened
  // from it, the bar editor with this bar selected
  readonly property bool _popoutOpen: barPopouts.occupied
  readonly property bool _menuOpen: Object.keys(EdgeMenuManager.openMenus).some(id => root._holds(EdgeMenuManager.anchors[id] ?? null))
  readonly property bool _editorHeld: BarManager.editing && BarManager.selectedBar()?.id === root.barConfig.sourceId
  on_PopoutOpenChanged: BarRevealManager.hold(root.barConfig.id, "popout", root._popoutOpen)
  on_MenuOpenChanged: BarRevealManager.hold(root.barConfig.id, "menu", root._menuOpen)
  on_EditorHeldChanged: BarRevealManager.hold(root.barConfig.id, "editor", root._editorHeld)

  // Whether an item (an edge menu's anchor: a PopoutAnchor, a Button) is
  // on this bar
  function _holds(item) {
    for (let p = item; p; p = p.parent)
      if (p === bar)
        return true;
    return false;
  }

  // The bar where it rests, shown (the mask while it's revealed)
  Item {
    id: barSlot
    x: root.barConfig.right ? parent.width - width : 0
    y: root.barConfig.bottom ? parent.height - height : 0
    width: bar.width
    height: bar.height
  }

  // The strip at its window's outer edge (the screen edge, for a bar
  // lying on it) that takes the pointer while it's hidden
  Item {
    id: edgeStrip
    readonly property int size: ScreenEdge.triggerSize
    x: root.barConfig.right ? parent.width - width : 0
    y: root.barConfig.bottom ? parent.height - height : 0
    width: root.barConfig.vertical ? edgeStrip.size : parent.width
    height: root.barConfig.vertical ? parent.height : edgeStrip.size
  }

  Component.onCompleted: {
    SurfaceManager.registerGrabPartner(root, root.screen?.name);
    ScreenEdgeManager.registerBar(root);
    BarRevealManager.register(root.barConfig.id);
    BarRevealManager.setCovered(root.barConfig.id, root.covered);
    BarRevealManager.hold(root.barConfig.id, "editor", root._editorHeld);
  }
  // The overlay's focus grab lets input through to the bar (see
  // SurfaceManager.grabPartners)
  onScreenChanged: SurfaceManager.registerGrabPartner(root, root.screen?.name)
  Component.onDestruction: {
    SurfaceManager.unregisterGrabPartner(root);
    ScreenEdgeManager.unregisterBar(root);
    BarRevealManager.forget(root.barConfig.id);
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
    estimatedStart: ScreenEdgeManager.barStartOn(root.screen, root.barConfig, true)
  }

  // What PopoutAnchors in it open their popouts in
  readonly property var popoutHost: barPopouts

  // The widget area, where the pills are
  readonly property var container: bar

  // A click on the bar, while a focus grab without a native grab is on,
  // is outside a grab that doesn't let input through to the bar
  // (FocusGrab). Reported once released, after the click's own action: a
  // bar button toggling the launcher closes it, never closes and reopens it
  Item {
    anchors.fill: parent
    z: 1
    // The pointer on the bar, or on its edge strip while it's hidden (the
    // mask): what hovering shows an auto-hiding bar by
    HoverHandler {
      id: hover
      enabled: root.barConfig.autoHiding
      onHoveredChanged: BarRevealManager.setHover(root.barConfig.id, hover.hovered)
    }
    PointHandler {
      id: barPress
      enabled: BackdropManager.catching
      acceptedButtons: Qt.AllButtons
      // The grabs on when it was pressed: one the click opens (a bar button
      // opening the power menu over the launcher) isn't outside
      property var since: []
      onActiveChanged: {
        if (barPress.active) {
          barPress.since = BackdropManager.grabs;
        } else {
          const since = barPress.since;
          Qt.callLater(() => BackdropManager.clickedOutside(root, since));
        }
      }
    }
  }

  BarPopouts {
    id: barPopouts
    barConfig: root.barConfig
    panel: root
    screen: root.screen
  }

  // The bar's own extent, at its outer edge. Placed by plain geometry, not
  // conditional anchors: when a bar changes orientation, a `width:
  // undefined` binding resets width to the implicit one after the anchors
  // have sized it, and the anchors don't reapply until the window resizes,
  // leaving a short bar that hides most of its widgets as overflow.
  // Slid out by geometry (not a Translate) while hidden, so its blur
  // shapes and shadow follow, cut to the window (blurClip)
  BarContainer {
    id: bar
    x: root.barConfig.vertical ? (root.barConfig.right ? parent.width - width + root.slide : -root.slide) : 0
    y: root.barConfig.vertical ? 0 : (root.barConfig.bottom ? parent.height - height + root.slide : -root.slide)
    width: root.barConfig.vertical ? root.barConfig.extent : parent.width
    height: root.barConfig.vertical ? parent.height : root.barConfig.extent
    barConfig: root.barConfig
    panel: root
    screen: root.screen
    blurClip: root.barConfig.autoHiding && root.screenOrigin ? Qt.rect(root.screenOrigin.x, root.screenOrigin.y, root.width, root.height) : null
  }
}
