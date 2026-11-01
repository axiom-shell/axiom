pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.methods

/**
 * A popout that slides out of a screen edge and joins the screen border
 * (or a bar on that edge) with the same connector + fillets as bar
 * popouts — see AttachedSurface.qml.
 *
 * Open/close/queue state and hover-loss dismissal come from
 * PopoutWrapperBase, the same as bar popouts. Unlike bar popouts, every
 * instance owns its own state, so instantiate one per screen (Variants
 * over General.screensFor(mode)) and they open independently.
 *
 * Content is a Component, loaded only while open (unless keepLoaded). It
 * can optionally expose `autoDismiss` / `dismissDelay` / `hovered`
 * exactly like bar popout content; hovering the surface or the trigger strip already
 * keeps it open without the content doing anything.
 *
 * Usage:
 *   Variants {
 *     model: General.screensFor(mode)
 *     delegate: EdgePopout {
 *       required property ShellScreen modelData
 *       screen: modelData
 *       edge: ScreenEdge.Right
 *       content: Component { MyPanel {} }
 *     }
 *   }
 */
PopoutWrapperBase {
  id: root

  required property ShellScreen screen

  // Side of the screen to attach to (a ScreenEdge value)
  property int edge: ScreenEdge.Right
  // Position along the edge: 0-1 of the available length, plus pixels
  property real position: 0.5
  property real positionOffset: 0

  property Component content: null
  readonly property Item contentItem: loader.item as Item
  // The content's largest size across the edge, if it changes size while
  // open: the window keeps room for it, so it isn't resized (and, on the
  // bottom or right edge, moved by the compositor a frame late) each time
  property real maxContentDepth: 0
  // On a top or bottom edge, content that can open submenus (an edge
  // menu's Submenu modules): the window takes the whole depth the screen
  // has across its edge, as a submenu longer than the box stretches it
  // away from its edge, and a window growing while it shows is drawn for a
  // frame with its old contents squeezed into the new size
  property bool roomForSubmenus: false
  // Keep content alive while closed (e.g. content that itself decides
  // when the popout should open)
  property bool keepLoaded: false

  // Hover strip at the very edge of the screen that opens the popout
  property bool triggerEnabled: true
  property int triggerWidth: PopoutsConfig.edgeTriggerSize
  property int triggerLength: 200 // fixed px: a hover strip on the screen's edge, like edgeTriggerSize
  property int hoverDelay: PopoutsConfig.openDelay
  // The strip's centre along the edge in screen px (NaN: at the box's
  // `position`, EdgeTrigger.centre)
  property real triggerCentre: NaN

  property bool wantsKeyboardFocus: false
  // Take the keyboard when clicked, without a focus grab (content that may
  // hold a text field, e.g. an edge menu's modules)
  property bool keyboardOnDemand: false
  // A plain rounded box a connector gap in from the edge, not joined to it:
  // held off the edge, or on a bar with nothing to grow out of
  // (EdgePlacement.detached)
  readonly property bool detached: placement.detached
  property bool closeOnClickOutside: false
  // Space between the box and its content
  property real contentPadding: Appearance.borderWidth + PopoutsConfig.padding
  // Extra distance in from the attach edge (for a detached box)
  property real edgeOffset: root.attachAt - root.attachBase
  // How far back towards the screen edge a detached box slides in from,
  // as a bar popout's: from under a transparent bar on its edge (its outer
  // edge, past the border stroke it lies on inside the border), its window
  // starting there on the bar's layer, ordered under it (HyprlandManager's
  // layer rules), when it slides under at all (EdgePlacement.slidesUnder:
  // not while the overlay is open on its screen, _overOverlay, nor over a
  // fullscreen window, nor without supports.layerOrder). Anything else it
  // opens over, sliding out within its own window.
  readonly property real slideDistance: placement.slidesUnder ? Math.max(0, root.attachAt - root.barOuter - (root.barConfig?.insideBorder ? Appearance.borderWidth : 0)) : 0
  readonly property bool slidesUnder: root.slideDistance > 0
  // Its window's layer: Overlay unless it slides under a bar
  readonly property int windowLayer: root.slidesUnder ? WlrLayer.Top : WlrLayer.Overlay
  // Over the overlay and fullscreen windows (BlurManager.backsOn), it and
  // a submenu in its window
  readonly property bool onOverlayLayer: root.windowLayer === WlrLayer.Overlay
  property color fillColor: Theme.background
  property color strokeColor: Theme.foreground
  // Off leaves the focus grab to another window (see SurfaceGroup)
  property bool grabEnabled: true
  // Other windows the grab lets input through to
  property var grabWindows: []
  // Its layer namespace unless it slides under (layer rules stack by it)
  property string overNamespace: "axiom-edge-popout"
  // The surface's window, its layer namespace, and the box within it
  window: surfaceWindow
  // The hover strip's window (a focus grab's partner, see EdgeMenuSync)
  readonly property var triggerWindow: trigger
  readonly property string layerNamespace: root.slidesUnder ? "axiom-popout-under" : root.overNamespace
  readonly property rect boxInWindow: Qt.rect(boxArea.x, boxArea.y, boxArea.width, boxArea.height)

  // Its place among the popouts (PopoutManager), under `claimKey` (none:
  // it takes no part): it shows once granted, closes when a higher popout
  // covers it, and a `resident` one hides while covered and comes back
  property string claimKey: ""
  property string claimKind: "osd"
  property bool pinned: false
  property bool resident: false
  // Granted (or closing after it was, PopoutClaim.held)
  readonly property bool claimed: root.claimKey === "" || root.claim.held
  // In use: the pointer on it, its hover strip or what opened it, or just
  // opened or asked for again (engage()) and not let go since. A pinned
  // one ranks as its kind meanwhile, so it opens (or comes forward) over
  // what it would give way to as pinned, and drops to pinned once let go
  readonly property bool engaged: surfaceHover.hovered || trigger.containsMouse || root.anchorHovered || root._grace
  property bool _grace: false
  function engage() {
    root._grace = true;
    graceTimer.restart();
  }
  // Long enough for the pointer to reach it; leaving it ends it at once
  property Timer graceTimer: Timer {
    interval: Math.max(root.dismissDelay, 2500)
    onTriggered: root._grace = false
  }
  readonly property bool _pointerIn: surfaceHover.hovered
  on_PointerInChanged: {
    if (!root._pointerIn)
      root._grace = false;
  }
  onIsOpenChanged: {
    if (root.isOpen)
      root.engage();
  }
  readonly property bool yielded: root.claim.yielded
  property PopoutClaim claim: PopoutClaim {
    key: root.claimKey
    kind: root.claimKind
    screen: root.screen?.name ?? ""
    edge: ScreenEdge.name(root.edge)
    pinned: root.pinned && !root.engaged
    resident: root.resident
    occupied: root.occupied
    closing: root.isClosing
    // Once Hyprland has said where its window is (or a moment has passed,
    // LayerOrigin.settled): the estimate before that can be far off, so a
    // claim made from it can miss what it covers
    wanted: root.claimKey !== "" && root.isOpen && root.contentItem !== null && placeOnScreen.settled
    // Where its window is, else where it most likely is (LayerOrigin.placed)
    footprint: PopoutGeometry.offset(surface.footprint, Qt.point(placeOnScreen.placed.x + surface.x, placeOnScreen.placed.y + surface.y))
    onEvicted: root.hide()
    onRefused: root.hide()
  }

  readonly property bool vertical: placement.vertical
  readonly property bool bareEdge: placement.bareEdge

  // Held off the edge (an edge menu's or OSD's `detached`): a detached box
  // `gap` in from the frame lines on its edge and at its ends
  // (ScreenEdgeManager.detachedGaps), so it lines up with a floating bar's islands, or
  // with the windows. Its gaps are what places it, so a change of `held`
  // never reads them before they follow.
  property bool held: false
  property int gap: -1
  // Over a fullscreen window, which covers the border and the bars, there's
  // nothing to join: it's held as well, with an automatic gap unless held
  // already (and slides under nothing, whose layer that window hides).
  // Followed only while closed, so an open box never moves.
  readonly property bool fullscreen: CompositorManager.hasFullscreen(root.screen?.name ?? "")
  property ClosedLatch _fullscreenLatch: ClosedLatch {
    source: root.fullscreen
    closed: !root.occupied
  }
  readonly property bool _overFullscreen: root._fullscreenLatch.value ?? false
  // Held, by `held` or over a fullscreen window
  readonly property bool holds: root.held || root._overFullscreen
  readonly property var gaps: placement.gaps

  // The perpendicular edges at its start and end (ScreenEdges)
  readonly property int startSide: placement.startSide
  readonly property int endSide: placement.endSide

  // A bar other than a solid one on this edge, while it shows, and its
  // outer edge across it (EdgePlacement)
  readonly property var barConfig: placement.barConfig
  readonly property real barOuter: placement.barOuter
  // Where the window's attach edge goes by default: on the stroke of what
  // reserves the edge (the border, a bar, integrated menus; not docks,
  // which it reaches past), none on a bare edge
  readonly property real attachBase: ScreenEdgeManager.reservedWithMenusOn(root.screen, root.edge) - (root.bareEdge ? 0 : Appearance.borderWidth)
  // Where it goes: held, a connector gap short of where its box goes;
  // following a bar, as that meets it; else on what reserves the edge
  // (EdgePlacement.attachAt)
  readonly property real attachAt: placement.attachAt

  // While the overlay is open on its screen a box that would slide under
  // a bar draws over the overlay instead (render.LayerRulesLua),
  // since the layer it slides out from under is one the overlay covers
  // (as BarPopouts.underBar). Followed only while closed: the namespace
  // changes with it.
  readonly property bool overlayOpen: SurfaceManager.surfaceOpenOn("overlay", root.screen)
  property ClosedLatch _overlayLatch: ClosedLatch {
    source: root.overlayOpen
    closed: !root.occupied
  }
  readonly property bool _overOverlay: root._overlayLatch.value ?? false

  // Extra box depth at the attach edge that a merged box's content keeps
  // clear of the pills by
  readonly property real attachClearance: placement.attachClearance
  // What the content moves in by at the attach edge, past the box's
  // stroke and padding: the clearance, less the plain fill it joins there
  // (EdgePlacement.attachFill: the border's margin, a floating or pill
  // bar's empty depth), taken off the padding (never the stroke), so the
  // content is as far from the screen edge as from the box's other sides
  readonly property real attachExtra: root.attachClearance - Math.min(placement.attachFill, Math.max(0, root.contentPadding - Appearance.borderWidth))

  // Unless held (or detached, or on an island), it joins the
  // perpendicular edges when the box reaches them, as a bar popout pushed
  // to an end does: flush on that edge's stroke (or a pill bar's far side,
  // PillBarJoin), merging into it (EdgePlacement.startEnd/endEnd,
  // SurfaceContext). Both ends joined stretch the box along the whole edge.
  // The content's length along the edge, ignoring the cap (maxBoxLength),
  // which the joins are decided from: they raise the cap, so deciding from
  // the capped length would feed back into itself. Infinity for content
  // that grows to fill whatever room it's given.
  property real reachLength: root.contentItem ? (root.vertical ? root.contentItem.implicitHeight : root.contentItem.implicitWidth) : 0

  // A joining window reaches onto the perpendicular strokes (the border's,
  // a solid bar's, a pill bar's far side), so a joined end can sit on the
  // stroke's outer edge (EdgePlacement)
  readonly property real startStrokeInset: placement.strokeInsetStart
  readonly property real endStrokeInset: placement.strokeInsetEnd
  // Length of the edge between the perpendicular edges' inner sides
  readonly property real edgeLength: placement.innerEnd - placement.innerStart
  // The least room the box keeps from each end that isn't joined: held,
  // its gaps from the frame lines there; at a wall (another bar, a menu's
  // strip), up to where windows start; else its fillet's past the corner
  // (EdgePlacement.insetStart/insetEnd, in this window's edge coordinates)
  readonly property real startInset: placement.insetStart
  readonly property real endInset: placement.insetEnd
  // Where edge coordinates start in the window
  readonly property real _windowStart: root.startStrokeInset

  // The natural box centred at `position`: an end joins when the box would
  // be pushed back from that edge, or leave less than a connector gap
  // between its fillet and it (EdgePlacement.joinStart/joinEnd)
  readonly property real naturalBox: reachLength + contentPadding * 2
  readonly property bool joinStart: placement.joinStart
  readonly property bool joinEnd: placement.joinEnd

  // Largest content box that fits along the edge: from stroke to stroke
  // when both ends join, else keeping its inset from each end that
  // doesn't, as the clamp in place does; on a floating bar's island, no
  // further than islands reach (the box starts where they do)
  readonly property real maxBoxLength: {
    const start = root.joinStart ? placement.joinFrom : placement.lo;
    const end = root.joinEnd ? placement.joinTo : placement.hi;
    if (placement.atIsland)
      return Math.min(end, placement.islandTo) - Math.max(start, placement.islandFrom);
    return end - start;
  }

  // The box along the edge, in edge coordinates (0 at the perpendicular
  // edges' inner side): flush on a joined end, else centred at `position`
  // and clamped to its insets (startInset/endInset), so its fillets stay
  // on the edge; on a bar's pills or islands, as a bar popout's
  // (EdgePlacement). Both ends joined, it runs the whole edge, the content
  // centred.
  readonly property real _contentAlong: Math.ceil((vertical ? root.contentItem?.implicitHeight ?? 100 : root.contentItem?.implicitWidth ?? 100) + contentPadding * 2)
  // ...and across it, on whole pixels too: a far side between two pixels
  // drew its stroke faint, or dotted with a thin one
  readonly property real _contentAcross: Math.ceil((vertical ? root.contentItem?.implicitWidth ?? 100 : root.contentItem?.implicitHeight ?? 100) + contentPadding * 2)
  EdgePlacement {
    id: placement
    screen: root.screen
    edge: root.edge
    held: root.holds
    gap: root.held ? root.gap : -1
    centre: root.edgeLength * root.position + root.positionOffset
    probeStart: placement.centre - root.naturalBox / 2
    probeLength: root.naturalBox
    // Along a side edge the box reaches past its content's ends for a
    // submenu (shownStretchTop/Bottom)
    aligned: placement.centre - root._contentAlong / 2 - root._stretchAlongTop
    contentLength: root._contentAlong + root._stretchAlongTop + root._stretchAlongBottom
    submenu: slot
    coverStart: surface.coverStart
    coverLength: surface.coverLength
    owner: "edgePopout:" + root
    showing: root.occupied && root.contentItem !== null && root.claimed
    open: root.isOpen && root.claimed
    onOverlayLayer: root.onOverlayLayer
    overOverlay: root._overOverlay
    origin: placeOnScreen.origin
    attachedSurface: surface
    opens: surfaceWindow.visible && root.claimed
  }
  readonly property var place: placement.place
  readonly property real boxLength: root.place.end - root.place.start
  // The surface (fillets included) along the edge
  readonly property real surfaceStart: root.place.surfaceStart

  currentItem: root.contentItem

  // Set a tick after the box first shows, so it opens at its size and
  // shape and only animates after (as a bar popout's, SwitchStill.settled)
  readonly property bool _shown: surfaceWindow.visible && root.isOpen
  property bool settled: false
  on_ShownChanged: {
    if (!root._shown)
      root.settled = false;
    else
      Qt.callLater(() => root.settled = root._shown);
  }

  // ---- Its submenu (SubPopout, through its SubmenuHost) ----
  // Opened by a PopoutAnchor in its content (an edge menu's modules), on
  // the side of its box: away from a side edge, else towards the screen's
  // nearer half. On a top or bottom edge one with no room for its fillet
  // at the box's edge side joins the stroke the box grows from (the
  // border's, a solid bar's, a pill's or island's, stretched to its wall
  // where its fillet won't land on it), and one longer than the side
  // stretches the box: away from its edge, or along a side edge past the
  // box's ends.
  submenuHost: slot
  SubmenuHost {
    id: slot
    wrapper: root
    screen: root.screen
    popupSurface: surface
    boxRect: root.boxInWindow
    popupScreenOrigin: placeOnScreen.origin
    popupScreenPlaced: placeOnScreen.placed
    animate: root.settled
    geometry: placement
    windowShift: root._windowStart
  }
  // Along a side edge the box reaches past its content's ends for a
  // submenu (across a top or bottom one, away from its edge)
  readonly property real _stretchAlongTop: root.vertical ? slot.shownStretchTop : 0
  readonly property real _stretchAlongBottom: root.vertical ? slot.shownStretchBottom : 0
  // ---- end submenu ----
  keepAlive: surfaceHover.hovered || trigger.containsMouse || (focusGrab.active && wantsKeyboardFocus)

  EdgeTrigger {
    id: trigger
    screen: root.screen
    visible: root.triggerEnabled
    edge: root.edge
    position: root.position
    positionOffset: root.positionOffset
    centre: root.triggerCentre
    triggerWidth: root.triggerWidth
    triggerLength: root.triggerLength
    hoverDelay: root.hoverDelay
    onTriggered: {
      root.engage();
      root.show();
    }
  }

  PanelWindow {
    id: surfaceWindow
    screen: root.screen
    visible: root.occupied && loader.status === Loader.Ready
    color: "transparent"

    // Overlay so the connector draws over the border/bar stroke it joins.
    // Normal exclusion with no zone of its own places the window inside
    // the border's and bars' reserved area; the -borderWidth margin then
    // lines it up with their inner stroke, whether that's a bar or the
    // plain border.
    // Sliding under something, on its layer, ordered under it (see
    // HyprlandManager's layer rules)
    WlrLayershell.layer: root.windowLayer
    WlrLayershell.namespace: root.layerNamespace
    WlrLayershell.keyboardFocus: root.wantsKeyboardFocus || root.keyboardOnDemand ? (focusGrab.exclusive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand) : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0

    // What PopoutAnchors in its content open in
    readonly property var popoutHost: root.submenu
    // Its content doesn't grow the box (a menu's cards are fixed): a
    // StyledComboEntry opens its list inline, in what scrolls around it
    // (BarPopouts' room is a number)
    readonly property var popoutRoom: null

    // Spans the whole edge; the input mask limits it to the surface.
    anchors {
      top: root.edge === ScreenEdge.Top || root.vertical
      bottom: root.edge === ScreenEdge.Bottom || root.vertical
      left: root.edge === ScreenEdge.Left || !root.vertical
      right: root.edge === ScreenEdge.Right || !root.vertical
    }

    // On a bare screen edge (no border, no bar) there's no stroke to land
    // on: the surface sits at the edge and runs straight off it
    // Docks reserving space inside the border don't push it in: it reaches
    // past them, on its own edge and at both ends
    readonly property string screenName: root.screen?.name ?? ""
    readonly property real attachMargin: (root.bareEdge ? 0 : -Appearance.borderWidth) - surface.backfill + root.edgeOffset - (root.slidesUnder ? root.slideDistance : 0) - DockManager.zoneOn(screenName, ScreenEdge.name(root.edge))
    margins {
      top: root.edge === ScreenEdge.Top ? surfaceWindow.attachMargin : root.vertical ? -root.startStrokeInset - DockManager.zoneOn(surfaceWindow.screenName, "top") : 0
      bottom: root.edge === ScreenEdge.Bottom ? surfaceWindow.attachMargin : root.vertical ? -root.endStrokeInset - DockManager.zoneOn(surfaceWindow.screenName, "bottom") : 0
      left: root.edge === ScreenEdge.Left ? surfaceWindow.attachMargin : root.vertical ? 0 : -root.startStrokeInset - DockManager.zoneOn(surfaceWindow.screenName, "left")
      right: root.edge === ScreenEdge.Right ? surfaceWindow.attachMargin : root.vertical ? 0 : -root.endStrokeInset - DockManager.zoneOn(surfaceWindow.screenName, "right")
    }

    // The surface, or room for it at the content's largest
    readonly property real depth: {
      const content = root.vertical ? (root.contentItem?.implicitWidth ?? 0) : (root.contentItem?.implicitHeight ?? 0);
      // (a submenu's stretch as it will be, not as it animates there)
      const surfaceDepth = (root.vertical ? surface.implicitWidth : surface.implicitHeight) - slot.shownStretchAcross + slot.stretchAcross;
      // and room for the shadow it casts (SurfaceShadow)
      const own = surfaceDepth + Math.max(0, root.maxContentDepth - content) + surface.shadowReach;
      if (!root.roomForSubmenus || root.vertical)
        return own;
      // From this window's edge (its attach edge, less its backfill and
      // the way it slides in from) to the far edge's reserved space
      const far = ScreenEdgeManager.reservedWithMenusOn(root.screen, root.edge === ScreenEdge.Top ? ScreenEdge.Bottom : ScreenEdge.Top);
      return Math.max(own, (root.screen?.height ?? 0) - far - root.attachAt + surface.backfill + (root.slidesUnder ? root.slideDistance : 0));
    }
    implicitWidth: root.vertical ? surfaceWindow.depth : 0
    implicitHeight: root.vertical ? 0 : surfaceWindow.depth

    // One sliding under a bar takes input on its box alone; none until
    // it's granted its place, or while it's given it up
    mask: Region {
      item: !root.claimed ? null : root.slidesUnder ? boxArea : surface
    }

    Item {
      id: boxArea
      x: surface.x + surface.boxRect.x
      y: surface.y + surface.boxRect.y
      width: surface.boxRect.width
      height: surface.boxRect.height
    }

    FocusGrab {
      id: focusGrab
      windows: [surfaceWindow].concat(root.grabWindows, SurfaceManager.modalWindows)
      active: surfaceWindow.visible && root.grabEnabled && (root.wantsKeyboardFocus || root.closeOnClickOutside)

      onActiveChanged: {
        if (active)
          root.contentItem?.forceActiveFocus();
      }

      onCleared: {
        if (!active)
          root.hide();
      }
    }

    // Where the window is on screen: the blur window draws the surface's
    // fill (BlurManager) from there
    LayerOrigin {
      id: placeOnScreen
      window: surfaceWindow
      namespace: root.layerNamespace
      edge: root.edge
      layer: root.windowLayer
    }

    EdgeSurface {
      id: surface

      geometry: placement
      submenu: slot
      screenName: surfaceWindow.screenName
      windowShown: surfaceWindow.visible
      animateShape: root.settled

      // At the attach edge of a window that may be deeper than it
      x: root.vertical ? (root.edge === ScreenEdge.Right ? surfaceWindow.width - width : 0) : root._windowStart + root.surfaceStart
      y: root.vertical ? root._windowStart + root.surfaceStart : (root.edge === ScreenEdge.Bottom ? surfaceWindow.height - height : 0)
      width: implicitWidth
      height: implicitHeight

      detachedOffset: root.slidesUnder ? root.slideDistance : 0
      // Once its pill has grown out to carry it
      // While the blur window backs surfaces, once it knows where this one
      // is (LayerOrigin.settled), so it never shows unbacked beside them
      active: root.isOpen && root.claimed && placement.stretchReady && (!BlurManager.backingOn(root.screen) || placeOnScreen.settled)
      boxWidth: root.vertical ? root._contentAcross + root.attachExtra : root.boxLength
      boxHeight: root.vertical ? root.boxLength : root._contentAcross + root.attachExtra + slot.shownStretchAcross
      fillColor: root.fillColor
      strokeColor: root.strokeColor

      HoverHandler {
        id: surfaceHover
      }

      Loader {
        id: loader
        // Across the edge it fills the box; along it, it keeps its own
        // length, where it wants to be (EdgeAttach.place's contentOffset:
        // the box can grow past it, to a joined stroke or an island's end).
        // Plain geometry, not anchors switched by `vertical`: those
        // re-evaluate one at a time when the edge changes, and QML drops
        // the anchor that briefly conflicts (top + bottom + verticalCenter)
        // for good.
        readonly property real leftMargin: root.contentPadding + (root.edge === ScreenEdge.Left ? root.attachExtra : 0)
        readonly property real rightMargin: root.contentPadding + (root.edge === ScreenEdge.Right ? root.attachExtra : 0)
        readonly property real topMargin: root.contentPadding + (root.edge === ScreenEdge.Top ? root.attachExtra : 0)
        readonly property real bottomMargin: root.contentPadding + (root.edge === ScreenEdge.Bottom ? root.attachExtra : 0)
        // (below a submenu's stretch above it, clear of one below)
        x: root.vertical ? leftMargin : root.contentPadding + root.place.contentOffset
        y: root.vertical ? root.contentPadding + root.place.contentOffset + slot.shownStretchTop : topMargin + slot.shownStretchTop
        width: root.vertical ? parent.width - leftMargin - rightMargin : (root.contentItem?.implicitWidth ?? 0)
        height: root.vertical ? (root.contentItem?.implicitHeight ?? 0) : parent.height - topMargin - bottomMargin - slot.shownStretchAcross

        active: root.occupied || root.keepLoaded
        asynchronous: false
        sourceComponent: root.content

        onLoaded: root.updateDismissTimer()
      }
    }
  }
}
