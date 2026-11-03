pragma Singleton
import QtQuick

// The shapes bar widget backgrounds take (Bars[].widgetShape, a slanted or
// arrow widget's or run's ends by Bars[].widgetEnds), alone or in runs
// (Bars[].widgetGrouping): which cap each end of a widget gets, how
// much room its content keeps clear of them, and the outline as an SVG
// path. Lengths run along the bar, `across` is the widget's thickness.
//
// Caps: flat, round (the widget radius), capsule (half the thickness),
// arrowOut/arrowIn (a point or a notch), slant (a parallelogram's side),
// roundOut/roundIn (a half circle bulging out or in). Powerline segments
// overlap: each after the first reaches back under the one before it (or,
// when fills don't hide what's under them, meets its cap edge to edge).
QtObject {
  id: root

  // How far a cap reaches in along the bar
  function depth(cap, across) {
    switch (cap) {
    case "arrowOut":
    case "arrowIn":
    case "roundOut":
    case "roundIn":
      return across / 2;
    case "slant":
      return across / 3;
    default:
      return 0;
    }
  }

  // A run's own ends by shape, and a slant's or arrow's by widgetEnds
  // (shaped, pointed: an arrow's alone, rounded), [start, end] (a lone
  // widget's in separate)
  function _ends(shape, ends) {
    if (ends === "rounded" && (shape === "slant" || shape === "arrow"))
      return ["round", "round"];
    switch (shape) {
    case "capsule":
      return ["capsule", "capsule"];
    case "slant":
      return ["slant", "slant"];
    case "arrow":
      return ends === "pointed" ? ["arrowOut", "arrowOut"] : ["arrowIn", "arrowOut"];
    default:
      return ["round", "round"];
    }
  }

  // Where powerline segments meet: [the earlier one's end, the later one's
  // start when it meets that edge to edge]
  function _joins(shape) {
    switch (shape) {
    case "slant":
      return ["slant", "slant"];
    case "arrow":
      return ["arrowOut", "arrowIn"];
    default:
      return ["roundOut", "roundIn"];
    }
  }

  // Room content keeps clear of a run's end cap
  function _clearOf(cap, across) {
    switch (cap) {
    case "slant":
      return root.depth(cap, across) / 2;
    case "arrowOut":
    case "arrowIn":
      return root.depth(cap, across);
    default:
      return 0;
    }
  }

  // Widget `index` of a run of `count`: { startCap, endCap, shownStart,
  // back, lead, trail, seamStart, seamEnd }. `back` is how far its background reaches
  // back under the one before; `lead`/`trail` the room its content keeps
  // at each end. In a merged run only the run's ends have caps (the run is
  // one background). `opaque`: the fill hides what's under it, so a
  // powerline segment can start square beneath the one before instead of
  // fitting against it. `seamStart`/`seamEnd`: that end meets a
  // neighbour's edge to edge, so an outline there is drawn on the seam
  // (see path). `shownStart`: the start as it shows, where the cap before
  // covers a square start: the shape it's outlined and hit-tested in.
  //
  // A powerline segment shows from the cap before it, which reaches into
  // its first `join` px, to its own end cap: on average half a join
  // earlier than its box at each joined end. Its content keeps that much
  // more room at the end, so it sits centred on what shows.
  function segment(shape, widgetEnds, grouping, opaque, index, count, across) {
    const ends = root._ends(shape, widgetEnds);
    const joins = root._joins(shape);
    const alone = grouping === "separate";
    const first = alone || index === 0;
    const last = alone || index === count - 1;
    const powerline = grouping === "powerline";
    const join = root.depth(joins[0], across);
    const shift = powerline ? (first ? 0 : join / 2) + (last ? 0 : join / 2) : 0;
    return {
      "startCap": first ? ends[0] : powerline && !opaque ? joins[1] : "flat",
      "shownStart": first ? ends[0] : powerline ? joins[1] : "flat",
      "endCap": last ? ends[1] : powerline ? joins[0] : "flat",
      "back": !first && powerline ? join : 0,
      "lead": first ? root._clearOf(ends[0], across) : 0,
      "trail": (last ? root._clearOf(ends[1], across) : 0) + shift,
      "seamStart": !first && powerline && !opaque,
      "seamEnd": !last && powerline && !opaque
    };
  }

  // A cap's points down one end, top to bottom: { x, y, arc } with x in
  // from that end and arc { r, sweep } (sweep as drawn at the far end of
  // a horizontal bar) on the way into the point. A slant is the one cap
  // that differs at the start: a parallelogram leans the same way at both.
  function _cap(cap, atStart, h, d, r) {
    const p = (x, y, arc) => ({
          "x": x,
          "y": y,
          "arc": arc ?? null
        });
    switch (cap) {
    case "round":
      if (r <= 0)
        return [p(0, 0), p(0, h)];
      return [p(r, 0), p(0, r, {
          "r": r,
          "sweep": 1
        }), p(0, h - r), p(r, h, {
          "r": r,
          "sweep": 1
        })];
    case "capsule":
      return [p(h / 2, 0), p(h / 2, h, {
          "r": h / 2,
          "sweep": 1
        })];
    case "arrowOut":
      return [p(d, 0), p(0, h / 2), p(d, h)];
    case "arrowIn":
      return [p(0, 0), p(d, h / 2), p(0, h)];
    case "slant":
      return atStart ? [p(d, 0), p(0, h)] : [p(0, 0), p(d, h)];
    case "roundOut":
      return [p(d, 0), p(d, h, {
          "r": h / 2,
          "sweep": 1
        })];
    case "roundIn":
      return [p(0, 0), p(0, h, {
          "r": h / 2,
          "sweep": 0
        })];
    default:
      return [p(0, 0), p(0, h)];
    }
  }

  // The outline of a background `length` along the bar and `across` it,
  // as an SVG path in its item's coordinates (on a vertical bar the length
  // runs down). `inset` shrinks it all round, so an outline's stroke stays
  // inside, except at a seam (`seamStart`/`seamEnd`), where it meets a
  // powerline neighbour and both strokes lie on the shared edge; caps keep
  // their depth for the full thickness, so neighbours' edges still meet.
  function path(length, across, radius, startCap, endCap, vertical, inset, seamStart, seamEnd) {
    const h = Math.max(0, across - inset * 2);
    const r = Math.min(radius, h / 2);
    const head = root._cap(startCap, true, h, root.depth(startCap, across), r);
    const tail = root._cap(endCap, false, h, root.depth(endCap, across), r);
    const along0 = seamStart ? 0 : inset, along1 = seamEnd ? 0 : inset;
    const atStart = q => [along0 + q.x, inset + q.y];
    const atEnd = q => [length - along1 - q.x, inset + q.y];
    // A vertical bar swaps the axes: a reflection, which flips arcs
    const pt = uv => vertical ? `${uv[1]} ${uv[0]}` : `${uv[0]} ${uv[1]}`;
    const to = (uv, arc) => arc ? `A ${arc.r} ${arc.r} 0 0 ${vertical ? 1 - arc.sweep : arc.sweep} ${pt(uv)} ` : `L ${pt(uv)} `;

    let d = `M ${pt(atStart(head[0]))} ` + to(atEnd(tail[0]));
    for (let k = 1; k < tail.length; k++)
      d += to(atEnd(tail[k]), tail[k].arc);
    d += to(atStart(head[head.length - 1]));
    // Back up the start: each step takes the arc that led into the point
    // it leaves (mirrored and reversed, so the sweep stays the same). A
    // straight last step back to the first point is the close's.
    for (let k = head.length - 2; k > 0 || (k === 0 && head[1].arc); k--)
      d += to(atStart(head[k]), head[k + 1].arc);
    return d + "Z";
  }

  // How far in from its end a cap's edge lies at `v` across (0 to h)
  function _reach(cap, atStart, v, h) {
    const d = root.depth(cap, h);
    const r = h / 2;
    const off = Math.abs(v - r);
    const chord = Math.sqrt(Math.max(0, r * r - off * off));
    switch (cap) {
    case "slant":
      return atStart ? d * (1 - v / h) : d * v / h;
    case "arrowOut":
      return d * off / r;
    case "arrowIn":
      return d * (1 - off / r);
    case "roundOut":
    case "capsule":
      return r - chord;
    case "roundIn":
      return chord;
    default:
      return 0;
    }
  }

  // Whether a point `u` along and `v` across a background `length` by
  // `across` lies inside its caps (corners of round caps count as inside)
  function contains(u, v, length, across, startCap, endCap) {
    if (v < 0 || v > across || u < 0 || u > length)
      return false;
    return u >= root._reach(startCap, true, v, across) && u <= length - root._reach(endCap, false, v, across);
  }
}
