pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.methods
import qs.components.reusable
import qs.components.hosts.popout

// A free menu (placement `free`): a box of its own on no edge, in a
// full-screen Top-layer window (axiom-menu) that never resizes, its input
// masked to the box. It opens where FreeMenuPlace puts it: at the bar
// widget that opened it as its popout, else at its `freeAnchor` (the
// free area's centre, the cursor, or a point), clamped clear of the bars;
// and comes in as `freeAnimation` says (a fade, a scale, or a slide from
// its widget's side or the nearest screen edge). The box is a detached
// EdgeSurface (SurfaceContext.free), with a submenu (SubmenuHost) for its
// Submenu rows. Like the edge hosts it follows EdgeMenuManager
// (EdgeMenuSync) and holds a PopoutClaim, ranked as it was opened.
// With `draggable` on its box moves while dragged by its top padding (its
// header); dropped, opened on its own, that spot is its session spot
// (EdgeMenuManager.positions), where a bind or IPC opens it again until
// logout. A right click there offers Reset position.
//
// It also shows a popped-out edge menu (EdgeMenuManager.popOut): at the
// spot its edge box was, appearing at once, held open as if pinned (an
// underlay), with its edge's layout; dragged, it moves for the moment
// only. Its close docks it.
//
// Open/close and hover-loss dismissal are PopoutWrapperBase's, as for the
// popouts.
PopoutWrapperBase {
  id: root

  required property var menu
  required property ShellScreen screen
  readonly property string menuId: root.menu.id
  // A popped-out edge menu's spot as it popped out ({ screen, x, y }),
  // else null (a free menu)
  readonly property var poppedOut: EdgeMenuManager.poppedOut[root.menuId] ?? null
  readonly property bool popped: root.poppedOut !== null && !EdgeMenusConfig.isFree(root.menu)
  // Laid out as on its edge while popped out (a top or bottom menu's
  // modules along a row), else down a column
  readonly property bool vertical: !root.popped || root.menu.edge === "left" || root.menu.edge === "right"
  // Its box drawn: a popped-out menu's edge host can go (EdgeMenu)
  readonly property bool boxShown: surface.active

  // Its box's frame: a box floating free of the edges
  readonly property var _free: SurfaceContext.free()
  readonly property real contentPadding: Appearance.borderWidth + PopoutsConfig.padding
  readonly property var colors: EdgeMenusConfig.colorsOf(root.menu)
  // fade | scale | slide; popped out, it appears at once where its edge
  // box was (an instant fade)
  readonly property string animation: root.popped ? "fade" : root.menu.freeAnimation
  // Its window is on Top, under the Overlay layer (SubPopout reads it)
  readonly property bool onOverlayLayer: false

  // What's kept clear at each screen edge: what's reserved there, and the
  // gap windows keep from it
  function _inset(side) {
    return ScreenEdgeManager.reservedWithMenusOn(root.screen, side) + (CompositorManager.gapsOut[ScreenEdge.name(side)] ?? 0);
  }
  readonly property var insets: ({
      "top": root._inset(ScreenEdge.Top),
      "bottom": root._inset(ScreenEdge.Bottom),
      "left": root._inset(ScreenEdge.Left),
      "right": root._inset(ScreenEdge.Right)
    })

  // The box at its content's size (a submenu's stretch drawn round it)
  readonly property Item contentItem: loader.item as Item
  readonly property real boxWidth: Math.ceil(root.contentItem?.implicitWidth ?? 0) + root.contentPadding * 2
  readonly property real boxHeight: Math.ceil(root.contentItem?.implicitHeight ?? 0) + root.contentPadding * 2
  // Room for the modules down the free area (across it, laid out as a
  // top or bottom menu): past it they scroll
  readonly property real maxLength: root.vertical ? (root.screen?.height ?? 0) - root.insets.top - root.insets.bottom - root.contentPadding * 2 : (root.screen?.width ?? 0) - root.insets.left - root.insets.right - root.contentPadding * 2

  // What opened it, taken as it opens: a bar widget on its screen
  // (PopoutAnchor.screenRect, its bar's edge as a name), and the cursor
  // for `freeAnchor.at: cursor` (asked for first: `_locating` holds the
  // claim back until it's known). A close (no data) keeps them until the
  // box has gone.
  property var _opener: null
  property var _cursor: null
  property bool _locating: false
  // Opened by a bar widget (its popout, a Button): it goes to the widget,
  // and a drag of it is for the moment (FreeMenuPlace.keepsDrag)
  property bool _fromWidget: false
  // Where it was dragged to since it opened ({ x, y }, its box's top-left
  // on the screen), else null
  property var _dragged: null
  onCurrentDataChanged: {
    const data = root.currentData;
    if (!data)
      return;
    root._dragged = null;
    root._fromWidget = !!data.anchorItem;
    const rect = data.anchorItem?.screenRect?.() ?? null;
    root._opener = rect && rect.screen?.name === root.screen?.name ? {
      "x": rect.x,
      "y": rect.y,
      "width": rect.width,
      "height": rect.height,
      "edge": ScreenEdge.name(rect.edge)
    } : null;
    root._cursor = null;
    root._locating = !root._opener && !root.spot && root.menu.freeAnchor.at === "cursor";
    if (!root._locating)
      return;
    CompositorManager.withCursorPos(pos => {
      if (root.currentData !== data)
        return;
      root._cursor = pos && root.screen ? {
        "x": pos.x - root.screen.x,
        "y": pos.y - root.screen.y
      } : null;
      root._locating = false;
    });
  }

  // The spot it takes over its anchor: where it was dragged, else its
  // session spot when opened on its own (FreeMenuPlace.spot)
  readonly property var spot: FreeMenuPlace.spot({
    "dragged": root._dragged,
    "popOut": root.poppedOut,
    "fromWidget": root._fromWidget,
    "session": EdgeMenuManager.positions[root.menuId] ?? null,
    "screen": root.screen?.name ?? "",
    "anchor": root.menu.freeAnchor,
    "draggable": root.menu.draggable
  })
  readonly property bool canDrag: FreeMenuPlace.canDrag(root.menu, root.popped)
  // Reset (its header's menu, IPC resetPosition): back to its anchor, or
  // its widget, even dragged since it opened
  Connections {
    target: EdgeMenuManager
    function onPositionReset(id) {
      if (id === root.menuId)
        root._dragged = null;
    }
  }

  // Where its box goes on the screen, and the edge it slides in from
  readonly property var place: FreeMenuPlace.place({
    "width": root.screen?.width ?? 0,
    "height": root.screen?.height ?? 0,
    "insets": root.insets,
    "box": {
      "width": root.boxWidth,
      "height": root.boxHeight
    },
    "opener": root._opener,
    "anchor": root.menu.freeAnchor,
    "cursor": root._cursor,
    "spot": root.spot
  })
  // ...that edge, kept once shown: its box growing past its middle
  // mustn't turn its shape round
  property ClosedLatch _slideFrom: ClosedLatch {
    source: ScreenEdge.fromName(root.place.slideFrom)
    closed: !root._shown
  }
  readonly property int slideEdge: root._slideFrom.value ?? ScreenEdge.Top

  // Set a tick after the box first shows, so it opens at its size and
  // shape and only animates after (as EdgePopout's)
  readonly property bool _shown: panel.visible && root.isOpen
  property bool settled: false
  on_ShownChanged: {
    if (!root._shown)
      root.settled = false;
    else
      Qt.callLater(() => root.settled = root._shown);
  }

  // Scaling in or out (`animation: scale`): its fill isn't the blur
  // window's meanwhile, which doesn't scale with it
  readonly property real _scaleTarget: root.animation !== "scale" || surface.active ? 1 : 0.9
  property real _scale: root._scaleTarget
  Behavior on _scale {
    NumberAnimation {
      duration: Appearance.animNormal
      easing.type: Appearance.easing
    }
  }
  readonly property bool scaling: root._scale < 1

  // Its place among the popouts (PopoutManager), ranked as it was opened
  // (EdgeMenuManager.claimKinds): a widget's popout as a bar popout, else
  // a menu; held by the editor, it gives way and comes back. Pinned or
  // popped out, it's an underlay (FreeMenuPlace.underlay): drawn under the
  // popouts on its Top layer, it never closes anything and nothing opening
  // over it closes it (PopoutGeometry.isUnderlay)
  property PopoutClaim claim: PopoutClaim {
    key: "menu:" + root.menuId
    kind: root.currentData?.claimKind ?? "menu"
    screen: root.screen?.name ?? ""
    edge: ""
    resident: sync.held
    underlay: FreeMenuPlace.underlay(EdgeMenuManager.isPinned(root.menuId), root.popped)
    occupied: root.occupied
    closing: root.isClosing
    wanted: root.isOpen && root.contentItem !== null && placeOnScreen.settled && !root._locating
    footprint: PopoutGeometry.offset(surface.footprint, Qt.point(placeOnScreen.placed.x + surface.x, placeOnScreen.placed.y + surface.y))
    onEvicted: root.hide()
    onRefused: root.hide()
  }
  // Granted (or closing after it was)
  readonly property bool claimed: root.claim.held

  autoDismiss: sync.autoDismiss
  dismissDelay: EdgeMenusConfig.closeDelayOf(root.menu)
  keepAlive: surface.hovered
  currentItem: root.contentItem
  window: panel

  EdgeMenuSync {
    id: sync
    host: root
    menu: root.menu
    screen: root.screen
    window: panel
    onWarpRequested: CompositorManager.warpCursorToLayer("axiom-menu", root.screen?.name ?? "", panel.width, panel.height, boxArea.x + boxArea.width / 2, boxArea.y + boxArea.height / 2)
  }

  // What its box meets (SurfaceContext.free), as an EdgeSurface and its
  // SubmenuHost read a host's EdgePlacement: nothing, sliding in from
  // `slideEdge`; its fill drawn by the blur window where that backs Top
  // surfaces on its screen (not while it scales), its shadow BarStyle's
  QtObject {
    id: shape
    readonly property int edge: root.slideEdge
    readonly property int connectorGap: Appearance.connectorGap
    readonly property bool detached: root._free.detached
    readonly property bool straight: root._free.straight
    readonly property var place: root._free.place
    readonly property bool straightJoinStart: false
    readonly property bool straightJoinEnd: false
    readonly property int backfill: root._free.backfill
    readonly property bool onOverlayLayer: root.onOverlayLayer
    readonly property var origin: placeOnScreen.origin
    readonly property bool backed: BlurManager.backsOn(root.screen, false) && placeOnScreen.origin !== null && !root.scaling
    readonly property bool opaque: BlurManager.opaqueOn(root.screen)
    readonly property var shadowLook: BarStyle.look
    readonly property var submenuJoin: null
  }

  // ---- Its submenu (SubPopout, through its SubmenuHost) ----
  // Opened by a Submenu row in it, beside its box: towards the screen's
  // nearer half (SubmenuSide); one longer than the box stretches it
  // past its top or bottom
  submenuHost: slot
  SubmenuHost {
    id: slot
    wrapper: root
    screen: root.screen
    popupSurface: surface
    boxRect: Qt.rect(boxArea.x, boxArea.y, boxArea.width, boxArea.height)
    popupScreenOrigin: placeOnScreen.origin
    popupScreenPlaced: placeOnScreen.placed
    animate: root.settled
    geometry: shape
  }
  readonly property real _stretchTop: slot.shownStretchTop
  readonly property real _stretchBottom: slot.shownStretchBottom

  PanelWindow {
    id: panel
    screen: root.screen
    // Where map order alone stacks: mapped from the start, drawing and
    // taking nothing while closed (LayerSlot.idle), so opening never
    // maps it after the bars and popouts it sits under
    visible: menuSlot.shown
    LayerSlot {
      id: menuSlot
      window: panel
      namespace: "axiom-menu"
      wanted: root.occupied && loader.status === Loader.Ready
      held: true
    }
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "axiom-menu"
    WlrLayershell.keyboardFocus: focusGrab.exclusive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    // The whole screen, the bars' zones included: FreeMenuPlace keeps
    // the box clear of them
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // What PopoutAnchors in its content open in
    readonly property var popoutHost: root.submenu
    // Its content doesn't grow the box (a menu's cards are fixed): a
    // StyledComboEntry opens its list inline (BarPopouts' room is a number)
    readonly property var popoutRoom: null

    // Input on the box alone, once it's granted its place (and its
    // header's menu while that's open)
    mask: Region {
      item: root.claimed && !menuSlot.idle ? boxArea : null
      regions: [panel.headerMenuArea]
    }
    property Region headerMenuArea: Region {
      item: headerMenu.visible ? headerMenu.background : null
    }

    // The box, in the window (as drawn, a submenu's stretch included)
    Item {
      id: boxArea
      x: surface.x + surface.boxRect.x
      y: surface.y + surface.boxRect.y
      width: surface.boxRect.width
      height: surface.boxRect.height
    }

    StyledContextMenu {
      id: headerMenu
      parent: boxArea
      onTriggered: id => {
        if (id === "reset")
          EdgeMenuManager.resetPosition(root.menuId);
      }
    }

    // Unpinned with close.onOutsideClick: a click outside it (and its
    // submenu) closes it. Its header's menu takes it too while open, so a
    // click elsewhere closes that menu (only) on a held one, and Escape
    // reaches it
    readonly property bool closesOnOutsideClick: root.menu.close.onOutsideClick && !sync.held
    FocusGrab {
      id: focusGrab
      windows: [panel, slot.submenu.popupWindow].concat(SurfaceManager.modalWindows)
      active: panel.visible && root.isOpen && root.claimed && (panel.closesOnOutsideClick || headerMenu.visible)

      onActiveChanged: {
        if (active && !headerMenu.visible)
          root.contentItem?.forceActiveFocus();
      }

      // Only a real click, never another surface's grab starting
      onDismissed: {
        headerMenu.close();
        if (panel.closesOnOutsideClick)
          root.hide();
      }
    }

    // Where the window is on screen (its whole screen): the blur window
    // draws the box's fill from there
    LayerOrigin {
      id: placeOnScreen
      window: panel
      namespace: "axiom-menu"
      layer: WlrLayer.Top
    }

    EdgeSurface {
      id: surface

      geometry: shape
      submenu: slot
      screenName: root.screen?.name ?? ""
      windowShown: panel.visible
      animateShape: root.settled

      // Its box where FreeMenuPlace puts it, a submenu's stretch round it
      x: root.place.x - surface.boxRect.x
      y: root.place.y - root._stretchTop - surface.boxRect.y
      width: implicitWidth
      height: implicitHeight

      // Fades in place, or scales as it does; slides from its edge
      fade: root.animation !== "slide"
      animationDuration: root.popped ? 0 : Appearance.animNormal
      // While the blur window backs surfaces, once it knows where this
      // one is, so it never shows unbacked beside them
      active: root.isOpen && root.claimed && panel.visible && (!BlurManager.backingOn(root.screen) || placeOnScreen.settled)
      boxWidth: root.boxWidth
      boxHeight: root.boxHeight + root._stretchTop + root._stretchBottom
      fillColor: root.colors.fill
      strokeColor: root.colors.stroke

      transform: Scale {
        origin.x: surface.boxRect.x + surface.boxRect.width / 2
        origin.y: surface.boxRect.y + surface.boxRect.height / 2
        xScale: root._scale
        yScale: root._scale
      }

      // Its header, the box's top padding: dragged (`draggable`), it moves
      // the box; dropped, a free menu opened on its own keeps the spot for
      // the session (EdgeMenuManager.storePosition). Nothing is previewed
      // meanwhile: the box just moves (clamped, FreeMenuPlace)
      DragArea {
        id: header
        // In the surface, so hovering it is hovering the box (keepAlive)
        z: 3
        y: root._stretchTop
        width: root.boxWidth
        height: root.contentPadding
        visible: root.canDrag && root.claimed && root.isOpen
        threshold: 2
        // The box's place and the pointer in the window (the screen) as
        // the drag began
        property point _from
        property point _press
        onDragStarted: (x, y) => {
          header._from = Qt.point(root.place.x, root.place.y);
          header._press = header.mapToItem(null, x, y);
        }
        onDragMoved: (x, y) => {
          const at = header.mapToItem(null, x, y);
          root._dragged = {
            "x": header._from.x + at.x - header._press.x,
            "y": header._from.y + at.y - header._press.y
          };
        }
        onDropped: {
          if (FreeMenuPlace.keepsDrag({
            "free": EdgeMenusConfig.isFree(root.menu),
            "poppedOut": root.popped,
            "fromWidget": root._fromWidget
          }))
            EdgeMenuManager.storePosition(root.menuId, {
              "screen": root.screen?.name ?? "",
              "x": root.place.x,
              "y": root.place.y
            });
        }
      }

      // A right click on the header: back to its freeAnchor (a free menu's
      // session spot forgotten)
      MouseArea {
        z: 2
        anchors.fill: header
        visible: header.visible && EdgeMenusConfig.isFree(root.menu)
        acceptedButtons: Qt.RightButton
        onClicked: mouse => {
          headerMenu.items = [
            {
              "id": "reset",
              "text": I18n.tr("Reset position"),
              "icon": "restart_alt",
              "enabled": EdgeMenuManager.positions[root.menuId] !== undefined || root._dragged !== null
            }
          ];
          headerMenu.openAt(header, mouse.x, mouse.y);
        }
      }

      Loader {
        id: loader
        x: root.contentPadding
        y: root.contentPadding + root._stretchTop
        width: root.contentItem?.implicitWidth ?? 0
        height: root.contentItem?.implicitHeight ?? 0
        active: root.occupied
        asynchronous: false

        sourceComponent: EdgeMenuBody {
          menu: root.menu
          free: true
          vertical: root.vertical
          maxLength: root.maxLength
        }

        onLoaded: root.updateDismissTimer()
      }
    }
  }
}
