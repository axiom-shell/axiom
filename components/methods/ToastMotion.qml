pragma Singleton
import QtQuick

// How a stack of notification toasts moves (ToastStack): the edge its
// toasts slide in from and out to, which way it grows, where
// each toast sits, and how one leaves. Newest at the stack's start (its
// edge, or its end of the edge), pushing the rest along.
QtObject {
  id: root

  // The ScreenEdge a stack's toasts slide in from and out to. p:
  // { attached, edge (ScreenEdge), rect ({ x, y, width, height }, the
  // stack at rest on the screen), screenWidth, screenHeight, override
  // ("auto" or an edge name) }
  // - an override other than "auto" wins
  // - attached, its own edge: it grows out of it
  // - detached, the screen edge nearest the rect (bars play no part); a
  //   tie goes to its own edge, else to the sides before top and bottom
  function slideEdge(p) {
    const forced = ScreenEdge.fromName(p.override ?? "auto");
    if (forced >= 0)
      return forced;
    if (p.attached)
      return p.edge;
    const r = p.rect;
    const gaps = [r.y, p.screenHeight - (r.y + r.height), r.x, p.screenWidth - (r.x + r.width)];
    const least = Math.min(...gaps);
    if (gaps[p.edge] === least)
      return p.edge;
    for (const e of [ScreenEdge.Left, ScreenEdge.Right, ScreenEdge.Top, ScreenEdge.Bottom]) {
      if (gaps[e] === least)
        return e;
    }
    return p.edge;
  }

  // Which way a stack on `edge` at `position` (0-1 along it) grows, always
  // down or up the screen: { sign: 1 (down) | -1 (up) }. A top or bottom
  // stack grows away from its edge; a side one along it, away from its
  // nearer end (down from the middle)
  function growth(edge, position) {
    if (edge === ScreenEdge.Top)
      return {
        "sign": 1
      };
    if (edge === ScreenEdge.Bottom)
      return {
        "sign": -1
      };
    return {
      "sign": position > 0.5 ? -1 : 1
    };
  }

  // Where each toast sits along the stack, newest (index 0) first:
  // { offsets: [px from the stack's start], length (px, all of them) }
  function rows(heights, spacing) {
    const offsets = [];
    let at = 0;
    for (let i = 0; i < heights.length; i++) {
      offsets.push(at);
      at += heights[i] + (i < heights.length - 1 ? spacing : 0);
    }
    return {
      "offsets": offsets,
      "length": at
    };
  }

  // The shift ({ x, y }) that hides something `distance` px out through
  // `edge`
  function hiddenShift(edge, distance) {
    return [
      {
        "x": 0,
        "y": -distance
      },
      {
        "x": 0,
        "y": distance
      },
      {
        "x": -distance,
        "y": 0
      },
      {
        "x": distance,
        "y": 0
      }
    ][edge];
  }

  // How a toast leaves: { shift ({ x, y }), tuck }. The one at the stack's
  // start (index 0), or any whose slide crosses no other toast (sideways
  // out of the stack), slides all the way out (`distance`,
  // past the clip). One further along a stack sliding the way it grows
  // would pass behind the others: it tucks under them instead (`tuck`,
  // drawn beneath), sliding `size` / 2 toward the edge as it fades.
  function leave(index, slide, size, distance) {
    const along = slide === ScreenEdge.Top || slide === ScreenEdge.Bottom;
    if (index === 0 || !along)
      return {
        "shift": root.hiddenShift(slide, distance),
        "tuck": false
      };
    return {
      "shift": root.hiddenShift(slide, size / 2),
      "tuck": true
    };
  }
}
