pragma Singleton
import QtQuick

// Where a free menu's box goes on its screen (surfaces/edgemenu/FreeMenu),
// and the side its slide comes in from. Pure: the host passes the screen,
// what's kept clear at each edge, the box, what opened it and its anchor.
// Also which spot it takes over its anchor (a drag, a pop-out, the
// session's), whether a drag is kept, and which host a menu shows in.
QtObject {
  id: root

  readonly property var _edges: ["top", "bottom", "left", "right"]

  // Its box's top-left on the screen, and the screen edge it slides in
  // from: { x, y, slideFrom } (slideFrom an edge name). `p`:
  //   width, height   the screen's size
  //   insets          { top, bottom, left, right }: px kept clear from
  //                   each screen edge (what's reserved there, the gap
  //                   windows keep)
  //   box             { width, height }
  //   opener          { x, y, width, height, edge (an edge name) } on this
  //                   screen: a bar widget that opened it as its popout,
  //                   else null
  //   anchor          its freeAnchor: { at: centre | cursor | point, x, y
  //                   (point: the box's centre, % of the screen) }
  //   cursor          { x, y } on this screen, or null (unknown)
  //   spot            { x, y }: the box's top-left asked for (spot()),
  //                   or null
  // With a spot it goes there, clamped. Opened by a widget it sits at that widget: centred on it along its
  // bar's edge, flush with what's kept clear there, and slides from that
  // edge. Else it's centred on its anchor: the cursor (the free area's
  // centre while unknown), a point, or the free area's centre; and slides
  // from the screen edge nearest its centre. Either way it's clamped into
  // the free area, its start kept where it doesn't fit.
  function place(p) {
    const insets = p.insets;
    const box = p.box;
    const opener = p.opener ?? null;
    const anchor = p.anchor ?? {
      "at": "centre"
    };
    const left = insets.left, top = insets.top;
    const right = p.width - insets.right, bottom = p.height - insets.bottom;
    let cx = (left + right) / 2, cy = (top + bottom) / 2;
    let slideFrom = "";
    if (p.spot) {
      cx = p.spot.x + box.width / 2;
      cy = p.spot.y + box.height / 2;
    } else if (opener && root._edges.includes(opener.edge)) {
      const vertical = opener.edge === "left" || opener.edge === "right";
      if (vertical) {
        cy = opener.y + opener.height / 2;
        cx = opener.edge === "left" ? left + box.width / 2 : right - box.width / 2;
      } else {
        cx = opener.x + opener.width / 2;
        cy = opener.edge === "top" ? top + box.height / 2 : bottom - box.height / 2;
      }
      slideFrom = opener.edge;
    } else if (anchor.at === "cursor" && p.cursor) {
      cx = p.cursor.x;
      cy = p.cursor.y;
    } else if (anchor.at === "point") {
      cx = p.width * (anchor.x ?? 50) / 100;
      cy = p.height * (anchor.y ?? 50) / 100;
    }
    const clamp = (v, lo, hi) => hi < lo ? lo : Math.max(lo, Math.min(hi, v));
    const x = Math.round(clamp(cx - box.width / 2, left, right - box.width));
    const y = Math.round(clamp(cy - box.height / 2, top, bottom - box.height));
    return {
      "x": x,
      "y": y,
      "slideFrom": slideFrom !== "" ? slideFrom : root.nearestEdge(x + box.width / 2, y + box.height / 2, p.width, p.height)
    };
  }

  // The screen edge nearest a point on a `width` × `height` screen, as an
  // edge name (ties: top, bottom, left, right)
  function nearestEdge(x, y, width, height) {
    const distances = [y, height - y, x, width - x];
    let best = 0;
    for (let i = 1; i < distances.length; i++)
      if (distances[i] < distances[best])
        best = i;
    return root._edges[best];
  }

  // The spot its box takes over its anchor (place()'s `spot`): { x, y },
  // its top-left in px on its screen, or null (opener or anchor). `p`:
  //   dragged      where it was dragged to since it opened, or null
  //   popOut       the docked box's spot it popped out at
  //                (EdgeMenuManager.poppedOut: { screen, x, y }), or null
  //   fromWidget   opened by a bar widget (its popout, a Button)
  //   session      its session spot (EdgeMenuManager.positions:
  //                { screen, x, y, anchor }), or null
  //   screen       its screen's name
  //   anchor       its freeAnchor
  //   draggable    its `draggable`
  // A drag wins, then a pop-out. Opened by a widget it goes to the
  // widget. Else its session spot, while it's draggable, on its screen
  // (dropped once that screen is gone or the menu moved) and its anchor
  // is still the one it was dragged from (a changed freeAnchor drops it).
  function spot(p) {
    if (p.dragged)
      return {
        "x": p.dragged.x,
        "y": p.dragged.y
      };
    if (p.popOut && p.popOut.screen === p.screen)
      return {
        "x": p.popOut.x,
        "y": p.popOut.y
      };
    if (p.fromWidget)
      return null;
    const session = p.session ?? null;
    if (!session || !p.draggable || session.screen !== p.screen || session.anchor !== root.anchorKey(p.anchor))
      return null;
    return {
      "x": session.x,
      "y": session.y
    };
  }

  // A freeAnchor as a session spot keeps it (spot()'s `anchor` check)
  function anchorKey(anchor) {
    return JSON.stringify(anchor ?? null);
  }

  // Whether a drag's end is kept as the menu's session spot: a free menu
  // opened on its own (a bind, IPC, a pin reopening), never one a widget
  // opened, nor a popped-out edge menu (its drag is for the moment)
  function keepsDrag(p) {
    return !!p.free && !p.poppedOut && !p.fromWidget;
  }

  // Whether an open menu's box moves when dragged by its header: a free
  // menu, or a popped-out edge menu, with `draggable` on
  function canDrag(menu, poppedOut) {
    if (!menu?.draggable)
      return false;
    return menu.placement === "free" || (menu.placement === "edge" && !!menu.popOutButton && !!poppedOut);
  }

  // Drawn under the popouts, never colliding (PopoutClaim.underlay): a
  // free menu pinned, or popped out (held as if pinned)
  function underlay(pinned, poppedOut) {
    return !!pinned || !!poppedOut;
  }

  // Which hosts a menu has loaded (surfaces/edgemenu/EdgeMenu): { edge,
  // strip, free }. Its placement's, but a popped-out edge menu shows in
  // the free host; its edge host stays until the free one has shown
  // (`freeShown`), so the box hands over with no gap
  function hosts(placement, poppedOut, freeShown) {
    const popped = placement === "edge" && !!poppedOut;
    return {
      "edge": placement === "edge" && (!popped || !freeShown),
      "strip": placement === "strip",
      "free": placement === "free" || popped
    };
  }
}
