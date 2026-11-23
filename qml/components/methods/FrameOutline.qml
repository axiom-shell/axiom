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
  // subpath in a window of w × h over the screen; or `out` px further out
  // (edges, and the radius with them: the corner pieces' own arc, which at
  // half a stroke is CornerPiece.arcRadius, the stroke's centre line)
  function innerPath(f, w, h, out) {
    const o = out ?? 0;
    const x0 = f.innerLeft - o, y0 = f.innerTop - o, x1 = w - f.innerRight + o, y1 = h - f.innerBottom + o;
    const r = Math.max(0, Math.min(f.innerBorderRadius - f.strokeWidth + o, (x1 - x0) / 2, (y1 - y0) / 2));
    return `M ${x0 + r} ${y0} L ${x1 - r} ${y0} A ${r} ${r} 0 0 1 ${x1} ${y0 + r} L ${x1} ${y1 - r} A ${r} ${r} 0 0 1 ${x1 - r} ${y1} L ${x0 + r} ${y1} A ${r} ${r} 0 0 1 ${x0} ${y1 - r} L ${x0} ${y0 + r} A ${r} ${r} 0 0 1 ${x0 + r} ${y0} Z`;
  }
  // The frame, filled odd-even: from the window's edges, or from past the
  // integrated menus' strips (`fromMenus`, as the blur window fills it),
  // to innerPath
  function framePath(f, w, h, fromMenus) {
    const x0 = fromMenus ? f.outerLeft : 0, y0 = fromMenus ? f.outerTop : 0;
    const x1 = w - (fromMenus ? f.outerRight : 0), y1 = h - (fromMenus ? f.outerBottom : 0);
    return `M ${x0} ${y0} L ${x1} ${y0} L ${x1} ${y1} L ${x0} ${y1} Z ` + root.innerPath(f, w, h);
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
  // Where the stroke is left open under what joins it (screen px, the
  // frame copy's coordinates, as AttachedSurface.strokeHoles): each border
  // opening's band, the stroke's rows along it with their anti-aliased
  // fringe a pixel either side (EdgeAttach.strokeHoleAcross), less the corner boxes
  // (where the strips' strokes stop: an arc no opening spans stays), and
  // each covered corner's box
  function strokeHoles(f, openings) {
    const w = f.width, h = f.height;
    const boxes = root.corners.map(c => root.cornerBox(f, c.isLeft, c.isTop));
    const bands = openings.map(o => {
      const sw = f.strokeWidth, length = o.end - o.start;
      switch (o.edge) {
      case "top":
        {
          const band = EdgeAttach.strokeHoleAcross(f.innerTop - sw, sw);
          return Qt.rect(o.start, band.start, length, band.size);
        }
      case "bottom":
        {
          const band = EdgeAttach.strokeHoleAcross(h - f.innerBottom, sw);
          return Qt.rect(o.start, band.start, length, band.size);
        }
      case "left":
        {
          const band = EdgeAttach.strokeHoleAcross(f.innerLeft - sw, sw);
          return Qt.rect(band.start, o.start, band.size, length);
        }
      default:
        {
          const band = EdgeAttach.strokeHoleAcross(w - f.innerRight, sw);
          return Qt.rect(band.start, o.start, band.size, length);
        }
      }
    });
    return [].concat(...bands.map(band => Utils.subtractRects(band, boxes)), root.corners.filter(c => root.cornerCovered(f, openings, c.isLeft, c.isTop)).map(c => root.cornerBox(f, c.isLeft, c.isTop)));
  }
}
