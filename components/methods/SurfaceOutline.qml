pragma Singleton
import QtQuick

// The outline of a surface that grows out of an edge (AttachedSurface): a
// content box joined to the attach edge by two concave fillets, or a plain
// box held off it. One set of metrics, so the drawn shape, the footprint
// other surfaces collide with (PopoutGeometry) and the copies the blur
// window draws all agree.
//
// Edge-local coordinates: u runs along the attach edge, v away from it
// (v = 0 is the attach edge), laid out as if attached to the Top edge and
// mapped onto the real one by `toItem`. `edge` is a ScreenEdge. No files,
// services or config: the caller passes the shape's settings in a spec:
//   { edge, boxAlong, boxDepth, strokeWidth, filletRadius, cornerRadius,
//     startCornerRadius, endCornerRadius, connectorGap, joinStart,
//     joinEnd, flushStart, flushEnd, flushStartThrough, flushEndThrough,
//     detached, detachedOffset, backfill, straight, straightJoins,
//     straightJoinStart, straightJoinEnd, joinBackfill, steps }
// (straightJoinStart/End: one joined end's, where the edges it meets
// differ, a bare screen edge at one and a solid bar's stroke at the
// other; each defaults to straightJoins. joinBackfill: the row a surface
// covers past its joined ends (a submenu's, beside its parent's backfill),
// which a straight join's far wall runs on through. steps: segments
// stacked past the box's far side, out from the edge, each centred on
// it, `{ along, depth }` (its length, outer edge to outer edge, and how
// far its far side lies past the one before): a stepped outline, each
// one no longer than the one before (a longer one is cut to it), joined
// to it by a concave fillet where it's narrower; attached only)
QtObject {
  id: root

  // Everything derived from a spec, in edge-local coordinates
  function metrics(s) {
    const half = s.strokeWidth / 2;
    const R = s.filletRadius;
    const detached = !!s.detached;
    const back = detached ? 0 : (s.backfill ?? 0);
    const lead = detached ? (s.detachedOffset ?? 0) : 0;
    // A radius under half the stroke is too tight for a fillet: the walls
    // run straight into what they attach to
    const sharp = R < half;
    const filletStart = !sharp && !s.joinStart && !s.flushStart && !s.straight;
    const filletEnd = !sharp && !s.joinEnd && !s.flushEnd && !s.straight;
    const straightJoinStart = !!(s.straightJoinStart ?? s.straightJoins) || sharp;
    const straightJoinEnd = !!(s.straightJoinEnd ?? s.straightJoins) || sharp;
    const joinFillet = (!!s.joinStart && !straightJoinStart) || (!!s.joinEnd && !straightJoinEnd);
    // A fillet's room along the edge: its arc's run (EdgeAttach.filletMargin)
    const full = R - half;
    const startMargin = filletStart ? full : 0;
    const endMargin = filletEnd ? full : 0;
    const alongLength = startMargin + s.boxAlong + endMargin;
    const cs = s.startCornerRadius ?? s.cornerRadius;
    const ce = s.endCornerRadius ?? s.cornerRadius;
    let naturalBoxStart;
    if (detached) {
      naturalBoxStart = lead + s.connectorGap / 2;
    } else {
      const fillet = filletStart || filletEnd ? R + half : 0;
      naturalBoxStart = Math.max(0, Math.min(s.connectorGap / 2, fillet + Math.max(cs, ce) + half - s.boxDepth));
    }
    return withBoxStart(s, {
      "half": half,
      "back": back,
      "sharp": sharp,
      "filletStart": filletStart,
      "filletEnd": filletEnd,
      "straightJoins": straightJoinStart && straightJoinEnd,
      "straightJoinStart": straightJoinStart,
      "straightJoinEnd": straightJoinEnd,
      "joinFillet": joinFillet,
      "throughStart": !!s.flushStart && (s.flushStartThrough ?? true),
      "throughEnd": !!s.flushEnd && (s.flushEndThrough ?? true),
      // How far a straight joined end's far wall runs on past it, through
      // the row joinBackfill covers, into the stroke it joins (drawn beside
      // that row's fill, outside the outline): stopped at the end, it left
      // that row's pixel of wall open, a notch in the line
      "joinThroughStart": !!s.joinStart && straightJoinStart ? (s.joinBackfill ?? 0) : 0,
      "joinThroughEnd": !!s.joinEnd && straightJoinEnd ? (s.joinBackfill ?? 0) : 0,
      "startMargin": startMargin,
      "endMargin": endMargin,
      "alongLength": alongLength,
      "naturalBoxStart": naturalBoxStart,
      "sideU": startMargin + half,
      "farSideU": startMargin + s.boxAlong - half
    }, naturalBoxStart);
  }

  // The metrics with the box starting `boxStart` from the attach edge (a
  // bar's pills keep a half connector gap instead of the natural start).
  // Each far corner is capped at the room the box has, as a Rectangle's
  // radius is: past it, a wall would run backwards and the outline cross
  // itself. The radius never changes the box's size.
  function withBoxStart(s, m, boxStart) {
    const h = m.half, R = s.filletRadius;
    const along = Math.max(0, s.boxAlong / 2 - h);
    const room = filleted => Math.max(0, Math.min(along, boxStart + s.boxDepth - h - (filleted ? h + R : 0)));
    const out = Object.assign({}, m, {
      "startCornerRadius": Math.min(s.startCornerRadius ?? s.cornerRadius, room(m.filletStart)),
      "endCornerRadius": Math.min(s.endCornerRadius ?? s.cornerRadius, room(m.filletEnd)),
      "boxStart": boxStart,
      "farV": boxStart + s.boxDepth - m.half
    });
    out.levels = root._levels(s, out);
    const stepped = out.levels.length > 0 ? out.levels[out.levels.length - 1].v - out.farV : 0;
    out.depth = m.back + boxStart + s.boxDepth + stepped + s.connectorGap / 2 + (m.joinFillet ? s.filletRadius : 0);
    return out;
  }

  // The steps past the box (spec `steps`), as levels out from it: the box
  // first, then each step, its walls' centre lines `a` (start) and `b`
  // (end) and its far side's `v`. A step as long as the one before (or
  // within a pixel) only carries its walls on; at a narrower one the
  // corners: `c0`/`c1` the convex corner each end of the face before it,
  // `f` the concave fillet into its wall, each at most half the room the
  // step leaves; and the outermost face's corners, `cs`/`ce`. Steps all
  // as long as the box only deepen it (one level). None without steps,
  // detached, or with a joined end
  function _levels(s, m) {
    const steps = (s.steps ?? []).filter(step => step.depth > 0);
    if (steps.length === 0 || s.detached || s.joinStart || s.joinEnd)
      return [];
    const h = m.half, R = s.filletRadius;
    // A step's corners: the spec's, else the box's own (a host passes
    // its start and end ones)
    const cr = Math.max(0, s.cornerRadius ?? Math.max(s.startCornerRadius ?? 0, s.endCornerRadius ?? 0));
    const centre = m.startMargin + s.boxAlong / 2;
    const levels = [
      {
        "a": m.sideU,
        "b": m.farSideU,
        "v": m.farV,
        "depth": s.boxDepth,
        "cs": m.startCornerRadius,
        "ce": m.endCornerRadius
      }
    ];
    steps.forEach(step => {
      const last = levels[levels.length - 1];
      const half = Math.min(step.along, last.b - last.a + 2 * h) / 2;
      const a = centre - half + h;
      if (a - last.a < 1) {
        last.v += step.depth;
        last.depth += step.depth;
        return;
      }
      levels.push({
        "a": a,
        "b": centre + half - h,
        "v": last.v + step.depth,
        "depth": step.depth
      });
    });
    levels.forEach((level, i) => {
      if (i === 0)
        return;
      const corner = Math.max(0, Math.min(cr, level.depth / 2, (level.b - level.a) / 2));
      level.cs = corner;
      level.ce = corner;
    });
    levels.forEach((level, i) => {
      if (i === 0)
        return;
      const before = levels[i - 1];
      const room = (level.a - before.a) / 2;
      level.c0 = Math.min(before.cs, room);
      level.c1 = Math.min(before.ce, room);
      level.f = Math.max(0, Math.min(R, room, level.depth / 2));
    });
    return levels;
  }

  // The outline's far side from the start wall (at the box's far corner)
  // to the end wall: the box's far corners, or with steps, out along each
  // step's walls and faces and back
  function _farStart(m, p, cs) {
    const L = m.levels ?? [];
    if (L.length === 0)
      return p.arc(cs, false, m.sideU + cs, m.farV);
    let d = "";
    for (let k = 1; k < L.length; k++) {
      const before = L[k - 1], step = L[k];
      // (the box's wall already runs up to its own corner)
      if (k > 1 || step.c0 !== cs)
        d += p.line(before.a, before.v - step.c0);
      d += p.arc(step.c0, false, before.a + step.c0, before.v);
      // (none where the two arcs meet: a line going nowhere spikes a
      // mitred stroke)
      if (step.a - step.f - (before.a + step.c0) > 0.01)
        d += p.line(step.a - step.f, before.v);
      d += p.arc(step.f, true, step.a, before.v + step.f);
    }
    const out = L[L.length - 1];
    d += p.line(out.a, out.v - out.cs);
    d += p.arc(out.cs, false, out.a + out.cs, out.v);
    return d;
  }
  function _farEnd(m, p, ce) {
    const L = m.levels ?? [];
    if (L.length === 0)
      return p.line(m.farSideU - ce, m.farV) + p.arc(ce, false, m.farSideU, m.farV - ce);
    const out = L[L.length - 1];
    let d = p.line(out.b - out.ce, out.v) + p.arc(out.ce, false, out.b, out.v - out.ce);
    for (let k = L.length - 1; k > 0; k--) {
      const before = L[k - 1], step = L[k];
      d += p.line(step.b, before.v + step.f);
      d += p.arc(step.f, true, step.b + step.f, before.v);
      if (before.b - step.c1 - (step.b + step.f) > 0.01)
        d += p.line(before.b - step.c1, before.v);
      d += p.arc(step.c1, false, before.b, before.v - step.c1);
    }
    return d;
  }

  // An edge-local point in the item's coordinates (`w`/`h` its size)
  function toItem(edge, w, h, back, u, v) {
    switch (edge) {
    case ScreenEdge.Left:
      return {
        "x": v + back,
        "y": u
      };
    case ScreenEdge.Right:
      return {
        "x": w - v - back,
        "y": u
      };
    case ScreenEdge.Bottom:
      return {
        "x": u,
        "y": h - v - back
      };
    default:
      return {
        "x": u,
        "y": v + back
      };
    }
  }

  // An edge-local rect (u, v, along, deep) in the item's coordinates
  function rectFrom(edge, w, h, back, u, v, along, deep) {
    const a = toItem(edge, w, h, back, u, v);
    const b = toItem(edge, w, h, back, u + along, v + deep);
    return {
      "x": Math.min(a.x, b.x),
      "y": Math.min(a.y, b.y),
      "width": Math.abs(b.x - a.x),
      "height": Math.abs(b.y - a.y)
    };
  }

  // The content box at rest, in the item's coordinates
  function boxRect(s, m, w, h) {
    return rectFrom(s.edge, w, h, m.back, m.startMargin, m.boxStart, s.boxAlong, s.boxDepth);
  }

  // A path-building context: SVG pieces from edge-local points. The sweep
  // flag is for the arc as drawn on the Top edge (y down); reflections
  // (bottom, left) flip it.
  function _pen(s, m, w, h) {
    const mirrored = s.edge === ScreenEdge.Bottom || s.edge === ScreenEdge.Left;
    const pt = (u, v) => {
      const p = toItem(s.edge, w, h, m.back, u, v);
      return p.x + " " + p.y;
    };
    return {
      "move": (u, v) => "M " + pt(u, v) + " ",
      "line": (u, v) => "L " + pt(u, v) + " ",
      "arc": (r, clockwise, u, v) => "A " + r + " " + r + " 0 0 " + ((clockwise !== mirrored) ? 1 : 0) + " " + pt(u, v) + " "
    };
  }

  // The outline from the start end to the end end: side walls (or joins)
  // and the far edge, shared by the fill and the stroke. `startWith(u, v)`
  // begins it (a move, or a line continuing the fill). A joined end's
  // fillet runs from `joinV` (default: where it meets the stroke it joins,
  // farV + R) along its own arc.
  function _outline(s, m, p, startWith, joinV, capInset) {
    const R = s.filletRadius, cs = m.startCornerRadius, ce = m.endCornerRadius, h = m.half;
    const sideU = m.sideU, farSideU = m.farSideU, farV = m.farV, L = m.alongLength;
    const jv = joinV ?? farV + R;
    // How far in from the end the fillet's arc is at jv
    const ju = h + R - Math.sqrt(Math.max(0, R * R - (farV + R - jv) * (farV + R - jv)));
    // An attach-side fillet's line along the edge starts `ci` in from the
    // end, or its arc does where it reaches that far (`du` past the arc's
    // end on the edge)
    const ci = capInset ?? 0;
    const arcV = du => h + R - Math.sqrt(Math.max(0, R * R - du * du));
    // A flush wall runs on through the backfill, its stroke covering the
    // end of the stroke it continues there, which the backfill leaves open
    const fv0 = m.throughStart ? -m.back : 0, fv1 = m.throughEnd ? -m.back : 0;
    let d = "";
    if (s.joinStart && m.straightJoinStart) {
      d += startWith(0, farV);
    } else if (s.joinStart) {
      d += startWith(ju, jv);
      d += p.arc(R, true, h + R, farV);
    } else if (!m.filletStart) {
      d += startWith(sideU, fv0);
      d += p.line(sideU, farV - cs);
      d += root._farStart(m, p, cs);
    } else {
      if (sideU - R >= ci) {
        d += startWith(ci, h);
        d += p.line(sideU - R, h);
      } else {
        d += startWith(ci, arcV(ci - (sideU - R)));
      }
      d += p.arc(R, true, sideU, h + R);
      d += p.line(sideU, farV - cs);
      d += root._farStart(m, p, cs);
    }
    if (s.joinEnd && m.straightJoinEnd) {
      d += p.line(L, farV);
    } else if (s.joinEnd) {
      d += p.line(L - h - R, farV);
      d += p.arc(R, true, L - ju, jv);
    } else if (!m.filletEnd) {
      d += root._farEnd(m, p, ce);
      d += p.line(farSideU, fv1);
    } else {
      d += root._farEnd(m, p, ce);
      d += p.line(farSideU, h + R);
      if (farSideU + R <= L - ci) {
        d += p.arc(R, true, farSideU + R, h);
        d += p.line(L - ci, h);
      } else {
        d += p.arc(R, true, L - ci, arcV(farSideU + R - (L - ci)));
      }
    }
    return d;
  }

  // Fill: the outline, closed back along the attach edge (and behind it by
  // the backfill). Joined ends also cover the perpendicular stroke up to
  // the fillet: a pixel short of where it meets that stroke, which the
  // fillet's stroke covers there, the fillet's edge leaving its arc there
  // too. A filleted end's fill along the attach edge stops a pixel short
  // of its end likewise. Wherever a stroke ends with a flat cap on another
  // surface's stroke, the fill reaching that cap (or a sliver of it running
  // down beside the arc to it) showed through the cap's anti-aliased edge
  // as a dark notch in the stroke it meets.
  function fillPath(s, m, w, h) {
    if (w <= 0 || h <= 0)
      return "";
    const p = _pen(s, m, w, h);
    const R = s.filletRadius, b = -m.back, L = m.alongLength;
    const joinV = m.farV + R - 1;
    // The backfill stops short of a flush end's wall, squarely, where the
    // stroke of what it attaches to carries on behind it
    const u0 = m.throughStart ? s.strokeWidth : 0, u1 = m.throughEnd ? L - s.strokeWidth : L;
    let d;
    if (s.joinStart)
      d = p.move(0, b) + p.line(0, m.straightJoinStart ? m.farV : joinV) + _outline(s, m, p, p.line, joinV, 1);
    else if (s.flushStart)
      d = p.move(u0, b) + (m.throughStart ? "" : p.line(0, 0)) + _outline(s, m, p, p.line, joinV, 1);
    else if (!m.filletStart)
      d = _outline(s, m, p, p.move, joinV, 1);
    else
      d = _outline(s, m, p, (u, v) => p.move(u, 0) + p.line(u, v), joinV, 1);
    if (s.joinEnd && !m.straightJoinEnd)
      d += p.line(L, joinV);
    else if (!s.joinEnd && m.filletEnd)
      d += p.line(L - 1, 0);
    else if (s.flushEnd && !m.throughEnd)
      d += p.line(L, 0);
    return d + p.line(u1, b) + p.line(u0, b) + "Z";
  }

  // Stroke: the outline alone, open along the attach edge and on joined
  // ends, whose ends sit exactly on the strokes they continue
  function strokePath(s, m, w, h) {
    if (w <= 0 || h <= 0)
      return "";
    const p = _pen(s, m, w, h);
    return _outline(s, m, p, p.move);
  }

  // What the surface covers, as rects in the item's coordinates: the box,
  // the fillets beside it at the attach edge (their whole squares), a
  // joined end's fillet past the far edge, and the backfill row behind the
  // attach edge. Detached, the box alone (its corners as square: a
  // touch of a corner's curve counts). Other surfaces overlapping any
  // of them collide with it (PopoutGeometry).
  function footprint(s, m, w, h) {
    const R = s.filletRadius, back = m.back;
    const rect = (u, v, along, deep) => rectFrom(s.edge, w, h, back, u, v, along, deep);
    if (s.detached)
      return [boxRect(s, m, w, h)];
    // Attached, the box reaches back to the attach edge
    const levels = m.levels ?? [];
    const deeper = levels.length > 0 ? levels[0].v - m.farV : 0;
    const out = [rect(m.startMargin, 0, s.boxAlong, m.boxStart + s.boxDepth + deeper)];
    const filletDeep = R + m.half;
    if (m.filletStart && m.startMargin > 0)
      out.push(rect(0, 0, m.startMargin, filletDeep));
    if (m.filletEnd && m.endMargin > 0)
      out.push(rect(m.startMargin + s.boxAlong, 0, m.endMargin, filletDeep));
    if (s.joinStart && !m.straightJoinStart)
      out.push(rect(0, m.farV, m.half + R, R + m.half));
    if (s.joinEnd && !m.straightJoinEnd)
      out.push(rect(m.alongLength - m.half - R, m.farV, m.half + R, R + m.half));
    if (back > 0)
      out.push(rect(0, -back, m.alongLength, back));
    // Each step past the box
    levels.forEach((level, i) => {
      if (i > 0)
        out.push(rect(level.a - m.half, m.levels[i - 1].v, level.b - level.a + 2 * m.half, level.v - m.levels[i - 1].v + m.half));
    });
    return out.filter(r => r.width > 0 && r.height > 0);
  }

  /**
   * The fill as a blur region, for a compositor that blurs only what a
   * window asks (supports.blurRegion): pieces in the item's coordinates,
   * out to the stroke's outer edge, slid by `dx`/`dy` and cut to the item
   * (as the slide clips it). Each piece is a rect { x, y, width, height,
   * topLeft, topRight, bottomLeft, bottomRight (corner radii), cuts }, its
   * `cuts` taken out of it alone ({ x, y, width, height, ellipse, radius }:
   * a concave fillet's circle). Detached, the box with its far corners
   * rounded as drawn and its near ones `near` ({ start, end }).
   */
  function blurRegion(s, m, w, h, dx, dy, near) {
    const R = s.filletRadius, half = m.half, L = m.alongLength, back = m.back;
    const outer = r => r > 0 ? r + half : 0;
    const far = m.farV + half;
    // Edge-local pieces: u, v, along, deep, corner radii (start/end, far/
    // near) and circles cut out ({ u, v, r }: the centre)
    const pieces = [];
    if (s.detached) {
      pieces.push({
        "u": m.startMargin,
        "v": m.boxStart,
        "along": s.boxAlong,
        "deep": s.boxDepth,
        "startFar": outer(m.startCornerRadius),
        "endFar": outer(m.endCornerRadius),
        "startNear": near?.start ?? 0,
        "endNear": near?.end ?? 0
      });
    } else {
      // The box, back to the backfill's far side
      const u0 = m.filletStart ? m.startMargin : 0, u1 = m.filletEnd ? L - m.endMargin : L;
      const levels = m.levels ?? [];
      pieces.push({
        "u": u0,
        "v": -back,
        "along": u1 - u0,
        "deep": back + (levels.length > 0 ? levels[0].v + half : far),
        "startFar": s.joinStart ? 0 : outer(levels.length > 1 ? levels[1].c0 : m.startCornerRadius),
        "endFar": s.joinEnd ? 0 : outer(levels.length > 1 ? levels[1].c1 : m.endCornerRadius)
      });
      // Each step past it (overlapping the face before it, under its
      // stroke), its far corners those of the face it meets next, and
      // the concave fillets at its foot: their squares less the circle
      // beyond their arc
      levels.forEach((level, i) => {
        if (i === 0)
          return;
        const before = levels[i - 1], next = levels[i + 1];
        pieces.push({
          "u": level.a - half,
          "v": before.v - half,
          "along": level.b - level.a + 2 * half,
          "deep": level.v - before.v + 2 * half,
          "startFar": outer(next ? next.c0 : level.cs),
          "endFar": outer(next ? next.c1 : level.ce)
        });
        if (level.f > half) {
          pieces.push({
            "u": level.a - level.f,
            "v": before.v,
            "along": level.f - half,
            "deep": level.f,
            "cuts": [
              {
                "u": level.a - level.f,
                "v": before.v + level.f,
                "r": level.f - half
              }
            ]
          });
          pieces.push({
            "u": level.b + half,
            "v": before.v,
            "along": level.f - half,
            "deep": level.f,
            "cuts": [
              {
                "u": level.b + level.f,
                "v": before.v + level.f,
                "r": level.f - half
              }
            ]
          });
        }
      });
      if (back > 0)
        pieces.push({
          "u": 0,
          "v": -back,
          "along": L,
          "deep": back
        });
      // The attach edge's fillets: their squares less the circle beyond
      // their arc (out to the stroke's outer side, towards its centre)
      if (m.filletStart && m.startMargin > 0)
        pieces.push({
          "u": 0,
          "v": 0,
          "along": m.startMargin,
          "deep": half + R,
          "cuts": [
            {
              "u": 0,
              "v": half + R,
              "r": R - half
            }
          ]
        });
      if (m.filletEnd && m.endMargin > 0)
        pieces.push({
          "u": L - m.endMargin,
          "v": 0,
          "along": m.endMargin,
          "deep": half + R,
          "cuts": [
            {
              "u": L,
              "v": half + R,
              "r": R - half
            }
          ]
        });
      // A joined end's fillet curving from the far wall into what it joins
      if (s.joinStart && !m.straightJoinStart)
        pieces.push({
          "u": 0,
          "v": m.farV,
          "along": half + R,
          "deep": R,
          "cuts": [
            {
              "u": half + R,
              "v": m.farV + R,
              "r": R - half
            }
          ]
        });
      if (s.joinEnd && !m.straightJoinEnd)
        pieces.push({
          "u": L - half - R,
          "v": m.farV,
          "along": half + R,
          "deep": R,
          "cuts": [
            {
              "u": L - half - R,
              "v": m.farV + R,
              "r": R - half
            }
          ]
        });
    }
    const out = pieces.filter(p => p.along > 0 && p.deep > 0).map(p => {
      const r = rectFrom(s.edge, w, h, back, p.u, p.v, p.along, p.deep);
      const piece = Object.assign({}, r, {
        "topLeft": 0,
        "topRight": 0,
        "bottomLeft": 0,
        "bottomRight": 0,
        "cuts": (p.cuts ?? []).filter(c => c.r > 0).map(c => {
          const at = toItem(s.edge, w, h, back, c.u, c.v);
          return {
            "x": at.x - c.r,
            "y": at.y - c.r,
            "width": c.r * 2,
            "height": c.r * 2,
            "ellipse": true,
            "radius": 0
          };
        })
      });
      // Each corner's radius onto the item corner it lands on
      const corner = (u, v, radius) => {
        if (!(radius > 0))
          return;
        const at = toItem(s.edge, w, h, back, u, v);
        const left = Math.abs(at.x - r.x) < Math.abs(at.x - (r.x + r.width));
        const top = Math.abs(at.y - r.y) < Math.abs(at.y - (r.y + r.height));
        piece[(top ? "top" : "bottom") + (left ? "Left" : "Right")] = radius;
      };
      corner(p.u, p.v + p.deep, p.startFar);
      corner(p.u + p.along, p.v + p.deep, p.endFar);
      corner(p.u, p.v, p.startNear);
      corner(p.u + p.along, p.v, p.endNear);
      return piece;
    });
    return placeRegion(out, dx ?? 0, dy ?? 0, {
      "x": 0,
      "y": 0,
      "width": w,
      "height": h
    });
  }

  /**
   * Blur region pieces (blurRegion's) moved by `dx`/`dy` and cut to `clip`
   * ({ x, y, width, height }, null for none), in whole pixels (a region's):
   * a piece cut short keeps its corners' radii, no bigger than it is.
   */
  function placeRegion(pieces, dx, dy, clip) {
    const out = [];
    for (const p of pieces) {
      let x0 = p.x + dx, y0 = p.y + dy, x1 = x0 + p.width, y1 = y0 + p.height;
      if (clip) {
        x0 = Math.max(x0, clip.x);
        y0 = Math.max(y0, clip.y);
        x1 = Math.min(x1, clip.x + clip.width);
        y1 = Math.min(y1, clip.y + clip.height);
      }
      x0 = Math.floor(x0);
      y0 = Math.floor(y0);
      x1 = Math.ceil(x1);
      y1 = Math.ceil(y1);
      if (x1 <= x0 || y1 <= y0)
        continue;
      const most = Math.floor(Math.min(x1 - x0, y1 - y0) / 2);
      const radius = r => Math.min(most, Math.round(r ?? 0));
      out.push({
        "x": x0,
        "y": y0,
        "width": x1 - x0,
        "height": y1 - y0,
        "topLeft": radius(p.topLeft),
        "topRight": radius(p.topRight),
        "bottomLeft": radius(p.bottomLeft),
        "bottomRight": radius(p.bottomRight),
        "cuts": (p.cuts ?? []).map(c => ({
              "x": Math.round(c.x + dx),
              "y": Math.round(c.y + dy),
              "width": Math.round(c.width),
              "height": Math.round(c.height),
              "ellipse": c.ellipse === true,
              "radius": Math.round(c.radius ?? 0)
            }))
      });
    }
    return out;
  }
}
