pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.core
import qs.services.compositor
import qs.services.ui
import qs.components.methods
import qs.components.hosts.popout
import qs.components.reusable

// One dock (a DockEntry) on one screen: a strip along its edge, inside the
// bars and border, holding a box of app icons. Its box meets the edge as an
// edge popout's does (EdgeAttach, see "Attaching to the edge"): held off
// it, growing out of the border's or a solid bar's stroke, or following
// another bar there as a bar popout would. The window is as deep as the
// magnified icons, and only the box (and icons grown out of it) take
// input. Always shown docks may reserve their strip; hover and
// intellihide docks slide in from the edge through an EdgeTrigger.
// As a `preview` (the settings card's Show, DockManager.preview) it's a
// copy over the overlay that only slides in and out: no trigger, zone,
// input or IPC.
// Everything along the dock is laid out here (`starts`, `sizes`), and each
// DockItem places itself from that.
Scope {
  id: root

  required property ShellScreen screen
  required property var dock
  // The settings card's Show (see the top)
  property bool preview: false

  readonly property int edge: Bar.getLocationFromString(root.dock.edge)
  readonly property bool vertical: root.edge === Bar.Left || root.edge === Bar.Right
  readonly property string mode: root.dock.visibility

  // --- Sizes ---
  readonly property real base: root.dock.iconSize
  readonly property real peak: root.dock.magnify.enabled ? Math.max(root.dock.magnify.size, root.base) : root.base
  readonly property real pad: root.dock.padding
  readonly property real spacing: root.dock.spacing
  readonly property real thickness: root.base + root.pad * 2

  // --- Attaching to the edge ---
  // As an edge popout does (EdgePlacement): held off the edge, a plain box
  // `gap` in from the frame lines on its edge and at its ends; else growing
  // out of the border's (or a solid bar's) stroke, or running straight off
  // a bare screen edge; with another bar on its edge, meeting it as a bar
  // popout would.
  readonly property string _edgeName: Bar.edgeName(root.edge)
  readonly property int connectorGap: placement.connectorGap
  // Held off the edge, and its gaps from the frame lines across its edge
  // and at its ends (what places it, so a change of `held` never reads
  // them before they follow)
  readonly property bool held: root.dock.detached
  readonly property var gaps: placement.gaps
  // Where the window starts across the edge (what's reserved there; not
  // docks, its own included)
  readonly property real reservedHere: EdgeMenuManager.reservedOn(root.screen, root.edge)
  readonly property bool attached: !placement.detached
  // Where its attach edge goes, from the screen edge: following a bar, as
  // that meets it; else the stroke of what reserves the edge (the screen
  // edge when bare; EdgePlacement.attachAt)
  readonly property real attachAt: placement.attachAt
  // On a pill's far stroke the surface covers that stroke's inner fringe
  readonly property real backfill: placement.backfill
  // An attached window's edge sits on its attach edge (reaching back onto
  // the stroke it joins, as EdgePopout's)
  // A preview reserves nothing, so the docks' zones on its edge push it in:
  // it reaches back past them to where a dock sits
  readonly property real edgeMargin: (root.attached ? root.attachAt - root.reservedHere - root.backfill : 0) - (root.preview ? DockManager.zoneOn(root.screen?.name ?? "", root._edgeName) : 0)
  // Detached, where its box goes from the window's edge: held, its gap
  // past the frame line; else a connector gap past where it attaches
  readonly property real _detachedBox: root.gaps ? placement.heldInset(root.edge, root.gaps.across) : Math.max(0, root.attachAt + root.connectorGap / 2 - root.reservedHere)
  // From the window's edge to the box of icons
  readonly property real boxOffset: root.backfill + surface.boxStart + (root.attached ? placement.attachClearance : 0)
  // The window: the gap to the edge, the box, and room for icons to grow
  // (and for an attached surface's far side, and the shadow it
  // casts, SurfaceShadow)
  readonly property real depth: root.boxOffset + root.thickness + Math.max(root.peak - root.base, (root.attached ? root.connectorGap / 2 : 0) + surface.shadowReach) + 2

  // --- Items ---
  // Re-read on every window change; delegates are keyed by the joined
  // keys, so they only rebuild when the set of apps changes
  readonly property var items: DockManager.itemsFor(root.dock, root.screen)
  readonly property string _keysJoined: root.items.map(item => item.key).join("\n")
  readonly property var keys: root._keysJoined ? root._keysJoined.split("\n") : []
  readonly property int count: root.keys.length
  readonly property int pinnedCount: root.items.filter(item => item.pinned).length
  readonly property bool separator: root.dock.running.separator && root.dock.running.show && root.pinnedCount > 0 && root.pinnedCount < root.count
  readonly property real lineWidth: Math.max(1, Appearance.borderWidth)
  readonly property real separatorLength: root.separator ? root.spacing + root.lineWidth : 0

  // --- Along the dock ---
  // In edge coordinates, as EdgePopout's: 0 at the perpendicular edges'
  // inner side. The window reaches onto their strokes where an end may
  // join one (EdgePlacement): where edge coordinates start in it, at each
  // end.
  readonly property real startStrokeInset: placement.strokeInsetStart
  readonly property real endStrokeInset: placement.strokeInsetEnd
  readonly property real length: placement.innerEnd - placement.innerStart
  readonly property real restLength: root.count * root.base + Math.max(0, root.count - 1) * root.spacing + root.separatorLength + root.pad * 2
  // The least room from the box to each end that isn't joined: held, its
  // gaps from the frame lines there; at a wall, up to where windows
  // start; else its fillet's past the corner (EdgePlacement)
  readonly property real startInset: placement.insetStart
  readonly property real endInset: placement.insetEnd
  readonly property real _wanted: root.length * root.dock.position / 100
  // The box's centre at rest, kept within those
  readonly property real centre: {
    if (root.restLength + root.startInset + root.endInset >= root.length)
      return (root.startInset + root.length - root.endInset) / 2;
    return Math.max(root.restLength / 2 + root.startInset, Math.min(root._wanted, root.length - root.restLength / 2 - root.endInset));
  }
  readonly property real restStart: root.centre - root.restLength / 2
  EdgePlacement {
    id: placement
    screen: root.screen
    edge: root.edge
    held: root.held
    gap: root.dock.gap
    centre: root.centre
    // Its joins from where it would rest, so magnifying never joins or
    // parts an end
    probeStart: root._wanted - root.restLength / 2
    probeLength: root.restLength
    aligned: root.centre - root.currentLength / 2
    contentLength: root.currentLength
    coverStart: surface.coverStart
    coverLength: surface.coverLength
    owner: "dock:" + root.dock.id + ":" + (root.screen?.name ?? "") + (root.preview ? ":preview" : "")
    // Its pill stretches as it's wanted, and draws back once it's gone
    showing: (root.wantShown || root._out) && root.count > 0
    open: root.wantShown
    // A preview is on the Overlay layer, but fills itself (no origin)
    onOverlayLayer: root.preview
    origin: root.preview ? null : root._origin
    attachedSurface: surface
    opens: root._origin !== null && !root.preview && panelWindow.visible && root.attached
  }
  readonly property var _origin: placeOnScreen.origin
  readonly property var place: placement.place

  // Magnification: the pointer along the row as laid out at rest, and how
  // far the icons have grown towards it (animated in and out)
  property real pointer: -1
  property real magnifyAmount: root.dock.magnify.enabled && hover.hovered && root.dragIndex < 0 ? 1 : 0
  Glide on magnifyAmount {}
  readonly property real _step: root.base + root.spacing
  readonly property var sizes: {
    let p = root.pointer - root.startStrokeInset - root.restStart - root.pad;
    if (root.separator && p > root.pinnedCount * root._step)
      p = Math.max(root.pinnedCount * root._step, p - root.separatorLength);
    const full = DockLayout.magnifiedSizes(root.count, root.pointer < 0 ? null : p, root.base, root.peak, root.dock.magnify.range, root.spacing);
    return full.map(size => root.base + (size - root.base) * root.magnifyAmount);
  }
  readonly property real currentLength: root.sizes.reduce((sum, size) => sum + size, 0) + Math.max(0, root.count - 1) * root.spacing + root.separatorLength + root.pad * 2
  // Where the icons' box starts along the window: where it wants to be,
  // the surface reaching past it to whatever it meets (place)
  readonly property real boxStart: root.startStrokeInset + root.place.contentStart
  // The surface's box along the window
  readonly property real surfaceBoxStart: root.startStrokeInset + root.place.start
  readonly property real surfaceBoxLength: root.place.end - root.place.start
  // Where each icon starts along the window
  readonly property var starts: {
    const starts = [];
    let at = root.boxStart + root.pad;
    for (let i = 0; i < root.count; i++) {
      if (root.separator && i === root.pinnedCount)
        at += root.separatorLength;
      starts.push(at);
      at += root.sizes[i] + root.spacing;
    }
    return starts;
  }
  readonly property real grown: Math.max(0, ...root.sizes) - root.base

  // --- Across the dock ---
  // How far it has slid in (0 hidden, 1 shown): once its pill has grown
  // out to carry it
  property real shown: root.wantShown && placement.stretchReady ? 1 : 0
  Glide on shown {
    duration: Appearance.animNormal
  }
  // Whether any of it is out: set by hand, as `shown` waits on the pill
  // stretch that this keeps up
  property bool _out: false
  onShownChanged: root._out = root.shown > 0
  readonly property real slide: (1 - root.shown) * root.depth

  // The cross-axis position (window coordinates) of something `fromEdge`
  // in from the dock's edge and `size` deep
  function crossAt(fromEdge, size) {
    switch (root.edge) {
    case Bar.Bottom:
      return panelWindow.height - fromEdge - size + root.slide;
    case Bar.Right:
      return panelWindow.width - fromEdge - size + root.slide;
    }
    return fromEdge - root.slide;
  }

  // --- Showing and hiding ---
  readonly property bool fullscreen: CompositorManager.hasFullscreen(root.screen?.name ?? "")
  readonly property bool hiddenByHand: !!DockManager.hidden[root.dock.id]
  // Opened by the trigger (after openDelay), a reveal, or the pointer on
  // the shown dock, until the pointer has been gone for closeDelay. Only
  // `latched` opens it: resting on the trigger doesn't, or openDelay would
  // be skipped, and a dock shown without latching would close at once.
  property bool latched: false
  // Whether the pointer has been on it since it latched: a reveal nobody
  // hovers (IPC, a bind) stays up a little longer than closeDelay
  property bool _touched: false
  // Something on the dock is in use
  property int dragIndex: -1
  readonly property bool menuOpen: menu.active
  readonly property bool engaged: hover.hovered || root.menuOpen || root.dragIndex >= 0
  // The pointer on the trigger while the dock is on screen (intellihide
  // showing it, or sliding out) holds it at once: openDelay is only for
  // opening a hidden dock
  readonly property bool _triggerHold: trigger.containsMouse && root.shown > 0
  readonly property bool _holding: root.engaged || root._triggerHold
  on_HoldingChanged: {
    if (root._holding) {
      root.latched = true;
      root._touched = true;
    }
  }
  // Keeps a latched dock open; the trigger counts, so a pointer resting on
  // the edge never lets it close
  readonly property bool pointerIn: root.engaged || trigger.containsMouse
  readonly property bool obscured: root.mode === "intellihide" && DockManager.obscured(root.screen, root._restRect())
  // The overlay on this screen puts it away, whatever its visibility, unless
  // it reserves its strip (hiding that would retile the windows under it)
  readonly property bool overlayOpen: ShellManager.surfaceOpenOn("overlay", root.screen)
  readonly property bool underOverlay: root.overlayOpen && !root.reserving
  // Any popout over it puts it away too (PopoutManager: it ranks lowest
  // but for pinned menus), a reserving one included: that keeps its zone,
  // so nothing retiles. It comes back once that's gone.
  property PopoutClaim claim: PopoutClaim {
    key: "dock:" + root.dock.id + ":" + (root.screen?.name ?? "")
    kind: "dock"
    resident: true
    screen: root.screen?.name ?? ""
    edge: root._edgeName
    wanted: !root.preview && !root.underOverlay && root._wouldShow
    footprint: root._footprint()
  }
  readonly property bool away: !root.preview && (root.underOverlay || root.claim.yielded)
  // Its preview shows in its place, so it hides at once (keeping its zone)
  readonly property bool previewed: !root.preview && DockManager.previewing(root.dock.id, root.screen)
  // A preview slides in once it's built (a Behavior doesn't animate the
  // value it's created with)
  property bool _entered: false
  Component.onCompleted: {
    if (root.preview)
      Qt.callLater(() => root._entered = true);
  }
  onAwayChanged: {
    if (root.away)
      root.conceal();
  }
  readonly property bool wantShown: {
    if (root.preview)
      return root._entered && DockManager.previewShown;
    return !root.away && root._wouldShow;
  }
  // Whether it would show, were nothing over it
  readonly property bool _wouldShow: {
    if (root.mode === "always")
      return !root.hiddenByHand;
    return root.latched || root.engaged || (root.mode === "intellihide" && !root.obscured);
  }
  readonly property bool reserving: !root.preview && root.mode === "always" && root.dock.reserveSpace && !root.hiddenByHand && root.count > 0

  // The shown box on the monitor (its work area's origin being the
  // reserved zones' corner), for intellihide
  function _restRect() {
    const reserved = DockManager.reservedOf(root.screen);
    const along = root.restStart;
    const across = root.boxOffset + root.edgeMargin;
    const w = root.screen?.width ?? 0;
    const h = root.screen?.height ?? 0;
    switch (root.edge) {
    case Bar.Top:
      return Qt.rect(reserved[0] + along, reserved[1] + across, root.restLength, root.thickness);
    case Bar.Left:
      return Qt.rect(reserved[0] + across, reserved[1] + along, root.thickness, root.restLength);
    case Bar.Right:
      return Qt.rect(w - reserved[2] - across - root.thickness, reserved[1] + along, root.thickness, root.restLength);
    }
    return Qt.rect(reserved[0] + along, h - reserved[3] - across - root.thickness, root.restLength, root.thickness);
  }

  // What it covers shown, in screen px: its box, and the fillets beside it
  // when it grows out of the edge
  function _footprint() {
    const r = root._restRect();
    if (!root.attached)
      return [r];
    const m = EdgeAttach.filletMargin(Appearance.borderWidth, Appearance.borderRadius);
    return [root.vertical ? Qt.rect(r.x, r.y - m, r.width, r.height + m * 2) : Qt.rect(r.x - m, r.y, r.width + m * 2, r.height)];
  }

  function reveal(byPointer) {
    // Put away, it would only latch to show once whatever outranks it goes
    if (root.away)
      return;
    root._touched = !!byPointer || root.engaged;
    root.latched = true;
    // Only restart a countdown that's due: restart() starts the timer even
    // while its binding says not to (the pointer on the dock or trigger)
    if (!root.pointerIn)
      closeTimer.restart();
  }

  function conceal() {
    root.latched = false;
    root.closeMenu();
  }

  Timer {
    id: closeTimer
    interval: root._touched ? root.dock.timing.closeDelay : Math.max(root.dock.timing.closeDelay, 1500)
    running: root.latched && !root.pointerIn
    onTriggered: root.latched = false
  }

  Connections {
    target: DockManager
    enabled: !root.preview

    function onRevealRequested(id) {
      if (id === root.dock.id)
        root.reveal();
    }

    function onConcealRequested(id) {
      if (id === root.dock.id)
        root.conceal();
    }

    function onToggleRequested(id) {
      if (id !== root.dock.id)
        return;
      if (root.wantShown)
        root.conceal();
      else
        root.reveal();
    }
  }

  // --- Menus (hover: names and windows; right click: everything) ---
  property string menuKey: ""
  property bool menuFull: false
  readonly property int menuIndex: root.keys.indexOf(root.menuKey)

  function openMenu(key, full) {
    root.menuKey = key;
    root.menuFull = full;
  }

  function closeMenu() {
    root.menuKey = "";
    root.menuFull = false;
  }

  // Pointer along the window, kept after it leaves so icons shrink back
  // from where it was
  readonly property real _livePointer: root.vertical ? hover.point.position.y : hover.point.position.x
  on_LivePointerChanged: {
    if (hover.hovered)
      root.pointer = root._livePointer;
  }

  EdgeTrigger {
    id: trigger
    screen: root.screen
    visible: !root.preview && root.mode !== "always" && !root.fullscreen && !root.away && root.count > 0
    edge: root.edge
    // Placed along the work area (inside the reserved zones), as the dock is
    position: 0
    startInset: 0
    endInset: 0
    positionOffset: DockManager.reservedOf(root.screen)[root.vertical ? 1 : 0] + root.centre
    triggerWidth: root.dock.trigger.size
    triggerLength: root.restLength
    hoverDelay: root.dock.timing.openDelay
    onTriggered: root.reveal(true)
  }

  PanelWindow {
    id: panelWindow

    screen: root.screen
    color: "transparent"
    // Once the windows before it in the stack have mapped
    visible: dockSlot.shown
    LayerSlot {
      id: dockSlot
      window: panelWindow
      namespace: panelWindow.layerNamespace
      layer: panelWindow.windowLayer
      wanted: root.count > 0
    }

    // Top, with its layer rule ordering it after the border and bars: it
    // sits inside them without shortening the bars on the other edges. A
    // fullscreen window covers it. A preview is on Overlay, its rule
    // ordering it after the overlay's panel.
    readonly property int windowLayer: root.preview ? WlrLayer.Overlay : WlrLayer.Top
    readonly property string layerNamespace: root.preview ? "axiom-dock-preview" : "axiom-dock"
    WlrLayershell.layer: panelWindow.windowLayer
    WlrLayershell.namespace: panelWindow.layerNamespace
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Normal
    // Hyprland counts the edge margin into it and adds gaps_out past it, so
    // windows start gaps_out past the box, held off the edge or not, as
    // from a screen edge
    exclusiveZone: root.reserving ? Math.max(0, root.boxOffset + root.thickness) : 0
    // Windows retile around it without an event saying so
    onExclusiveZoneChanged: DockManager.refreshSoon()

    // What it takes off the work area (Hyprland counts the edge margin
    // in), for the EdgePopouts and border corners that reach past it
    readonly property real reserved: panelWindow.visible && exclusiveZone > 0 ? exclusiveZone + root.edgeMargin : 0
    // Where it's reported. The zone set last is kept, so moving the dock to
    // another edge (or renaming it) moves its zone instead of leaving the
    // old one behind, and destruction clears it even once `dock` is gone.
    readonly property var zoneKey: root.dock && !root.preview ? [root.screen?.name ?? "", root._edgeName, root.dock.id] : null
    property var _zoneSet: null
    function _publishZone() {
      const key = panelWindow.zoneKey;
      const old = panelWindow._zoneSet;
      if (old && (!key || old.join(":") !== key.join(":"))) {
        DockManager.setZone(old[0], old[1], old[2], 0);
        DockManager.refreshSoon();
      }
      if (key)
        DockManager.setZone(key[0], key[1], key[2], panelWindow.reserved);
      panelWindow._zoneSet = key;
    }
    onReservedChanged: panelWindow._publishZone()
    onZoneKeyChanged: panelWindow._publishZone()
    Component.onCompleted: {
      panelWindow._publishZone();
      // The preview's blur region, attached only where the compositor
      // blurs regions (attached at all, it claims the window's blur, and
      // Hyprland's layer rules no longer blur it)
      if (CompositorManager.supports.blurRegion === true)
        BackgroundEffect.blurRegion = Qt.binding(() => root.preview && BlurManager.regions ? previewBlur : null);
    }
    Component.onDestruction: {
      const old = panelWindow._zoneSet;
      if (old)
        DockManager.setZone(old[0], old[1], old[2], 0);
    }

    anchors {
      top: root.edge !== Bar.Bottom
      bottom: root.edge !== Bar.Top
      left: root.edge !== Bar.Right
      right: root.edge !== Bar.Left
    }
    implicitWidth: root.vertical ? root.depth : 0
    implicitHeight: root.vertical ? 0 : root.depth

    // Along the edge it reaches onto the perpendicular strokes (startStrokeInset, endStrokeInset)
    margins {
      top: root.edge === Bar.Top ? root.edgeMargin : root.vertical ? -root.startStrokeInset : 0
      bottom: root.edge === Bar.Bottom ? root.edgeMargin : root.vertical ? -root.endStrokeInset : 0
      left: root.edge === Bar.Left ? root.edgeMargin : root.vertical ? 0 : -root.startStrokeInset
      right: root.edge === Bar.Right ? root.edgeMargin : root.vertical ? 0 : -root.endStrokeInset
    }

    // The box and the icons grown out of it, and the gap to the edge (so
    // the pointer doesn't leave the dock on its way from the edge); nothing
    // while it's hidden, or for a preview (the overlay under it keeps the
    // pointer)
    mask: Region {
      item: inputArea
    }

    Item {
      id: inputArea
      readonly property real alongStart: root.surfaceBoxStart
      readonly property bool open: root.shown > 0 && !root.preview
      readonly property real alongLength: open ? root.surfaceBoxLength : 0
      readonly property real crossDepth: open ? root.boxOffset + root.thickness + root.grown : 0

      x: root.vertical ? root.crossAt(0, crossDepth) : alongStart
      y: root.vertical ? alongStart : root.crossAt(0, crossDepth)
      width: root.vertical ? crossDepth : alongLength
      height: root.vertical ? alongLength : crossDepth
    }

    // A preview fills and blurs itself: where the compositor blurs only
    // what a window asks, its shape as drawn (attached in onCompleted)
    BlurRegion {
      id: previewBlur
      pieces: root.preview && BlurManager.regions ? SurfaceOutline.placeRegion(surface.blurPieces(), surface.x, surface.y, null) : []
    }

    // Where the window is on screen: the blur window draws the dock's fill
    // (BlurManager) from there; not a preview's, drawn over the overlay
    LayerOrigin {
      id: placeOnScreen
      window: panelWindow
      namespace: panelWindow.layerNamespace
      edge: root.edge
      layer: panelWindow.windowLayer
    }
    // The window on screen: a hiding box goes past its edge
    readonly property rect screenRect: Qt.rect(placeOnScreen.origin?.x ?? 0, placeOnScreen.origin?.y ?? 0, panelWindow.width, panelWindow.height)

    Item {
      id: dockContent
      anchors.fill: parent
      visible: !root.previewed

      HoverHandler {
        id: hover
      }

      // The box, joined to the edge or held off it (detached), as every
      // edge popout's
      EdgeSurface {
        id: surface
        x: root.vertical ? root.crossAt(0, width) : root.startStrokeInset + root.place.surfaceStart
        y: root.vertical ? root.startStrokeInset + root.place.surfaceStart : root.crossAt(0, height)
        width: implicitWidth
        height: implicitHeight

        geometry: placement
        screenName: root.screen?.name ?? ""
        windowShown: panelWindow.visible && dockContent.visible
        blurClip: panelWindow.screenRect
        active: true
        detachedOffset: Math.max(0, root._detachedBox - root.connectorGap / 2)
        boxWidth: root.vertical ? root.thickness + (root.attached ? placement.attachClearance : 0) : root.surfaceBoxLength
        boxHeight: root.vertical ? root.surfaceBoxLength : root.thickness + (root.attached ? placement.attachClearance : 0)
        fillColor: Theme.resolveColor(root.dock.backgroundColor)
        strokeColor: Theme.resolveColor(root.dock.borderColor)
        // Hiding, it moves past its window's edge
        hiddenBehind: Math.max(0, root.slide)
      }

      // Between the pinned apps and the others
      Rectangle {
        visible: root.separator
        readonly property real along: (root.starts[root.pinnedCount] ?? 0) - root.spacing - root.lineWidth
        readonly property real across: root.thickness - root.pad

        x: root.vertical ? root.crossAt(root.boxOffset + root.pad / 2, across) : along
        y: root.vertical ? along : root.crossAt(root.boxOffset + root.pad / 2, across)
        width: root.vertical ? across : root.lineWidth
        height: root.vertical ? root.lineWidth : across
        color: Theme.resolveColor(root.dock.borderColor)
        opacity: 0.5
      }

      Repeater {
        id: repeater
        model: root.keys

        delegate: DockItem {
          dockWindow: root
        }
      }
    }
  }

  DockMenu {
    id: menu
    dockWindow: root
    anchorItem: root.menuIndex >= 0 ? repeater.itemAt(root.menuIndex) as DockItem : null
    grabWindow: panelWindow
  }
}
