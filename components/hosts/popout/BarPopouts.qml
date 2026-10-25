pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.services.core
import qs.services.compositor
import qs.services.ui
import qs.config
import qs.components.methods
import qs.components.reusable
// Imported (though loaded by URL) so qs scans the content folders whose
// files see each other (scripts/check_structure.py)
import qs.components.content.Submenu // qmllint disable unused-imports

/**
 * Popout wrapper for bar widgets
 * Handles positioning, animation, and content loading for popouts that emerge from the bar.
 * Opened from a widget under or beside the open box, it switches in place
 * (canSwitchTo): the box glides to the new widget and resizes while the
 * old content, held as a still, fades out over the new.
 * Open/close/queue state and dismiss timing live in PopoutWrapperBase — this
 * file only adds what's specific to bar popouts: which content type to
 * load, where to position it, and how to animate it in/out.
 */
PopoutWrapperBase {
  id: root

  required property ShellScreen screen
  required property var barConfig
  required property QtObject panel

  // The window showing the popout, a layer surface along the bar's edge.
  // On a transparent bar it's on the bar's layer, ordered under it, so a
  // detached box slides out from beneath the bar rather than out of thin
  // air at its invisible inner edge; else on the Overlay layer, over the
  // bar. That under-bar layer is also under the overlay: while that's open
  // here, the box shows over it instead, without sliding (LayerStack), as
  // it does where the compositor stacks by map order alone (no
  // supports.layerOrder: a window mapped as it opens lands over the bar).
  // Followed only while closed, since it changes the window's layer.
  // (EdgePlacement.slidesUnder)
  property ClosedLatch _under: ClosedLatch {
    source: placement.slidesUnder
    closed: !root.occupied
  }
  readonly property bool underBar: root._under.value ?? false
  // Over the overlay and fullscreen windows (BlurManager.backsOn), the box
  // and a submenu in its window: on the Overlay layer unless under the bar
  readonly property bool onOverlayLayer: !root.underBar
  window: mainPopup
  // Content box in its window's coordinates (see AttachedSurface.boxRect)
  readonly property rect boxRect: Qt.rect(surface.x + surface.boxRect.x, surface.y + surface.boxRect.y, surface.boxRect.width, surface.boxRect.height)

  // Its place among the popouts (PopoutManager), one per bar: it shows
  // once granted, closing what it covers below it, and closes when a
  // higher popout covers it (or won't open under one)
  property PopoutClaim claim: PopoutClaim {
    key: "bar:" + root.barConfig.id
    kind: "bar"
    screen: root.screen?.name ?? ""
    edge: Bar.edgeName(root.barConfig.location)
    barId: root.barConfig.id
    occupied: root.occupied
    closing: root.isClosing
    wanted: still.showing && !root.isClosing
    // The surface is at (barX, barY) in bar window coordinates, in either
    // window
    footprint: PopoutGeometry.offset(surface.footprint, Qt.point(mainPopup.barOrigin.x + mainPopup.barX, mainPopup.barOrigin.y + mainPopup.barY))
    onEvicted: root.requestDismiss()
    onRefused: root.requestDismiss()
  }
  // Granted (or closing after it was, PopoutClaim.held)
  readonly property bool claimed: root.claim.held

  // ---- Its submenu (SubPopout, through its SubmenuHost) ----
  // Opened by a PopoutAnchor in its content (mainPopup.popoutHost): the
  // tray's submenus, any other content's. What it meets on the box's side
  // is the stroke the box grows from on a horizontal bar: a solid bar's, a
  // pill's or island's far stroke as the box stretches it, else the
  // perpendicular strokes, or the border at a merged box's outer edge.
  submenuHost: slot
  SubmenuHost {
    id: slot
    wrapper: root
    screen: root.screen
    popupSurface: surface
    boxRect: root.boxRect
    // Where the popout's window is on screen, for a submenu's (its popup)
    // blur: null until the bar's is known; or where it most likely is
    popupScreenOrigin: surface.barOrigin ? mainPopup.windowOrigin : null
    popupScreenPlaced: mainPopup.windowOrigin
    animate: still.settled
    geometry: placement
    windowShift: mainPopup.alongShift
  }
  // ---- end submenu ----

  // content/<name>/<name>.qml (Paths.contentUrl), loaded by URL like bar
  // widgets and overlay modules: a new popout is just a type folder there
  // plus a PopoutAnchor naming it. The
  // name travels inside the payload (`name`, see PopoutAnchor.qml) rather
  // than as a separate argument, so this file never needs to override
  // openPopout/safeOpenPopout from the base.
  function _loadContent() {
    root._payloadApplied = false;
    const name = root.currentData?.name ?? "";
    if (loader.active && name !== "") {
      const url = Paths.contentUrl(name);
      // The same type for another widget (a switch in place) is built anew
      if (loader.source.toString() === url.toString())
        loader.source = "";
      loader.setSource(url, {
        "wrapper": root
      });
    } else if (!loader.active)
      // Cleared, so reactivating doesn't first rebuild the previous popout
      loader.source = "";
  }

  currentItem: loader.item ?? null
  // Loaded, and done fetching anything it must show before mapping (the
  // tray menu's contentReady); content without the property is ready
  // The Loader reports Ready before its onLoaded hands the content its
  // payload (the widget's data, which can size it), so it waits for that
  readonly property bool contentReady: loader.status === Loader.Ready && root._payloadApplied && (root.currentItem?.contentReady ?? true)
  property bool _payloadApplied: false

  // Content with a text field up asks for the keyboard (Panel's
  // wantsKeyboardFocus): a focus grab over the popout and its bar, which a
  // click outside clears (the content's focusLost())
  readonly property bool wantsKeyboardFocus: root.window.visible && (root.currentItem?.wantsKeyboardFocus ?? false)

  FocusGrab {
    id: focusGrab
    windows: [root.window, root.panel].concat(ShellManager.modalWindows)
    active: root.wantsKeyboardFocus
    onCleared: root.currentItem?.focusLost?.()
  }

  // Positioners (Row, Column, Grid, Flow) lay out on their window's
  // polish, which a window not yet mapped never runs: until then their
  // implicit size is 0, so content built from them (the workspace grid)
  // would map too small and grow a frame later. On a bottom or right bar
  // the popup then has to move as well, which the compositor doesn't
  // always follow, leaving it off the screen. So the loaded content is
  // laid out at once, innermost first.
  function _layOut(item) {
    for (const child of item.children)
      root._layOut(child);
    if (typeof item.forceLayout === "function")
      item.forceLayout();
  }

  // Where the anchor widget was when it opened, in bar-window coordinates
  // (from currentData.anchorItem; the anchorX/anchorY snapshot in the
  // payload is the fallback for callers that don't pass an item). An open
  // popout stays put: a widget moving or resizing meanwhile (modules
  // growing) doesn't drag it along, and it opens where it belongs next
  // time.
  property rect anchorRect: Qt.rect(0, 0, 0, 0)

  function updateAnchorRect() {
    const data = root.currentData;
    if (!data)
      return;
    const item = data.anchorItem;
    if (item) {
      try {
        const pos = item.mapToItem(null, 0, 0);
        root.anchorRect = Qt.rect(pos.x, pos.y, item.width, item.height);
        return;
      } catch (e) {
        // Anchor was destroyed (e.g. the bar rebuilt on a config reload)
      }
    }
    root.anchorRect = Qt.rect(data.anchorX ?? 0, data.anchorY ?? 0, data.anchorWidth ?? 0, data.anchorHeight ?? 0);
  }

  // Every payload loads afresh: a switch in place may bring the same
  // content type with another widget's data
  onCurrentDataChanged: {
    updateAnchorRect();
    _loadContent();
  }

  // ---- Switching in place ----
  // A widget under the box, or within a connector gap of it, along the bar
  canSwitchTo: (anchor, data) => {
    const item = data?.anchorItem;
    if (anchor !== root.currentAnchor || !still.showing || !item)
      return false;
    const pos = item.mapToItem(null, 0, 0);
    const from = root.barConfig.vertical ? pos.y : pos.x;
    const to = from + (root.barConfig.vertical ? item.height : item.width);
    return from <= mainPopup.boxEnd + placement.connectorGap && to >= mainPopup.boxStart - placement.connectorGap;
  }
  // The old content held as a still where it is along the bar
  // (SwitchStill), then the new payload opened under it
  prepareSwitch: done => still.prepare(root.currentItem, done)
  // ---- end switching in place ----

  // Where the box goes along the bar and everything that follows from what
  // it meets there (EdgePlacement, shared with edge popouts and docks), in
  // bar-window coordinates: growing out of the anchor's pill or island,
  // stretching it to carry the box; grown from a pill bar's outer edge when
  // it shows no pills (merged), its box as deep as the pills would be; a
  // detached box past a transparent bar; joining the perpendicular edges
  // where it reaches them (their stroke, or a pill bar's far side), with
  // the strokes it covers left open
  readonly property real anchorCentre: root.barConfig.vertical ? root.anchorRect.y + root.anchorRect.height / 2 : root.anchorRect.x + root.anchorRect.width / 2
  // Out and granted: what the openings and the joined pill bars follow
  readonly property bool _out: root.occupied && root.claimed && root.window.visible
  EdgePlacement {
    id: placement
    screen: root.screen
    edge: root.barConfig.location
    followPanel: root.panel
    alongStart: root.barConfig.vertical ? mainPopup.barOrigin.y : mainPopup.barOrigin.x
    centre: root.anchorCentre
    aligned: mainPopup.alignedBoxStart
    contentLength: mainPopup.boxLength
    probeStart: mainPopup.alignedBoxStart
    probeLength: mainPopup.boxLength
    coverStart: surface.coverStart
    coverLength: surface.coverLength
    drawnSurfaceStart: mainPopup.shownAlongPos
    submenu: slot
    owner: "barPopout:" + root.barConfig.id
    showing: root.occupied && root.claimed
    open: still.showing && !root.isClosing && root.claimed
    onOverlayLayer: root.onOverlayLayer
    overOverlay: ShellManager.surfaceOpenOn("overlay", root.screen)
    origin: slot.popupScreenOrigin
    attachedSurface: surface
    opens: root._out
  }
  readonly property var place: placement.place

  // How far past the bar's outer edge a merged popout's content starts:
  // where a pill's far stroke would be, with the border on or off
  readonly property real pillClearance: placement.attachClearance
  // Where the popout attaches, measured from the bar's outer edge
  // (EdgePlacement.attachFromBar)
  readonly property real attachAt: placement.attachFromBar
  // Read through a var: screenOrigin is BarPanel's, not QtObject's
  readonly property var _panel: root.panel
  // The bar window's thickness (more than the bar's extent with pills)
  readonly property real panelThickness: root.panel?.thickness ?? root.barConfig.extent
  // Where the under-bar window starts, from the bar's outer edge: past the
  // border stroke the outer edge of a bar inside the border lies on
  readonly property real underStart: root.barConfig.insideBorder ? Appearance.borderWidth : 0
  // Where the surface starts, from the bar's outer edge: a detached box's
  // reaches back to the under-bar window's edge, to slide in from there
  readonly property real surfaceFrom: surface.detached && root.underBar ? root.underStart : root.attachAt

  // Resizing a window while it shows is a round trip to the compositor
  // (a popup's reposition, a layer surface's configure), so the outline
  // lagged content that changes size (the calendar's editor). So the
  // windows never follow the content: along the bar the popup spans the
  // whole bar, and across it both keep the most room the box has needed
  // since the popout opened, or that its content declares it can take
  // (Panel.maxImplicitHeight/Width), with the surface on the bar side of
  // that room. Content resizing changes only the scene, and the box
  // animates to its new size (and place along the bar) in it.
  readonly property real targetBoxWidth: mainPopup.contentWidth + surface.contentInset * 2 + (root.barConfig.vertical ? root.pillClearance : mainPopup.boxGrow)
  readonly property real targetBoxHeight: mainPopup.contentHeight + surface.contentInset * 2 + (root.barConfig.vertical ? mainPopup.boxGrow : root.pillClearance)
  // What's drawn: the targets, animated once the popout shows
  property real shownBoxWidth: still.holding ? still.held.width : root.targetBoxWidth
  property real shownBoxHeight: still.holding ? still.held.height : root.targetBoxHeight
  property real shownBoxStart: still.holding ? still.held.start : mainPopup.boxStart
  // Where the box is drawn along the bar: on a vertical bar, reaching up
  // past its start for a submenu (shownStretchTop)
  readonly property real drawnBoxStart: root.shownBoxStart - (root.barConfig.vertical ? slot.shownStretchTop : 0)
  Glide on shownBoxWidth {
    enabled: still.settled
  }
  Glide on shownBoxHeight {
    enabled: still.settled
  }
  Glide on shownBoxStart {
    enabled: still.settled
  }

  // (a submenu's stretch included, so the window keeps room for it too)
  readonly property real _boxAcross: root.barConfig.vertical ? root.targetBoxWidth : root.targetBoxHeight + slot.stretchAcross
  readonly property real _shownBoxAcross: root.barConfig.vertical ? root.shownBoxWidth : root.shownBoxHeight + slot.shownStretchAcross
  // Read through a var: content declares it on Panel, not Item
  readonly property var _content: root.currentItem
  readonly property real _declaredAcross: {
    const item = root._content;
    const declared = root.barConfig.vertical ? item?.maxImplicitWidth ?? 0 : item?.maxImplicitHeight ?? 0;
    const content = root.barConfig.vertical ? mainPopup.contentWidth : mainPopup.contentHeight;
    return root._boxAcross + Math.max(0, declared - content);
  }
  property real _peakAcross: 0
  function _notePeak() {
    if (root.occupied && root.contentReady)
      root._peakAcross = Math.max(root._peakAcross, root._boxAcross);
  }
  on_BoxAcrossChanged: _notePeak()
  onContentReadyChanged: _notePeak()
  onOccupiedChanged: {
    if (!root.occupied)
      root._peakAcross = 0;
  }
  // The room past the drawn box, on the side away from the bar: the
  // window's depth stays put while the box animates within it
  // (and room for the shadow the surface casts, see SurfaceShadow)
  readonly property real spareAcross: Math.max(0, Math.max(root._peakAcross, root._declaredAcross, root._boxAcross) - root._shownBoxAcross) + surface.shadowReach
  // On a bottom or right bar the room lies before the surface
  readonly property bool spareBefore: root.barConfig.vertical ? root.barConfig.right : root.barConfig.bottom

  Component.onDestruction: ShellManager.unregisterGrabPartner(mainPopup)

  // The overlay's focus grab lets input through to the popout (see
  // ShellManager.grabPartners)
  function _registerGrabPartners() {
    ShellManager.registerGrabPartner(mainPopup, root.screen?.name);
  }
  Component.onCompleted: _registerGrabPartners()
  onScreenChanged: _registerGrabPartners()

  // Ignoring what others reserve, it starts at the screen's edge, so where
  // things are in it follows from where the bar is (BarPanel.screenPlaced)
  // alone: along the bar it spans the whole screen, and across it reaches
  // from the screen's edge past the box.
  PanelWindow {
    id: mainPopup
    screen: root.screen
    visible: still.showing
    color: "transparent"

    WlrLayershell.layer: root.onOverlayLayer ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.namespace: root.underBar ? "axiom-popout-under" : "axiom-popout"
    WlrLayershell.keyboardFocus: root.wantsKeyboardFocus ? (focusGrab.exclusive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand) : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0

    anchors {
      top: root.barConfig.top || root.barConfig.vertical
      bottom: root.barConfig.bottom || root.barConfig.vertical
      left: root.barConfig.left || !root.barConfig.vertical
      right: root.barConfig.right || !root.barConfig.vertical
    }

    // What PopoutAnchors in its content open in
    readonly property var popoutHost: root.submenu

    // Where the bar window is on the screen, else where it most likely is
    readonly property point barOrigin: root._panel?.screenPlaced ?? Qt.point(0, 0)
    // Where this window is on the screen: at its edge
    readonly property point windowOrigin: Qt.point(root.barConfig.right ? root.screen.width - width : 0, root.barConfig.bottom ? root.screen.height - height : 0)
    // Along the bar, bar-window coordinates to this window's
    readonly property real alongShift: (root.barConfig.vertical ? barOrigin.y - windowOrigin.y : barOrigin.x - windowOrigin.x)

    // Content dimensions
    readonly property int contentWidth: root.currentItem?.implicitWidth ?? 200 // fixed px: a placeholder until content loads
    readonly property int contentHeight: root.currentItem?.implicitHeight ?? 100 // fixed px: a placeholder until content loads

    // Along the bar, in bar-window coordinates: the box centred on the
    // anchor, and the surface around it with a fillet margin each side,
    // placed by EdgeAttach (root.place). One that would be pushed back from
    // an end, or come within a connector gap of it, joins it instead: flush
    // on the perpendicular stroke, merging into that edge.
    readonly property real boxLength: (root.barConfig.vertical ? mainPopup.contentHeight : mainPopup.contentWidth) + surface.contentInset * 2
    readonly property real alignedBoxStart: {
      if (!root.currentData)
        return 0;
      const start = root.barConfig.vertical ? root.anchorRect.y : root.anchorRect.x;
      const length = root.barConfig.vertical ? root.anchorRect.height : root.anchorRect.width;
      return start + (length - mainPopup.boxLength) / 2;
    }
    readonly property real boxStart: root.place.start
    // Room the box takes past its content: to an island's ends, or from
    // stroke to stroke when it joins both
    readonly property real boxGrow: root.place.grow
    readonly property real boxEnd: root.place.end
    // Where the surface is drawn along the bar, the box animating to its
    // place (see shownBoxStart)
    readonly property real shownAlongPos: root.drawnBoxStart - surface.startMargin

    // Where the surface sits, in bar-window coordinates
    readonly property real barX: {
      if (!root.currentData)
        return 0;
      if (root.barConfig.left) {
        return root.surfaceFrom - surface.backfill;
      } else if (root.barConfig.right) {
        // Mirror of the left case: measured from the bar's outer edge,
        // not relative to the anchor (tray icons are narrower than modules)
        return root.panelThickness - root.surfaceFrom + surface.backfill - surface.implicitWidth;
      } else {
        return mainPopup.shownAlongPos;
      }
    }

    readonly property real barY: {
      if (!root.currentData)
        return 0;
      if (root.barConfig.top) {
        return root.surfaceFrom - surface.backfill;
      } else if (root.barConfig.bottom) {
        return root.panelThickness - root.surfaceFrom + surface.backfill - surface.implicitHeight;
      } else {
        return mainPopup.shownAlongPos;
      }
    }

    // Only the surface takes input (under the bar, only its box: the bar
    // over it keeps its own)
    mask: Region {
      item: root.underBar ? boxArea : surface
    }
    Item {
      id: boxArea
      x: root.boxRect.x
      y: root.boxRect.y
      width: root.boxRect.width
      height: root.boxRect.height
    }

    // Across the bar, from the screen's edge to past the box and the room
    // it may grow into (see spareAcross). On a bottom or right bar the
    // window instead takes the screen's whole depth: one growing there
    // would also have to move, and the compositor shows a resize a frame
    // or more before the move, flashing the new size in the old place
    // (switching in place to taller content). At a fixed size it never does.
    // So does a top bar's: a submenu longer than the box stretches it away
    // from the bar, and a window growing while it shows is drawn for a
    // frame with its old contents squeezed into the new size
    readonly property bool wholeDepth: root.spareBefore || !root.barConfig.vertical
    readonly property real _barNear: root.barConfig.vertical ? (root.barConfig.right ? root.screen.width - barOrigin.x - root.panelThickness : barOrigin.x) : (root.barConfig.bottom ? root.screen.height - barOrigin.y - root.panelThickness : barOrigin.y)
    readonly property real depth: wholeDepth ? (root.barConfig.vertical ? root.screen.width : root.screen.height) : _barNear + root.surfaceFrom - surface.backfill + (root.barConfig.vertical ? surface.implicitWidth : surface.implicitHeight) + root.spareAcross
    implicitWidth: root.barConfig.vertical ? depth : 0
    implicitHeight: root.barConfig.vertical ? 0 : depth

    // How much more the box can grow before it meets what's on the
    // screen's far side (along a vertical bar, its ends'). Content that
    // grows on its own reads it through its window: StyledComboEntry opens
    // its list inline here, no taller than this
    readonly property real popoutRoom: {
      if (!root.screen)
        return 0;
      if (root.barConfig.vertical)
        return root.screen.height - EdgeMenuManager.frameLineOn(root.screen, Bar.Top) - EdgeMenuManager.frameLineOn(root.screen, Bar.Bottom) - root.targetBoxHeight;
      return root.screen.height - EdgeMenuManager.frameLineOn(root.screen, root.barConfig.top ? Bar.Bottom : Bar.Top) - mainPopup._barNear - root.surfaceFrom - root._boxAcross;
    }
    // The surface in this window: where it is in the bar's, moved by where
    // the bar is on the screen
    readonly property real surfaceX: barOrigin.x - windowOrigin.x + barX
    readonly property real surfaceY: barOrigin.y - windowOrigin.y + barY
  }

  EdgeSurface {
    id: surface
    // In whichever window shows the popout
    parent: mainPopup.contentItem
    x: mainPopup.surfaceX
    y: mainPopup.surfaceY
    width: implicitWidth
    height: implicitHeight

    geometry: placement
    submenu: slot
    screenName: root.screen?.name ?? ""
    windowShown: root.window.visible
    animateShape: still.settled
    // Once its pill has grown out to carry it
    active: still.showing && !root.isClosing && root.claimed && placement.stretchReady
    // Where the bar window is on screen (null until known): the surface is
    // at (barX, barY) in its coordinates, in either window
    readonly property var barOrigin: root._panel?.screenOrigin ?? null
    boxWidth: root.shownBoxWidth
    // A submenu's stretch: along the bar on a vertical one, away from it
    // on a horizontal one
    boxHeight: root.shownBoxHeight + slot.shownStretchTop + slot.shownStretchBottom
    // A detached box on a transparent bar slides out from under it
    detachedOffset: root.underBar ? root.attachAt - root.underStart : 0

    // The content keeps its target size while the box animates to it,
    // hung from the box's start along the bar and from its bar side
    // across it, and cut to the box (as FloatingPopout does)
    Item {
      id: clipBox
      anchors.fill: parent
      clip: true

      Loader {
        id: loader
        // Merged (a pill bar showing no pills), the content starts past
        // where the pills would be
        readonly property real barSide: surface.contentInset + root.pillClearance
        // Along the bar, where it wants to be (EdgeAttach.place's
        // contentStart), however far the box grows past it either side
        readonly property real along: surface.contentInset + root.place.contentStart - root.drawnBoxStart
        width: mainPopup.contentWidth
        height: mainPopup.contentHeight
        x: root.barConfig.left ? barSide : root.barConfig.right ? clipBox.width - barSide - width : along
        y: root.barConfig.top ? barSide : root.barConfig.bottom ? clipBox.height - barSide - height : along
        opacity: still.contentOpacity

        active: root.occupied
        asynchronous: false

        onActiveChanged: root._loadContent()

        onLoaded: {
          if (item) {
            if (root.currentData) {
              for (let key in root.currentData) {
                if (item.hasOwnProperty(key)) {
                  // Content may derive one itself (a readonly property):
                  // skip it rather than abort
                  try {
                    item[key] = root.currentData[key];
                  } catch (e) {}
                }
              }
            }
            root._layOut(item);
          }
          root._payloadApplied = true;
          root.updateDismissTimer();
        }
      }

      // The content switched away from, held where it was along the bar
      // while the box glides on
      SwitchStill {
        id: still
        contentReady: root.contentReady
        occupied: root.occupied
        snapshot: () => ({
              "start": root.shownBoxStart,
              "width": root.shownBoxWidth,
              "height": root.shownBoxHeight,
              "along": surface.contentInset + root.place.contentStart
            })
        readonly property real along: (held?.along ?? 0) - root.drawnBoxStart
        x: root.barConfig.left ? loader.barSide : root.barConfig.right ? clipBox.width - loader.barSide - width : along
        y: root.barConfig.top ? loader.barSide : root.barConfig.bottom ? clipBox.height - loader.barSide - height : along
      }
    }
  }
}
