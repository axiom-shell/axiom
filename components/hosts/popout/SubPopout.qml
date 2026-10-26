pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.reusable

/**
 * A popout's submenu, one level deep: each popout host has one
 * (BarPopouts.submenu, EdgePopout.submenu), which a PopoutAnchor in its
 * content opens by itself (its window's `popoutHost`), loading
 * content/<name>.qml as a bar popout does (the tray's submenus:
 * "parts/TraySubmenu"). A PopoutAnchor inside a submenu opens its content
 * in this same one, in place: there's no second level.
 * Attaches to the side of the parent popout's box (right, or left when
 * openToLeft) with the same AttachedSurface shape as bar/edge popouts,
 * level with the item that opened it and slid out of the parent. Another
 * submenu of the same popout switches in place (SwitchStill).
 * Along the parent's side it's placed as a bar popout is along a pill
 * (SurfaceContext.submenuPlace): a side whose fillet has no room before an
 * end of the parent's side runs flush to it where that end is free (the parent
 * squaring its corner there), or joins the stroke the parent grows from
 * at its bar side (a solid bar's, a pill's, the border's), as a popout
 * joins the perpendicular border; a submenu longer than the side
 * stretches the parent (parentStretch, which the parent's BarPopouts
 * draws, a joined submenu's outer fillet on its pill included).
 * It's the parent's in PopoutManager (kind "submenu", ranked as its
 * parent), closes with it, and closing with the pointer off the parent
 * (it left, or an entry was picked) takes the parent with it at once.
 * Open/close/queue state and dismiss timing come from PopoutWrapperBase —
 * this file only adds submenu-specific positioning and animation.
 */
