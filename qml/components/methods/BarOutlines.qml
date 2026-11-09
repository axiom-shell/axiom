pragma Singleton
import QtQuick

// Outlines of bar widget backgrounds as SVG paths, from one outline spec
// (BarShapes.outline: its length, thickness, radius, caps, seams, tab and
// open ends): the outline (path), a double outline's lines moved in
// (offsetPath), a dash pattern's halves (dashPath), Ends only's marks
// (marks) and a flared tab's fillets (fillets). Caps' points are
// BarShapes', a tab's sides BarTabs'.
QtObject {
  id: root

  // The outline of a background (outline spec `o`, BarShapes.outline) as
  // an SVG path in its item's coordinates. `inset` shrinks it all round,
  // so an outline's stroke stays inside, except at a seam (`seamStart`/
  // `seamEnd`), where it meets a powerline neighbour and both strokes lie
  // on the shared edge; caps keep their depth for the full thickness, so
  // neighbours' edges still meet. A tab's (`tab`) is its own: see
  // _tabPath. An open end (`openStart`/`openEnd`) keeps no inset there
  // either, so the two meet; `open` (a stroke's path) leaves the line
  // across it out, so no divider shows where they meet, and a tab's outer
  // edge too.
  function path(o, inset, open) {
    if (o.tab)
      return root._tabPath(o, inset, open === true, 0);
    const length = o.length, across = o.across;
    const h = Math.max(0, across - inset * 2);
    const r = Math.min(o.radius, h / 2);
    const along0 = o.seamStart || o.openStart ? 0 : inset, along1 = o.seamEnd || o.openEnd ? 0 : inset;
    const shift = along => q => Object.assign({}, q, {
          "x": along + q.x,
          "y": inset + q.y
        });
    const head = BarShapes.capPoints(o.startCap, true, h, BarShapes.depth(o.startCap, across), r).map(shift(along0));
    const tail = BarShapes.capPoints(o.endCap, false, h, BarShapes.depth(o.endCap, across), r).map(shift(along1));
    return root._outline(length, head, tail, o.vertical, open === true && o.openStart, open === true && o.openEnd);
  }

  // The outline of a background (path's, for outline spec `o`), its line
  // moved `inset` in all
  // round, square to every edge (a double outline's lines): a slant's or
  // an arrow's side stays parallel to the shape's, a round corner keeps
  // its centre. `alongStart`/`alongEnd` move the caps' lines by a
  // different amount (0 at a powerline seam, where the line lies on the
  // shared edge). Empty when the inset leaves no room.
  // A tab's (`tab`) is open along its outer edge, as its outline is, and
  // any at an open end (`openStart`/`openEnd`), whose lines run right to
  // it. The spec's seams are left to `alongStart`/`alongEnd`.
  function offsetPath(o, inset, alongStart, alongEnd) {
    if (o.tab)
      return root._tabPath(o, inset, true, inset);
    if (o.across - inset * 2 <= 0)
      return "";
    const head = root._offsetCap(o.startCap, true, o.across, o.radius, inset, o.openStart ? 0 : alongStart);
    const tail = root._offsetCap(o.endCap, false, o.across, o.radius, inset, o.openEnd ? 0 : alongEnd);
    return root._outline(o.length, head, tail, o.vertical, o.openStart, o.openEnd);
  }

  // An outline for a dash pattern to run along (path's for outline spec
  // `o` at `inset`, as open paths):
  // halves mirroring each other, each from the middle of the long sides
  // out round its own end, so a dash pattern started the same way on both
  // (OutlineStroke centres a dash on their start) meets each end alike,
  // wherever the outline would start. The start's half runs from the
  // middle of the side at the top (in item coordinates; the left on a
  // vertical bar) round the start cap to the middle of the other side,
  // the end's likewise; at an open end, the two sides alone, each from
  // its middle out. A tab's sides run from the middle of its inner side
  // out to the edge it hangs from, a flared one's to its fillets, which
  // are drawn solid apart (fillets): a dash pattern can't match on them.
  function dashPath(o, inset) {
    if (o.tab)
      return root._tabDashPath(o, inset);
    const length = o.length, across = o.across;
    const h = Math.max(0, across - inset * 2);
    const r = Math.min(o.radius, h / 2);
    const along0 = o.seamStart || o.openStart ? 0 : inset, along1 = o.seamEnd || o.openEnd ? 0 : inset;
    const shift = along => q => Object.assign({}, q, {
          "x": along + q.x,
          "y": inset + q.y
        });
    const head = BarShapes.capPoints(o.startCap, true, h, BarShapes.depth(o.startCap, across), r).map(shift(along0));
    const tail = BarShapes.capPoints(o.endCap, false, h, BarShapes.depth(o.endCap, across), r).map(shift(along1));
    const pen = root._pen(length, o.vertical);
    const top = [(head[0].x + length - tail[0].x) / 2, head[0].y];
    const bottom = [(head[head.length - 1].x + length - tail[tail.length - 1].x) / 2, head[head.length - 1].y];
    // Each end's half: down its cap's points (the start's arcs mirrored,
    // as marks has them), or its two sides alone where it's open
    const half = (pts, place, atStart, open) => {
      if (open)
        return `M ${pen.pt(top)} ` + pen.to(place(pts[0])) + `M ${pen.pt(bottom)} ` + pen.to(place(pts[pts.length - 1]));
      let d = `M ${pen.pt(top)} ` + pen.to(place(pts[0]));
      for (let k = 1; k < pts.length; k++) {
        const arc = pts[k].arc && atStart ? Object.assign({}, pts[k].arc, {
          "sweep": 1 - pts[k].arc.sweep
        }) : pts[k].arc;
        d += pen.to(place(pts[k]), arc);
      }
      return d + pen.to(bottom);
    };
    return (half(head, pen.atStart, true, o.openStart) + half(tail, pen.atEnd, false, o.openEnd)).trim();
  }

  // An outline at its ends only (outlineStroke `ends`), as open SVG paths
  // over path's outline (outline spec `o`) at `inset`: each cap's line with arms a quarter of
  // the thickness along the bar from its two corners, so it reads as a
  // bracket (round or flat `[ ]`, a slant's, an arrow's), but a capsule's
  // `( )` (and a powerline's half circles) alone. At a seam the cap before draws
  // the one mark (`seamStart` leaves the start out, and puts no inset on
  // the end there).
  // A tab's (`tab`): its two sides, open at the edge it hangs from
  // (_tabMarks). An open end (`openStart`/`openEnd`) has no mark: the run
  // carries on past it.
  function marks(o, inset) {
    if (o.tab)
      return root._tabMarks(o, inset, o.tab.thickness / 4);
    const across = o.across, radius = o.radius;
    const pen = root._pen(o.length, o.vertical);
    const arm = across / 4;
    // Brackets: every mark but a capsule's or a half circle's has arms
    const armed = cap => ["round", "flat", "slant", "arrowOut", "arrowIn"].includes(cap);
    // The mark down one end, top to bottom: each arc is the one into the
    // point it reaches, as drawn at the end; down the start, mirrored, it
    // sweeps the other way
    const mark = (cap, atStart, seam) => {
      const pts = root._offsetCap(cap, atStart, across, radius, inset, seam ? 0 : inset);
      const place = atStart ? pen.atStart : pen.atEnd;
      const first = pts[0], last = pts[pts.length - 1];
      let d = "M " + pen.pt(place(armed(cap) ? {
        "x": first.x + arm,
        "y": first.y
      } : first)) + " ";
      if (armed(cap))
        d += pen.to(place(first));
      for (let k = 1; k < pts.length; k++) {
        const arc = pts[k].arc && atStart ? Object.assign({}, pts[k].arc, {
          "sweep": 1 - pts[k].arc.sweep
        }) : pts[k].arc;
        d += pen.to(place(pts[k]), arc);
      }
      if (armed(cap))
        d += pen.to(place({
          "x": last.x + arm,
          "y": last.y
        }));
      return d;
    };
    return (o.seamStart || o.openStart ? "" : mark(o.startCap, true, false)) + (o.openEnd ? "" : mark(o.endCap, false, o.seamEnd));
  }

  // A flared tab's fillets alone (dashPath's other part) in outline spec
  // `o` at `inset`, from the edge it hangs from in to each side, as open
  // paths: "" with none (no tab, square, or an end held by a corner's
  // curve or open)
  function fillets(o, inset) {
    if (!o.tab)
      return "";
    const t = BarTabs.sides(o, inset, 0);
    const fillet = (pts, atEnd) => `M ${t.at(pts[0], atEnd)} ` + t.to(pts[1], atEnd, pts[1].arc, true);
    return ((t.headFillet && !o.openStart ? fillet(t.head, false) : "") + (t.tailFillet && !o.openEnd ? fillet(t.tail, true) : "")).trim();
  }

  // A tab's outline (path with a `tab`): along its start side from the
  // outer edge in, along its inner side, back out along its end side,
  // then closed along the outer edge, or left open there (`open`, an
  // outline: a tab has no line along the edge it hangs from). Its outer
  // side keeps no inset, so a stroke runs right to that edge. `grow`:
  // BarTabs.sides'. Left open, an open end (the spec's `openStart`/
  // `openEnd`) has no side: the line runs along the inner side to it.
  function _tabPath(o, inset, open, grow) {
    const t = BarTabs.sides(o, inset, grow);
    const head = t.head, tail = t.tail;
    const skipHead = open && o.openStart, skipTail = open && o.openEnd;
    let d = `M ${t.at(head[skipHead ? head.length - 1 : 0], false)} `;
    for (let k = 1; k < head.length && !skipHead; k++)
      d += t.to(head[k], false, head[k].arc, true);
    d += t.to(tail[tail.length - 1], true, null, false);
    for (let k = tail.length - 2; k >= 0 && !skipTail; k--)
      d += t.to(tail[k], true, tail[k + 1].arc, false);
    return open ? d.trim() : d + "Z";
  }

  // A tab's Ends only marks (marks with a `tab`): each side from the outer
  // edge in, round its inner corner and an arm `arm` along the inner side
  // (a `[ ]` open at the edge it hangs from), none at an open end
  function _tabMarks(o, inset, arm) {
    const t = BarTabs.sides(o, inset, 0);
    const mark = (pts, atEnd) => {
      const last = pts[pts.length - 1];
      let d = `M ${t.at(pts[0], atEnd)} `;
      for (let k = 1; k < pts.length; k++)
        d += t.to(pts[k], atEnd, pts[k].arc, true);
      return d + t.to({
        "x": last.x + arm,
        "y": last.y
      }, atEnd, null, true);
    };
    return (o.openStart ? "" : mark(t.head, false)) + (o.openEnd ? "" : mark(t.tail, true));
  }

  // A tab's dashed outline (dashPath with a `tab`): each side from the
  // middle of the inner side out, round its inner corner and up to the
  // edge it hangs from, or to its fillet, which `fillets` draws solid
  function _tabDashPath(o, inset) {
    const t = BarTabs.sides(o, inset, 0);
    const half = (pts, atEnd, open, fillet) => {
      const last = pts.length - 1;
      let d = `M ${t.at({
        "x": t.room / 2,
        "y": pts[last].y
      }, false)} ` + t.to(pts[last], atEnd, null, false);
      for (let k = last - 1; k >= (fillet ? 1 : 0) && !open; k--)
        d += t.to(pts[k], atEnd, pts[k + 1].arc, false);
      return d;
    };
    return (half(t.head, false, o.openStart, t.headFillet) + half(t.tail, true, o.openEnd, t.tailFillet)).trim();
  }

  // A closed path from a start cap's and an end cap's points (capPoints', x
  // in from their own end, y across the whole thickness), or left open
  // at its start or end (`openStart`/`openEnd`): no line across that end,
  // only the long sides running to it
  function _outline(length, head, tail, vertical, openStart, openEnd) {
    const pen = root._pen(length, vertical);
    const first = pen.pt(pen.atStart(head[0])), last = pen.pt(pen.atStart(head[head.length - 1]));
    if (openStart && openEnd)
      return `M ${first} ` + pen.to(pen.atEnd(tail[0])) + `M ${pen.pt(pen.atEnd(tail[tail.length - 1]))} ` + pen.to(pen.atStart(head[head.length - 1])).trim();
    if (openEnd) {
      // From the end's bottom corner, back up the start, to its top corner
      let d = `M ${pen.pt(pen.atEnd(tail[tail.length - 1]))} ` + `L ${last} `;
      for (let k = head.length - 2; k >= 0; k--)
        d += pen.to(pen.atStart(head[k]), head[k + 1].arc);
      return (d + pen.to(pen.atEnd(tail[0]))).trim();
    }
    let d = `M ${first} ` + pen.to(pen.atEnd(tail[0]));
    for (let k = 1; k < tail.length; k++)
      d += pen.to(pen.atEnd(tail[k]), tail[k].arc);
    d += pen.to(pen.atStart(head[head.length - 1]));
    if (openStart)
      return d.trim();
    // Back up the start: each step takes the arc that led into the point
    // it leaves (mirrored and reversed, so the sweep stays the same). A
    // straight last step back to the first point is the close's.
    for (let k = head.length - 2; k > 0 || (k === 0 && head[1].arc); k--)
      d += pen.to(pen.atStart(head[k]), head[k + 1].arc);
    return d + "Z";
  }

  // SVG steps for a background `length` long: a cap's point at the start
  // or the end as [along, across], and a line or arc to one
  function _pen(length, vertical) {
    // A vertical bar swaps the axes: a reflection, which flips arcs
    const pt = uv => vertical ? `${uv[1]} ${uv[0]}` : `${uv[0]} ${uv[1]}`;
    return {
      "pt": pt,
      "atStart": q => [q.x, q.y],
      "atEnd": q => [length - q.x, q.y],
      "to": (uv, arc) => arc ? `A ${arc.r} ${arc.r} 0 0 ${vertical ? 1 - arc.sweep : arc.sweep} ${pt(uv)} ` : `L ${pt(uv)} `
    };
  }

  // A cap's line moved in from the edge it outlines, as capPoints' (x
  // in from its end, y across the whole thickness `across`): `inset` in
  // from the long sides and `along` square to the cap's own edge, so a
  // slant or an arrow's line runs parallel to it (a double outline's
  // lines, an Ends only mark). A round cap's radius `r` shrinks by the
  // inset, a capsule's or a half circle's by what's square to it.
  function _offsetCap(cap, atStart, across, r, inset, along) {
    const p = (x, y, arc) => ({
          "x": x,
          "y": y,
          "arc": arc ?? null
        });
    const d = BarShapes.depth(cap, across);
    const half = across / 2;
    const bottom = across - inset;
    // How far along a line square to an edge `step` along per `rise`
    // across moves to lie `along` from it
    const shifted = (step, rise) => along * Math.sqrt(step * step + rise * rise) / rise;
    switch (cap) {
    case "round":
      {
        const rr = Math.max(0, Math.min(r - inset, half - inset));
        if (rr <= 0)
          return [p(along, inset), p(along, bottom)];
        return [p(along + rr, inset), p(along, inset + rr, {
            "r": rr,
            "sweep": 1
          }), p(along, bottom - rr), p(along + rr, bottom, {
            "r": rr,
            "sweep": 1
          })];
      }
    case "capsule":
      return [p(half, inset), p(half, bottom, {
          "r": half - inset,
          "sweep": 1
        })];
    case "arrowOut":
      {
        const a = shifted(d, half);
        const x = a + d * (half - inset) / half;
        return [p(x, inset), p(a, half), p(x, bottom)];
      }
    case "arrowIn":
      {
        const a = shifted(d, half);
        const x = a + d * inset / half;
        return [p(x, inset), p(a + d, half), p(x, bottom)];
      }
    case "slant":
      {
        const a = shifted(d, across);
        const at = y => a + d * (atStart ? 1 - y / across : y / across);
        return [p(at(inset), inset), p(at(bottom), bottom)];
      }
    case "roundOut":
      {
        // A half circle about (d, half), its radius less `along`
        const rr = half - along;
        const x = d - Math.sqrt(Math.max(0, rr * rr - (half - inset) * (half - inset)));
        return [p(x, inset), p(x, bottom, {
            "r": rr,
            "sweep": 1
          })];
      }
    case "roundIn":
      {
        // A half circle about (0, half), bowed in, its radius more `along`
        const rr = half + along;
        const x = Math.sqrt(Math.max(0, rr * rr - (half - inset) * (half - inset)));
        return [p(x, inset), p(x, bottom, {
            "r": rr,
            "sweep": 0
          })];
      }
    default:
      return [p(along, inset), p(along, bottom)];
    }
  }
}
