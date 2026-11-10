pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.methods
import qs.components.hosts.popout

// A floating edge menu: an EdgePopout over the windows, growing out of the
// border or a solid bar on its edge, and meeting any other bar there as a
// bar popout does (EdgePlacement): out of a pill or a floating bar's
// island, or a detached box past a transparent bar. One held off the edge
// (`detached`) is an island, placed as every detached surface is
// (ScreenEdgeManager.heldGaps): `distance` across the free screen from its
// edge, at 0 lined up with a floating bar's islands, or with the windows,
// sliding or fading in (`animation`).
EdgePopout {
  id: root

  required property var menu
  readonly property string menuId: root.menu.id

  // Held off the edge, `distance` across the free screen from it
  // (EdgePlacement.gaps)
  held: EdgeMenusConfig.detachedOf(root.menu)
  distance: root.menu.distance / 100
  fade: root.menu.animation === "fade"

  // Closes what it covers below it (PopoutManager); pinned, it ranks
  // lowest, and pinned or previewing it gives way and comes back
  claimKey: "menu:" + root.menuId
  // As it was opened (EdgeMenuManager.claimKinds): a widget's menu popout
  // (opened on hover, by its PopoutAnchor: a Button's popout.menu too)
  // ranks as that widget's bar popout, so a neighbour's popout replaces
  // it as bar popouts replace each other; opened any other way (a keybind, its edge, a bar Button's
  // click) it ranks as a menu
  claimKind: root.currentData?.claimKind ?? "menu"
  pinned: EdgeMenuManager.pinnedMenus[root.menuId] === true
  resident: sync.held

  // Along the edge, on the menu's lattice (GridPlacement.menuAlong),
  // in screen px: this window's edge coordinates start past what's
  // reserved on the perpendicular edge at its start (over a fullscreen
  // window, at the screen's edge: EdgePopout.bare)
  readonly property real screenLength: root.vertical ? root.screen?.height ?? 0 : root.screen?.width ?? 0
  readonly property real alongOrigin: root.bare ? 0 : ScreenEdgeManager.reservedWithMenusOn(root.screen, root.startSide)
  // The least room from the modules to the screen's ends: what's reserved
  // there, the box's inset and its padding
  readonly property real startPad: root.alongOrigin + root.startInset + root.contentPadding
  readonly property real endPad: (root.bare ? 0 : ScreenEdgeManager.reservedWithMenusOn(root.screen, root.endSide)) + root.endInset + root.contentPadding
  // From config, so the hover strip lines up before the body has loaded
  // Its card size (EdgeMenusConfig.cardUnitOf)
  readonly property int unit: EdgeMenusConfig.cardUnitOf(root.menu)
  readonly property real cardGap: EdgeMenusConfig.gapOf(root.menu)
  readonly property real gridLength: EdgeMenusConfig.gridLengthOf(root.menu, root.vertical, root.unit, root.cardGap)
  readonly property real modulesStart: GridPlacement.menuAlong(root.menu, root.screenLength, root.unit, root.startPad, root.endPad, root.cardGap)

  // Where the modules can sit, for the layouts editor (EdgeMenuManager.frames)
  readonly property var frame: ({
      "screen": root.screen?.name ?? "",
      "startPad": root.startPad,
      "endPad": root.endPad,
      "across": root.attachAt + root.contentPadding + root.attachExtra,
      "before": Math.max(0, root.attachBase),
      "after": root.contentPadding,
      "reserves": false
    })

  edge: EdgeMenusConfig.edgeOf(root.menu)
  // The box's centre, so it starts where the modules should, less its
  // padding. From its natural length (the joins at the ends depend on
  // where it is); one filling its edge joins both and needs none. Opened
  // as a widget's popout with `popoutAtWidget`, centred on that widget
  // instead, as a bar popout is (its ends clamped and joined alike).
  position: 0
  positionOffset: isNaN(root._widgetCentre) ? root.modulesStart - root.alongOrigin - root.contentPadding + (isFinite(root.naturalBox) ? root.naturalBox / 2 : 0) : root._widgetCentre - root.alongOrigin

  // The centre along the edge, in screen px, of the widget that opened it
  // as its popout, when it places itself there (on this edge and screen
  // only), else NaN. Taken as it opens, so an open popout never moves; a
  // close (no data) keeps it until the box has gone.
  property real _widgetCentre: NaN
  onCurrentDataChanged: {
    const data = root.currentData;
    if (!data)
      return;
    const rect = root.menu.popoutAtWidget && !GridPlacement.menuFillsEdge(root.menu) && data.claimKind === "bar" ? data.anchorItem?.screenRect?.() ?? null : null;
    root._widgetCentre = rect && rect.edge === root.edge && rect.screen?.name === root.screen?.name ? (root.vertical ? rect.y + rect.height / 2 : rect.x + rect.width / 2) : NaN;
  }
  // Fill cells grow to whatever room there is, so its ends always reach
  // (and, not held, join) the perpendicular edges
  reachLength: root._body ? (root._body.fillsEdge ? Infinity : root._body.naturalLength) : 0
  // Growing modules make a top or bottom menu deeper: room for the most
  maxContentDepth: !root.vertical && root._body ? root._body.maxGrownHeight : 0
  // Room for its submenus' stretch from the start (EdgePopout.roomForSubmenus):
  // from config, as the body loads with the window
  roomForSubmenus: root.menu.layout.modules.some(module => module?.type === "Submenu")
  // Read through a var: EdgeMenuBody's members, on EdgePopout's Item
  readonly property var _body: root.contentItem
  contentPadding: Appearance.borderWidth + PopoutsConfig.padding
  fillColor: EdgeMenusConfig.colorsOf(root.menu).fill
  strokeColor: EdgeMenusConfig.colorsOf(root.menu).stroke
  triggerEnabled: root.menu.open.onHover
  hoverDelay: root.menu.open.delay
  triggerLength: sync.triggerLength(root.vertical, root.contentPadding, root.screenLength - root.startPad - root.endPad + root.contentPadding * 2)
  // On the modules, in screen px (the box's own position is in this
  // window's coordinates, which start past the perpendicular edges')
  triggerCentre: GridPlacement.menuFillsEdge(root.menu) ? (root.startPad + root.screenLength - root.endPad) / 2 : root.modulesStart + root.gridLength / 2
  dismissDelay: EdgeMenusConfig.closeDelayOf(root.menu)
  keyboardOnDemand: true
  closeOnClickOutside: root.menu.close.onOutsideClick && !sync.held
  // Over the overlay its grab (which lets input through to the menu) is
  // the one: a grab of its own would clear it, closing the overlay
  grabEnabled: !root.overlayOpen
  autoDismiss: sync.autoDismiss

  EdgeMenuSync {
    id: sync
    host: root
    menu: root.menu
    screen: root.screen
    window: root.window
    triggerWindow: root.triggerWindow
    frame: root.frame
    onWarpRequested: {
      const box = root.boxInWindow;
      const at = root.contentInWindow;
      // Tiled, the card nearest the box's centre (MenuTiles.aim)
      const card = root.tiled ? MenuTiles.aim(cardMask.rects, Qt.point(box.x + box.width / 2 - at.x, box.y + box.height / 2 - at.y)) : null;
      const x = card ? at.x + card.x : box.x + box.width / 2;
      const y = card ? at.y + card.y : box.y + box.height / 2;
      CompositorManager.warpCursorToLayer(root.layerNamespace, root.screen?.name ?? "", root.window.width, root.window.height, x, y);
    }
  }

  // No box (`background: none`): its cards are tiles, held off its edge
  // (detachedOf), input on them alone (CardMask), a crossing between two
  // given the close delay's floor
  readonly property bool tiled: EdgeMenusConfig.tiledOf(root.menu)
  maskRegions: root.tiled ? cardMask : null
  hollow: root.tiled
  // How its cards' tiles are drawn (EdgeMenuBody.tiles): by the blur
  // window as its box would be, from where its content is on the screen
  // as drawn
  readonly property var _origin: root.window?.screenOrigin ?? null
  readonly property var _tiles: root.tiled ? ({
      "backed": root.surfaceItem.backed,
      "opaque": root.surfaceItem.opaque,
      "screen": root.screen?.name ?? "",
      "origin": root._origin ? Qt.point(root._origin.x + root.contentInWindow.x + root.surfaceItem.slideX, root._origin.y + root.contentInWindow.y + root.surfaceItem.slideY) : null,
      "clip": root._origin ? Qt.rect(root._origin.x, root._origin.y, root.window.width, root.window.height) : null,
      "overlayLayer": root.onOverlayLayer,
      "opacity": root.surfaceItem.shownOpacity,
      "look": root.surfaceItem.shadowLook
    }) : null
  CardMask {
    id: cardMask
    rects: root._body?.maskRects ?? []
    offset: root.contentInWindow
    box: root.boxItem
  }

  // Asked for again while open (EdgeMenuManager.engageRequested): it comes
  // forward (EdgePopout.engage). The integrated host holds no popout
  // claim, so it has no rank to raise. Asked to pop out, it hands its spot
  // to the free host (EdgeMenuManager.popOut)
  Connections {
    target: EdgeMenuManager

    function onEngageRequested(id) {
      if (id === root.menuId)
        root.engage();
    }

    // Its pop-out button: the free host takes it where its content is
    // now (its box there, the content inside the same padding)
    function onPopOutRequested(id) {
      if (id !== root.menuId || !root.isOpen)
        return;
      const at = root.contentOnScreen();
      EdgeMenuManager.popOut(id, {
        "screen": root.screen?.name ?? "",
        "x": at.x - root.contentPadding,
        "y": at.y - root.contentPadding
      });
    }
  }

  content: Component {
    EdgeMenuBody {
      menu: root.menu
      tiles: root._tiles
      vertical: root.vertical
      maxLength: root.maxBoxLength - root.contentPadding * 2
    }
  }
}
