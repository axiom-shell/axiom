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
// A free menu opened as a bar widget's popout (`openerRect`) is this
// host's too: out of that widget's bar edge, centred on the widget as a
// bar popout is, always sliding, its own place settings ignored.
EdgePopout {
  id: root

  required property var menu
  readonly property string menuId: root.menu.id
  // The widget it opened at (PopoutAnchor.screenRect(): { x, y, width,
  // height } in screen px, its bar's edge (a ScreenEdge) and screen), taken
  // as it opened by MenuHosts, else null: it is where it is placed
  property var openerRect: null
  readonly property bool atWidget: root.openerRect !== null
  // This host shows the menu: false while it hands over to another
  // widget's (MenuHosts), then it hides with its slide
  property bool shows: true

  // Held off the edge, `distance` across the free screen from it
  // (EdgePlacement.gaps); at a widget it sits on its bar's edge
  held: MenusConfig.detachedOf(root.menu)
  distance: root.atWidget ? 0 : root.menu.distance / 100
  fade: !root.atWidget && root.menu.animation !== "slide"

  // Closes what it covers below it (PopoutManager); pinned, it ranks
  // lowest, and pinned or previewing it gives way and comes back
  claimKey: "menu:" + root.menuId
  // As it was opened (MenuManager.claimKinds): a widget's menu popout
  // (opened on hover, by its PopoutAnchor: a Button's popout.menu too)
  // ranks as that widget's bar popout, so a neighbour's popout replaces
  // it as bar popouts replace each other; opened any other way (a keybind, its edge, a bar Button's
  // click) it ranks as a menu
  claimKind: root.currentData?.claimKind ?? "menu"
  pinned: MenuManager.pinnedMenus[root.menuId] === true
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
  // Its grid on its screen (MenusConfig.layoutOf)
  readonly property var layout: MenusConfig.layoutOf(root.menu)
  // Its card size
  readonly property int unit: root.layout.unit
  readonly property real cardGap: root.layout.gap
  readonly property real gridLength: MenusConfig.gridLengthOf(root.menu, root.vertical, root.unit, root.cardGap)
  readonly property real modulesStart: GridPlacement.menuAlong(root.menu, root.screenLength, root.unit, root.startPad, root.endPad, root.cardGap)

  // Where the modules can sit, for the layouts editor (MenuManager.frames)
  readonly property var frame: root.atWidget ? null : ({
      "screen": root.screen?.name ?? "",
      "startPad": root.startPad,
      "endPad": root.endPad,
      "across": root.attachAt + root.contentPadding + root.attachExtra,
      "before": Math.max(0, root.attachBase),
      "after": root.contentPadding,
      "reserves": false
    })

  edge: root.atWidget ? root.openerRect.edge : MenusConfig.edgeOf(root.menu)
  // The box's centre, so it starts where the modules should, less its
  // padding. From its natural length (the joins at the ends depend on
  // where it is); one filling its edge joins both and needs none. At a
  // widget, centred on that widget instead, as a bar popout is (its ends
  // clamped and joined alike).
  position: 0
  positionOffset: isNaN(root._widgetCentre) ? root.modulesStart - root.alongOrigin - root.contentPadding + (isFinite(root.naturalBox) ? root.naturalBox / 2 : 0) : root._widgetCentre - root.alongOrigin

  // The centre along the edge, in screen px, of the widget it opened at,
  // else NaN
  readonly property real _widgetCentre: root.atWidget ? (root.vertical ? root.openerRect.y + root.openerRect.height / 2 : root.openerRect.x + root.openerRect.width / 2) : NaN
  // Laid out down a column at a widget (as a free menu's window), else
  // as its edge says
  readonly property bool _bodyVertical: root.atWidget || root.vertical
  // Fill cells grow to whatever room there is, so its ends always reach
  // (and, not held, join) the perpendicular edges. A column under a top
  // or bottom edge is as wide as it is
  reachLength: root._body ? (root._bodyVertical !== root.vertical ? root._body.implicitWidth : root._body.fillsEdge ? Infinity : root._body.naturalLength) : 0
  // Growing modules make a top or bottom menu deeper: room for the most
  maxContentDepth: !root.vertical && root._body ? root._body.maxGrownHeight : 0
  // The body's length cap, as a free menu's (FreeMenu.maxLength): along
  // the edge its box's room less padding, a column under a top or bottom
  // edge the screen's height from the edge to the far side's reserve
  readonly property real maxLength: root._bodyVertical !== root.vertical ? (root.screen?.height ?? 0) - root.attachAt - (root.bare ? 0 : ScreenEdgeManager.reservedWithMenusOn(root.screen, ScreenEdge.opposite(root.edge))) - root.attachExtra - root.contentPadding * 2 : root.maxBoxLength - root.contentPadding * 2
  // Room for its submenus' stretch from the start (EdgePopout.roomForSubmenus):
  // from config, as the body loads with the window
  roomForSubmenus: root.menu.layout.modules.some(module => module?.type === "Submenu")
  // Read through a var: MenuBody's members, on EdgePopout's Item
  readonly property var _body: root.contentItem
  contentPadding: Appearance.borderWidth + PopoutsConfig.padding
  fillColor: MenusConfig.colorsOf(root.menu).fill
  strokeColor: MenusConfig.colorsOf(root.menu).stroke
  triggerEnabled: !root.atWidget && root.menu.open.onHover
  triggerLength: sync.triggerLength(root.vertical, root.contentPadding, root.screenLength - root.startPad - root.endPad + root.contentPadding * 2)
  // On the modules, in screen px (the box's own position is in this
  // window's coordinates, which start past the perpendicular edges')
  triggerCentre: GridPlacement.menuFillsEdge(root.menu) ? (root.startPad + root.screenLength - root.endPad) / 2 : root.modulesStart + root.gridLength / 2
  // At a widget it closes on leave like a bar popout, with its delay
  dismissDelay: root.atWidget ? PopoutsConfig.dismissDelay : root.menu.close.delay
  keyboardOnDemand: true
  closeOnClickOutside: root.menu.close.onOutsideClick && !sync.held
  // Over the overlay its grab (which lets input through to the menu) is
  // the one: a grab of its own would clear it, closing the overlay
  grabEnabled: !root.overlayOpen
  autoDismiss: sync.autoDismiss

  MenuSync {
    id: sync
    host: root
    menu: root.menu
    screen: root.screen
    window: root.window
    triggerWindow: root.triggerWindow
    frame: root.frame
    shows: root.shows
    // Never into a free menu (FreeMenu)
    warps: !root.atWidget
    closeOnLeave: root.atWidget || root.menu.close.onLeave
    onWarpRequested: {
      const box = root.boxInWindow;
      CompositorManager.warpCursorToLayer(root.layerNamespace, root.screen?.name ?? "", root.window.width, root.window.height, box.x + box.width / 2, box.y + box.height / 2);
    }
  }

  // No box (`background: none`): its cards are tiles, held off its edge
  // (detachedOf); its input is still the whole box, so the gaps between
  // the cards are the menu's (hovering one keeps it open, a click there
  // is inside it)
  readonly property bool tiled: MenusConfig.tiledOf(root.menu)
  hollow: root.tiled
  // How its cards' tiles are drawn (MenuBody.tiles): by the blur
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
  // Asked for again while open (MenuManager.engageRequested): it comes
  // forward (EdgePopout.engage). The integrated host holds no popout
  // claim, so it has no rank to raise. Asked to pop out, it hands its spot
  // to the free host (MenuManager.popOut)
  Connections {
    target: MenuManager

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
      MenuManager.popOut(id, {
        "screen": root.screen?.name ?? "",
        "x": at.x - root.contentPadding,
        "y": at.y - root.contentPadding
      });
    }
  }

  content: Component {
    MenuBody {
      menu: root.menu
      screen: root.screen
      tiles: root._tiles
      free: root.atWidget
      vertical: root._bodyVertical
      maxLength: root.maxLength
    }
  }
}
