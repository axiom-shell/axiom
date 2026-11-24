pragma Singleton
import QtQuick

// The screen border's frame (RoundedBorders) as geometry: the stroke's inner
// side round the corner arcs, the frame's fill, the corner pieces' boxes and
// the stroke holes under what joins the border. One set of rules, so the
// border, its corner pieces and the backing window's copy of it agree. No
// files, services or config: the caller passes `f` = { width, height (the
// screen), outerLeft, outerTop, outerRight, outerBottom, innerLeft,
// innerTop, innerRight, innerBottom, innerBorderRadius, strokeWidth } (screen
// px) and one screen's border openings ({ edge, start, end }).
QtObject {
  id: root

  // The corner's curve plus its stroke
  function cornerSize(f) {
    return f.innerBorderRadius + f.strokeWidth;
  }
  // The stroke's inner side, round the corner pieces' arcs, as an SVG
  // subpath in a window of w × h over the screen
  function innerPath(f, w, h) {
    const i = root._inner(f, w, h);
    const x0 = i.x0, y0 = i.y0, x1 = i.x1, y1 = i.y1, r = i.r;
    return `M ${x0 + r} ${y0} L ${x1 - r} ${y0} A ${r} ${r} 0 0 1 ${x1} ${y0 + r} L ${x1} ${y1 - r} A ${r} ${r} 0 0 1 ${x1 - r} ${y1} L ${x0 + r} ${y1} A ${r} ${r} 0 0 1 ${x0} ${y1 - r} L ${x0} ${y0 + r} A ${r} ${r} 0 0 1 ${x0 + r} ${y0} Z`;
  }
  // The stroke's inner side's edges and corner radius
  function _inner(f, w, h) {
    const x0 = f.innerLeft, y0 = f.innerTop, x1 = w - f.innerRight, y1 = h - f.innerBottom;
    const r = Math.max(0, Math.min(f.innerBorderRadius - f.strokeWidth, (x1 - x0) / 2, (y1 - y0) / 2));
    return {
      "x0": x0,
      "y0": y0,
      "x1": x1,
      "y1": y1,
      "r": r
    };
  }
  // The frame's fill as a blur region (SurfaceOutline.blurRegion's pieces): the screen inside the integrated menus' strips, less the stroke's inner side with its rounded corners (innerPath's radius)
  function blurRegion(f, w, h) {
    const i = root._inner(f, w, h);
    return [
      {
        "x": f.outerLeft,
        "y": f.outerTop,
        "width": w - f.outerRight - f.outerLeft,
        "height": h - f.outerBottom - f.outerTop,
        "cuts": [
          {
            "x": i.x0,
            "y": i.y0,
            "width": i.x1 - i.x0,
            "height": i.y1 - i.y0,
            "ellipse": false,
            "radius": i.r
          }
        ]
      }
    ];
  }
  // The frame, filled odd-even: from the window's edges, or from past the
  // integrated menus' strips (`fromMenus`, as the blur window fills it),
  // to innerPath
  function framePath(f, w, h, fromMenus) {
    const x0 = fromMenus ? f.outerLeft : 0, y0 = fromMenus ? f.outerTop : 0;
    const x1 = w - (fromMenus ? f.outerRight : 0), y1 = h - (fromMenus ? f.outerBottom : 0);
    return `M ${x0} ${y0} L ${x1} ${y0} L ${x1} ${y1} L ${x0} ${y1} Z ` + root.innerPath(f, w, h);
  }
  // Rect `r` (screen px) drawn as a non-anti-aliased Rectangle in a window
  // whose top-left is `origin` (screen px), as it fills on screen, in screen
  // px: the window sits on device px `Math.round(dpr × origin)`, and a pixel
  // is filled when its centre is in the rect, so an edge on a pixel's centre
  // (a .5 device px) takes that pixel at the start and leaves it at the end
  function strokePixels(r, origin, dpr) {
    const edge = (e, o) => (Math.round(dpr * o) + Math.ceil(dpr * (e - o) - 0.5)) / dpr;
    const x0 = edge(r.x, origin.x), y0 = edge(r.y, origin.y);
    return Qt.rect(x0, y0, edge(r.x + r.width, origin.x) - x0, edge(r.y + r.height, origin.y) - y0);
  }
  // A window's box `r` (screen px) as the compositor shows it: origin and
  // size on the nearest whole device px, in screen px (its buffer)
  function windowPixels(r, dpr) {
    return Qt.rect(Math.round(dpr * r.x) / dpr, Math.round(dpr * r.y) / dpr, Math.round(dpr * r.width) / dpr, Math.round(dpr * r.height) / dpr);
  }
  // A border strip's stroke in its own window (BorderPanel): on its screen-facing side, between the corner pieces, before openings; px
  function stripStroke(edge, length, frameWidth, innerBorderRadius, strokeWidth) {
    const horizontal = edge === "top" || edge === "bottom";
    const start = horizontal ? frameWidth + innerBorderRadius : innerBorderRadius;
    const across = edge === "top" || edge === "left" ? frameWidth - strokeWidth : 0;
    return horizontal ? Qt.rect(start, across, length - 2 * start, strokeWidth) : Qt.rect(across, start, strokeWidth, length - 2 * start);
  }
  // A corner piece's box on screen: where its stroke starts out from the
  // frame's inner side, past the integrated menus' strips
  // (cornerMargin is taken from what they reserve)
  function cornerBox(f, isLeft, isTop) {
    const size = root.cornerSize(f);
    const x = isLeft ? f.innerLeft - f.strokeWidth : f.width - f.innerRight + f.strokeWidth - size;
    const y = isTop ? f.innerTop - f.strokeWidth : f.height - f.innerBottom + f.strokeWidth - size;
    return Qt.rect(x, y, size, size);
  }
  // Whether opening `o` runs across the piece (at `at` along its edge) from
  // its stroke on, the piece being at the edge's start or not
  function _spans(f, o, at, atStart) {
    const size = root.cornerSize(f);
    return atStart ? o.start <= at + f.strokeWidth + 1 && o.end >= at + size : o.end >= at + size - f.strokeWidth - 1 && o.start <= at;
  }
  // Whether a border opening runs across a corner's piece, along the edge
  // the piece is on or the perpendicular one (a surface joined to the
  // stroke runs on into it): the piece is left open there
  function cornerCovered(f, openings, isLeft, isTop) {
    const box = root.cornerBox(f, isLeft, isTop);
    return openings.some(o => o.edge === (isTop ? "top" : "bottom") && root._spans(f, o, box.x, isLeft) || o.edge === (isLeft ? "left" : "right") && root._spans(f, o, box.y, isTop));
  }
  readonly property var corners: [
    {
      "isLeft": true,
      "isTop": true
    },
    {
      "isLeft": false,
      "isTop": true
    },
    {
      "isLeft": true,
      "isTop": false
    },
    {
      "isLeft": false,
      "isTop": false
    }
  ]
}