Item {
  id: outer

  required property ShellScreen screen
  required property bool openToLeft
  // The parent popout (BarPopouts, EdgePopout): its claim, open state and
  // dismissal
  required property var host
  // Its SubmenuHost: what we meet on its side (`side`, a SubmenuSide: the
  // ends we may run flush to or join at its bar side, and where that
  // stroke lies), its box at rest (attachBox), where its window is on
  // screen (popupScreenOrigin); it draws parentStretch and the holes we
  // leave in its strokes and shadow (submenuHole, submenuBox,
  // submenuJoinSpan)
  required property var slot

  // What the parent draws for us while we show: how far its box reaches
  // past its top and bottom, whether it squares its corner there, and,
  // joined to its bar side, where along the bar (x in its window) our
  // outer wall rests: the parent's placement decides from it how we meet
  // the stroke there (SurfaceContext.submenuJoin, the slot's `join`)
  readonly property var parentStretch: {
    if (!root.occupied || !(root.contentReady || still.switching))
      return null;
    const stretch = root.place.stretch;
    const joined = root.place.joinStart || root.place.joinEnd;
    return {
      "top": stretch ? Math.max(0, root.attachRect.y - stretch.start) : 0,
      "bottom": stretch ? Math.max(0, stretch.end - root.attachEnd) : 0,
      "squareTop": stretch?.squareStart ?? false,
      "squareBottom": stretch?.squareEnd ?? false,
      "joined": joined,
      "wall": joined ? root.outerWall : null
    };
  }

  PopoutWrapperBase {
    id: root
    anchors.fill: parent

    property int connectorGap: Appearance.connectorGap

    currentItem: loader.item ?? null
    // Loaded, with its entries in (they arrive over DBus, TrayMenuList)
    readonly property bool contentReady: loader.status === Loader.Ready && (root.currentItem?.contentReady ?? true)

    // Another submenu of the same menu (a sibling item's, or one drilled
    // into) switches in place: the box glides level with its item and
    // resizes, the old entries fading out over the new (SwitchStill)
    canSwitchTo: (anchor, data) => anchor === root.currentAnchor && (root.contentReady || still.switching)
    prepareSwitch: done => still.prepare(root.currentItem, done)

    // Every payload builds afresh (content/<name>.qml, given the wrapper
    // and the payload's fields), so a switch waits for its own entries
    onCurrentDataChanged: root._load()
    function _load() {
      const data = root.currentData;
      const name = data?.name ?? "";
      if (!loader.active || name === "") {
        loader.source = "";
        return;
      }
      // Where its anchor is from the parent's box top, level with which
      // its content starts (unless the payload says): within the box, so
      // one opened while the parent still slides out lands where it rests
      const item = data.anchorItem;
      let offset = data.anchorOffset;
      if (offset === undefined && item) {
        try {
          offset = outer.slot?.anchorOffsetOf ? outer.slot.anchorOffsetOf(item) : item.mapToItem(null, 0, 0).y - root.attachRect.y;
        } catch (e) {}
      }
      root._anchorOffset = offset ?? 0;
      const props = {
        "wrapper": root
      };
      for (const key in data)
        if (key !== "name" && !key.startsWith("anchor"))
          props[key] = data[key];
      loader.source = "";
      loader.setSource(Paths.contentUrl(name), props);
    }
    property real _anchorOffset: 0

    // The parent popout's content box at rest, in the anchor window's
    // coordinates, read live (the parent's window may move as it grows).
    // Its free sides are the outer edge of the parent's stroke
    // (AttachedSurface.boxRect).
    readonly property rect attachRect: outer.slot?.attachBox ?? Qt.rect(0, 0, 0, 0)
    readonly property real attachEnd: root.attachRect.y + root.attachRect.height

    readonly property real boxLength: submenuPopup.contentHeight + surface.contentInset * 2
    // The screen's room up and down (y in the parent's window): inside
    // what's reserved at its top and bottom. A box longer than the side
    // stays within it, and content (MenuSubmenu) scrolls past
    // maxContentHeight
    readonly property real _placedY: outer.slot?.popupScreenPlaced?.y ?? 0
    readonly property real screenFrom: ScreenEdgeManager.reservedWithMenusOn(outer.screen, ScreenEdge.Top) - root._placedY
    readonly property real screenTo: (outer.screen?.height ?? 0) - ScreenEdgeManager.reservedWithMenusOn(outer.screen, ScreenEdge.Bottom) - root._placedY
    readonly property real maxContentHeight: Math.max(Widget.height, root.screenTo - root.screenFrom - surface.contentInset * 2)
    // Along the parent's side (y in its window), placed as a bar popout is
    // along a pill (SurfaceContext.submenuPlace)
    readonly property var place: SurfaceContext.submenuPlace({
      "attach": {
        "start": root.attachRect.y,
        "length": root.attachRect.height
      },
      "wanted": root.attachRect.y + root._anchorOffset - surface.contentInset,
      "length": root.boxLength,
      "joinTop": outer.slot?.side?.joinTop ?? false,
      "joinBottom": outer.slot?.side?.joinBottom ?? false,
      "joinLine": outer.slot?.side?.attachLine ?? 0,
      "freeTop": outer.slot?.side?.freeTop ?? false,
      "freeBottom": outer.slot?.side?.freeBottom ?? false,
      "growsUp": outer.slot?.side?.growsUp ?? false,
      "screenFrom": root.screenFrom,
      "screenTo": root.screenTo,
      "gap": root.connectorGap,
      "stroke": Appearance.borderWidth,
      "radius": Appearance.borderRadius
    })

    // The box at its content's size (grown to a flush end) and placed, and
    // as drawn: animated to them once it shows (not on opening), and held
    // as it was while a switch waits for its entries
    readonly property real targetBoxWidth: submenuPopup.contentWidth + surface.contentInset * 2
    // The box's outer wall (outer edge of its stroke), x in the parent's
    // window: our attach edge lies a stroke inside the parent's side
    readonly property real outerWall: outer.openToLeft ? root.attachRect.x + Appearance.borderWidth - surface.boxStart - root.targetBoxWidth : root.attachRect.x + root.attachRect.width - Appearance.borderWidth + surface.boxStart + root.targetBoxWidth
    // Joined, whether our outer fillet curves into the stroke we join (a
    // pill or island running on past it, carried on past the fillet
    // where one shows past our wall at all); else our wall runs straight
    // up into it, stretched to meet it (SurfaceContext.submenuJoin)
    readonly property bool joinFillets: outer.slot?.join?.fillet ?? false
    readonly property real targetBoxHeight: root.place.end - root.place.start
    property real shownBoxWidth: still.holding ? still.held.width : root.targetBoxWidth
    property real shownBoxHeight: still.holding ? still.held.height : root.targetBoxHeight
    property real shownBoxStart: still.holding ? still.held.start : root.place.start
    property bool _settled: false
    function _updateSettled() {
      if (!root.occupied || !(root.contentReady || still.switching))
        root._settled = false;
      else
        Qt.callLater(() => root._settled = root.occupied && (root.contentReady || still.switching));
    }
    Glide on shownBoxWidth {
      enabled: root._settled
    }
    Glide on shownBoxHeight {
      enabled: root._settled
    }
    Glide on shownBoxStart {
      enabled: root._settled
    }

    // The widest surface since it opened, and the furthest it reached past
    // either end of the parent's side, which the window keeps room for
    property real _peakWidth: 0
    property real _peakFrom: 0
    property real _peakTo: 0
    function _notePeak() {
      if (!root.occupied || !root.contentReady)
        return;
      root._peakWidth = Math.max(root._peakWidth, submenuPopup.surfaceWidth);
      root._peakFrom = Math.min(root._peakFrom, submenuPopup.surfaceFrom);
      root._peakTo = Math.max(root._peakTo, submenuPopup.surfaceTo);
    }
    onContentReadyChanged: {
      _notePeak();
      _updateSettled();
    }
    onOccupiedChanged: {
      if (!root.occupied) {
        root._cascade();
        root._peakWidth = 0;
        root._peakFrom = 0;
        root._peakTo = 0;
        still.end();
      }
      _updateSettled();
    }

    PopupWindow {
      id: submenuPopup
      // What PopoutAnchors in its content open in: this one again
      readonly property var popoutHost: outer

      visible: root.occupied && (root.contentReady || still.switching) && !SurfaceManager.captureFrozen
      color: "transparent"

      // TrayMenuList sizes itself to its entries, within its limits
      readonly property int contentWidth: root.currentItem?.implicitWidth ?? 0
      readonly property int contentHeight: root.currentItem?.implicitHeight ?? 0
      // The surface at the target box size and place (it's drawn at the
      // shown one), along the side from the parent's box top
      readonly property real surfaceWidth: surface.implicitWidth - root.shownBoxWidth + root.targetBoxWidth
      readonly property real surfaceFrom: root.place.surfaceStart - root.attachRect.y
      readonly property real surfaceTo: surfaceFrom + root.place.surfaceLength
      onSurfaceWidthChanged: root._notePeak()
      onSurfaceFromChanged: root._notePeak()
      onSurfaceToChanged: root._notePeak()

      // Room for the shadow the surface casts (SurfaceShadow) on
      // its free sides: away from the parent, above and below
      readonly property real shadowRoom: surface.shadowReach
      // None past the bar side we may join, so it doesn't fall over the
      // bar (as the parent's slide clips its own there)
      // (but the parent's backfill row, which a joined surface covers)
      readonly property real joinBackfill: outer.slot?.side?.backfill ?? 0
      readonly property real roomTop: outer.slot?.side?.joinTop ? joinBackfill : shadowRoom
      readonly property real roomBottom: outer.slot?.side?.joinBottom ? joinBackfill : shadowRoom

      // Resizing or moving a popup while it shows is a round trip to the
      // compositor, so the window doesn't follow the surface: it spans
      // everywhere a submenu of this menu can sit (the parent's side, and
      // as far past it as any surface since it opened), as wide as the
      // widest, and the surface glides and resizes within it
      readonly property real windowFrom: Math.min(root._peakFrom, surfaceFrom)
      readonly property real windowTo: Math.max(root.attachRect.height, root._peakTo, surfaceTo)
      implicitWidth: Math.max(root._peakWidth, surfaceWidth) + shadowRoom
      implicitHeight: windowTo - windowFrom + roomTop + roomBottom

      // Overlap the parent's side stroke with our attach-edge stroke, the
      // same way bar/edge popouts overlap the bar or border stroke
      // (backfill grows the window towards the parent, past the attach edge)
      readonly property real attachX: outer.openToLeft ? root.attachRect.x + Appearance.borderWidth + surface.backfill - implicitWidth : root.attachRect.x + root.attachRect.width - Appearance.borderWidth - surface.backfill

      anchor {
        window: root.currentAnchor
        // Placed here, so the compositor mustn't move it: its window
        // reaches past the parent's for room, and pushed back onto the
        // screen it would leave its blur and the parent's opening behind
        adjustment: PopupAdjustment.None
        rect {
          x: submenuPopup.attachX
          y: root.attachRect.y + submenuPopup.windowFrom - submenuPopup.roomTop
          width: 1
          height: 1
        }
      }

      // Only the surface takes input
      mask: Region {
        item: surface
      }

      AttachedSurface {
        id: surface
        x: outer.openToLeft ? submenuPopup.width - width : 0
        y: root.shownBoxStart - surface.startMargin - root.attachRect.y - submenuPopup.windowFrom + submenuPopup.roomTop
        width: implicitWidth
        height: implicitHeight

        edge: outer.openToLeft ? ScreenEdge.Right : ScreenEdge.Left
        castShadow: true
        // The blur window draws its fill (BlurManager), from
        // where the parent's window is on screen
        readonly property var parentOrigin: outer.slot?.popupScreenOrigin ?? null
        // Where it sits in the parent's window
        readonly property real inParentX: submenuPopup.attachX + surface.x
        readonly property real inParentY: root.attachRect.y + submenuPopup.windowFrom - submenuPopup.roomTop + surface.y
        // In its parent's window, on its layer
        readonly property bool onOverlayLayer: outer.host?.onOverlayLayer ?? true
        backed: BlurManager.backsOn(outer.screen, surface.onOverlayLayer) && surface.parentOrigin !== null
        opaque: BlurManager.opaqueOn(outer.screen)
        // Cast as its parent casts its own (SurfaceContext.shadow): one
        // shadow round the two
        readonly property var _parentSurface: outer.slot?.popupSurface ?? null
        shadowLook: surface._parentSurface?.shadowLook ?? BarStyle.look

        BlurShape {
          source: surface
          screen: outer.screen?.name ?? ""
          x: (surface.parentOrigin?.x ?? 0) + surface.inParentX
          y: (surface.parentOrigin?.y ?? 0) + surface.inParentY
          shown: surface.backed && submenuPopup.visible
          overlayLayer: surface.onOverlayLayer
        }

        // The parent's side stroke it covers, left open, with its
        // anti-aliased fringe a pixel either side
        readonly property var parentHole: Appearance.translucent && submenuPopup.visible ? Qt.rect(outer.openToLeft ? root.attachRect.x - 1 : root.attachRect.x + root.attachRect.width - Appearance.borderWidth - 1, surface.inParentY + surface.coverStart, Appearance.borderWidth + 2, surface.coverLength) : null
        onParentHoleChanged: {
          if (outer.slot)
            outer.slot.submenuHole = surface.parentHole;
        }
        // Joined to the parent's bar side, the stretch of the stroke it
        // joins that its end covers there (x in the parent's window): its
        // fill runs along it to the join's fillet (joinCover), from the
        // parent's side stroke
        readonly property var joinSpan: Appearance.translucent && submenuPopup.visible && (surface.joinStart || surface.joinEnd) ? (outer.openToLeft ? {
            "start": surface.inParentX + surface.width - surface.joinCover,
            "end": surface.inParentX + surface.width
          } : {
            "start": surface.inParentX,
            "end": surface.inParentX + surface.joinCover
          }) : null
        onJoinSpanChanged: {
          if (outer.slot)
            outer.slot.submenuJoinSpan = surface.joinSpan;
        }
        // Its box in the parent's window, which the parent's own shadow
        // leaves out (AttachedSurface.shadowHoles)
        readonly property var parentBox: submenuPopup.visible ? Qt.rect(surface.inParentX + surface.boxRect.x, surface.inParentY + surface.boxRect.y, surface.boxRect.width, surface.boxRect.height) : null
        onParentBoxChanged: {
          if (outer.slot)
            outer.slot.submenuBox = surface.parentBox;
        }
        // Its own hole, if still shown (rects compare by value, not ===)
        Component.onDestruction: {
          const box = outer.slot?.submenuBox;
          if (box && surface.parentBox && box.x === surface.parentBox.x && box.y === surface.parentBox.y)
            outer.slot.submenuBox = null;
          const hole = outer.slot?.submenuHole;
          if (hole && surface.parentHole && hole.x === surface.parentHole.x && hole.y === surface.parentHole.y)
            outer.slot.submenuHole = null;
          const span = outer.slot?.submenuJoinSpan;
          if (span && surface.joinSpan && span.start === surface.joinSpan.start)
            outer.slot.submenuJoinSpan = null;
        }
        // Once the parent's box has grown out for it (SubmenuHost.contextReady)
        active: root.occupied && !root.isClosing && (root.contentReady || still.switching) && (outer.slot?.contextReady ?? true)
        connectorGap: root.connectorGap
        boxWidth: root.shownBoxWidth
        boxHeight: root.shownBoxHeight
        // A side with no room for its fillet before a free end of the
        // parent's side runs straight on to it
        flushStart: root.place.flushStart
        flushEnd: root.place.flushEnd
        // At the parent's bar side, on the stroke it grows from
        joinStart: root.place.joinStart
        joinEnd: root.place.joinEnd
        straightJoins: (outer.slot?.side?.straight ?? false) || !root.joinFillets
        // The parent's side stroke leaves an anti-aliased fringe on its
        // inner side: cover it (see AttachedSurface.backfill)
        backfill: 1
        joinBackfill: submenuPopup.joinBackfill

        // The content keeps its target size while the box animates to it,
        // where it wants to be along the side (EdgeAttach.place's
        // contentStart), however far the box grows past it, and cut to the
        // box
        Item {
          id: clipBox
          anchors.fill: parent
          clip: true

          Loader {
            id: loader
            x: surface.contentInset
            y: surface.contentInset + root.place.contentStart - root.shownBoxStart
            width: submenuPopup.contentWidth
            height: submenuPopup.contentHeight
            opacity: still.contentOpacity
            active: root.occupied
            asynchronous: false

            onActiveChanged: root._load()
            onLoaded: root.updateDismissTimer()
          }

          // The entries switched away from, held where they were while
          // the box glides on
          SwitchStill {
            id: still
            contentReady: root.contentReady
            snapshot: () => ({
                  "start": root.shownBoxStart,
                  "width": root.shownBoxWidth,
                  "height": root.shownBoxHeight,
                  "along": root.place.contentStart
                })
            x: surface.contentInset
            y: surface.contentInset + (held?.along ?? 0) - root.shownBoxStart
          }
        }
      }
    }

    // Its place among the popouts (PopoutManager): its parent's, ranked
    // as it is, never colliding with it
    property PopoutClaim claim: PopoutClaim {
      key: (outer.host?.claim?.key ?? "") + "/submenu"
      kind: "submenu"
      parentKey: outer.host?.claim?.key ?? ""
      screen: outer.screen?.name ?? ""
      occupied: root.occupied
      closing: root.isClosing
      wanted: root.isOpen && submenuPopup.visible
      footprint: PopoutGeometry.offset(surface.footprint, Qt.point((outer.slot?.popupScreenPlaced?.x ?? 0) + surface.inParentX, (outer.slot?.popupScreenPlaced?.y ?? 0) + surface.inParentY))
      onEvicted: root.closePopout()
      onRefused: root.closePopout()
    }

    // Closes with its parent, when the parent gives way to a popout over
    // it (a resident's yield hides its box, not this), or when the parent
    // switches to other content
    readonly property bool _parentOpen: (outer.host?.isOpen ?? false) && (outer.host?.claimed ?? true)
    on_ParentOpenChanged: {
      if (!root._parentOpen && root.occupied)
        root.closePopout();
    }
    readonly property var _parentData: outer.host?.currentData ?? null
    on_ParentDataChanged: {
      if (root.occupied)
        root.closePopout();
    }
    // Gone with the pointer off the parent and what opened it, it takes the
    // parent with it at once, a cascade rather than the parent's own
    // dismiss delay after it
    function _cascade() {
      if (outer.host?.isOpen && (outer.host?.autoDismiss ?? true) && !(outer.host?.ownHovered ?? true))
        outer.host.requestDismiss();
    }
  }

  // The overlay's focus grab lets input through to the submenu (see
  // SurfaceManager.grabPartners)
  Component.onCompleted: SurfaceManager.registerGrabPartner(submenuPopup, outer.screen?.name)
  onScreenChanged: SurfaceManager.registerGrabPartner(submenuPopup, outer.screen?.name)
  Component.onDestruction: SurfaceManager.unregisterGrabPartner(submenuPopup)

  // How much of it is still behind its parent's side as it slides
  // (AttachedSurface.slid): the pill reach under a joined one follows it
  readonly property real hidden: surface.slid

  // What PopoutAnchor and the parent use of the inner PopoutWrapperBase;
  // the content is handed that one itself (`wrapper`)
  readonly property alias occupied: root.occupied
  readonly property alias isOpen: root.isOpen
  readonly property alias currentData: root.currentData
  readonly property alias hasPendingOpen: root.hasPendingOpen
  readonly property alias pendingOpenData: root.pendingOpenData
  // The submenu already open for the same item (the pointer back on it)
  // stays as it is rather than being rebuilt
  function safeOpenPopout(anchor, data) {
    if (root.isOpen && anchor === root.currentAnchor && data?.anchorItem === root.currentData?.anchorItem && data?.name === root.currentData?.name && data?.menuItem === root.currentData?.menuItem) {
      root.updateDismissTimer();
      return;
    }
    // From inside the submenu (a PopoutAnchor in its content): its content
    // replaced in place, where it is, as there's no second level
    if (anchor === submenuPopup) {
      root.safeOpenPopout(root.currentAnchor, Object.assign({}, data, {
        "anchorOffset": root._anchorOffset
      }));
      return;
    }
    root.safeOpenPopout(anchor, data);
  }
  function closePopout() {
    root.closePopout();
  }
}
