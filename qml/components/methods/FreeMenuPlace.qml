pragma Singleton
import QtQuick

// Where a free menu's box goes on its screen (surfaces/edgemenu/FreeMenu),
// and the side its slide comes in from. Pure: the host passes the screen,
// what's kept clear at each edge, the box, what opened it and its anchor.
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
  // Opened by a widget it sits at that widget: centred on it along its
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
    if (opener && root._edges.includes(opener.edge)) {
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
}
