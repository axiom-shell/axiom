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
// roundOut/roundIn (a half circle bulging out or in), curve (a shallow
// arc bulging out: split's divider), tab (a tab's side: see tab and path).
// Powerline segments
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
    case "curve":
      return across / 4;
    default:
      return 0;
    }
  }

  // The cap a split widget's icon part ends in, where the label's part
  // starts (Bars[].splitDivider): match takes the shape's own (slanted,
  // an arrow), else straight
  function dividerCap(shape, divider) {
    switch (divider === "match" ? shape : divider) {
    case "slant":
      return "slant";
    case "arrow":
      return "arrowOut";
    case "curve":
      return "curve";
    default:
      return "flat";
    }
  }

  // The gap a split widget keeps between its icon part and its label:
  // joined, its padding either side of the divider (`cap`, dividerCap)
  // and the divider's depth; a badge (`icon` "badge") reaches `badgePad`
  // round the icon, then the usual `spacing`
  function splitRoom(icon, cap, across, padding, spacing, badgePad) {
    return icon === "badge" ? spacing + badgePad : padding * 2 + root.depth(cap, across);
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
    case "tab":
      return ["tab", "tab"];
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
  // levelStartCap, levelEndCap, back, lead, trail, seamStart, seamEnd }. `back` is how far its background reaches
  // back under the one before; `lead`/`trail` the room its content keeps
  // at each end. In a merged run only the run's ends have caps (the run is
  // one background). `opaque`: the fill hides what's under it, so a
  // powerline segment can start square beneath the one before instead of
  // fitting against it. `seamStart`/`seamEnd`: that end meets a
  // neighbour's edge to edge, so an outline there is drawn on the seam
  // (see path). `shownStart`: the start as it shows, where the cap before
  // covers a square start: the shape it's outlined and hit-tested in.
  // `levelStartCap`/`levelEndCap`: the caps a level (the pill style) is
  // drawn in: the widget's own, but in a merged run the ones it would have
  // alone, so a pill looks the same merged as separate.
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
    const startCap = first ? ends[0] : powerline && !opaque ? joins[1] : "flat";
    const endCap = last ? ends[1] : powerline ? joins[0] : "flat";
    const merged = grouping === "merged";
    return {
      "startCap": startCap,
      "shownStart": first ? ends[0] : powerline ? joins[1] : "flat",
      "endCap": endCap,
      "levelStartCap": merged ? ends[0] : startCap,
      "levelEndCap": merged ? ends[1] : endCap,
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
    case "curve":
      // An arc through both corners bulging `d` out at the middle
      return [p(d, 0), p(d, h, {
          "r": d > 0 ? (h * h / 4 + d * d) / (2 * d) : h,
          "sweep": 1
        })];
    default:
      return [p(0, 0), p(0, h)];
    }
  }

  // The one fillet radius every flared tab on a bar takes (tabCorners
  // flared; 0 square), on both sides, a run's ends included, so all its
  // tabs look alike: the inner corners' radius, but no more than half the
  // configured gap between widgets (`spacing`: two neighbours' fillets
  // then meet in it, never crossing) nor the room at the ends where a
  // fillet sits (`endRoom`, BarEnds.tabEndRoom). From config alone, never
  // the gaps as drawn: a gap a spacer widens changes nothing.
  function tabFillet(radius, thickness, corners, spacing, endRoom) {
    if (corners !== "flared")
      return 0;
    return Math.max(0, Math.min(radius, thickness / 2, spacing / 2, endRoom));
  }

  // A tab (widgetShape tab) reaches from the widget out to the outer edge
  // of what it sits on, where its sides meet that edge squarely or with a
  // concave fillet of `fillet` (tabFillet); its inner corners take the
  // widget radius, at most half the bar's `thickness`. `limits` [start,
  // end] (tabLimits) are what bounds each end along the bar, or null: an
  // end nearer a bound than its corner's radius takes that corner's curve
  // on its outer corner instead of a fillet. `outerStart`: the outer edge
  // is at the start of `across` (a top or left bar).
  // -> { outerStart, radius, start: { flare, corner }, end } (corner:
  // { radius, gap } or null), path's `tab`
  function tab(radius, thickness, fillet, outerStart, limits) {
    const r = Math.max(0, Math.min(radius, thickness / 2));
    const end = limit => {
      const gap = Math.max(0, limit?.gap ?? 0);
      if (limit && gap < limit.radius)
        return {
          "flare": 0,
          "corner": {
            "radius": limit.radius,
            "gap": gap
          }
        };
      return {
        "flare": fillet,
        "corner": null
      };
    };
    return {
      "outerStart": outerStart,
      "thickness": thickness,
      "radius": r,
      "start": end(limits?.[0] ?? null),
      "end": end(limits?.[1] ?? null)
    };
  }

  // What bounds a tab running `start` to `end` along the bar at each end:
  // the inner side of the surface it hangs from, from `bounds` [{ start,
  // end, startRadius, endRadius }] (the curves of its corners at each of
  // its ends: an island's, the rounded border's), as tab's `limits`:
  // [{ gap, radius }, …], or null where none holds it
  function tabLimits(start, end, bounds) {
    const middle = (start + end) / 2;
    const bound = (bounds ?? []).find(b => b.start <= middle && middle <= b.end) ?? null;
    if (!bound)
      return [null, null];
    return [
      {
        "gap": start - bound.start,
        "radius": bound.startRadius
      },
      {
        "gap": bound.end - end,
        "radius": bound.endRadius
      }
    ];
  }

  // A side of a tab that isn't a tab's (a merged run's flat middle,
  // split's divider), as _tabPath's points from its outer edge in: _cap's,
  // `h` deep (`d` its depth), turned over when the outer edge is at the
  // far side (`flip`), each arc kept on the later point with its sweep as
  // drawn down the item (`down`)
  function _tabSideCap(cap, atStart, h, d, flip) {
    const pts = root._cap(cap, atStart, h, d, 0);
    // _cap's sweeps: a tail's as drawn down it, a head's as drawn up
    const arcs = pts.map(q => q.arc ? {
        "r": q.arc.r,
        "down": atStart ? 1 - q.arc.sweep : q.arc.sweep
      } : null);
    const out = pts.map((q, k) => ({
          "x": q.x,
          "y": flip ? h - q.y : q.y,
          "arc": null
        }));
    if (!flip) {
      out.forEach((q, k) => q.arc = arcs[k]);
      return out;
    }
    // Reversed: the arc between k - 1 and k now leads into k - 1
    out.forEach((q, k) => q.arc = arcs[k + 1] ?? null);
    return out.reverse();
  }

  // A tab's two sides (path with `tab`), each from the outer edge in, as
  // { x in from its end, y down from the outer edge, arc into it }, and
  // a pen putting them in item coordinates: drawn as if the outer edge
  // were at the top, then flipped across when it's at the far side, and
  // swapped on a vertical bar (each a reflection, which flips the arcs).
  // The sides lie `inset` in, but the outer edge keeps none. `grow` moves
  // the lines that far in from the shape's own while round corners keep
  // their centres (a double outline's lines, offsetPath): the inner
  // corners' radius less it, a fillet's or a bound's curve's more or less.
  function _tabSides(length, across, startCap, endCap, vertical, inset, tab, grow) {
    const h = Math.max(0, across - inset);
    const room = Math.max(0, length - 2 * inset);
    const r = Math.max(0, Math.min(tab.radius - grow, room / 2, h / 2));
    const flip = !tab.outerStart;
    const p = (x, y, arc) => ({
          "x": x,
          "y": y,
          "arc": arc ?? null
        });
    const side = (cap, end, atStart) => {
      if (cap !== "tab")
        return root._tabSideCap(cap, atStart, h, root.depth(cap, tab.thickness), flip);
      const out = [];
      const corner = end.corner;
      if (corner) {
        // The bound's curve: it runs from the outer edge, its radius in
        // from the bound, round to where it crosses this side (its centre
        // kept: `grow` takes its radius in, the gap stays)
        const R = Math.max(0, corner.radius - grow);
        const off = R - corner.gap;
        const along = Math.min(off, room / 2);
        const down = Math.min(h - r, R - Math.sqrt(Math.max(0, R * R - off * off)));
        out.push(p(along, 0), p(0, down, {
          "r": R,
          "convex": true
        }));
      } else if (end.flare > 0) {
        // A concave fillet: a quarter circle out into the outer edge, or
        // with `grow` its centre's circle that much wider, from where it
        // crosses that edge
        const f = Math.min(end.flare, h - r);
        const F = f + grow;
        out.push(p(-F + Math.sqrt(Math.max(0, F * F - f * f)), 0), p(0, f, {
          "r": F,
          "convex": false
        }));
      } else {
        out.push(p(0, 0));
      }
      if (r > 0)
        out.push(p(0, h - r), p(r, h, {
          "r": r,
          "convex": true
        }));
      else
        out.push(p(0, h));
      return out;
    };
    const pt = uv => vertical ? `${uv[1]} ${uv[0]}` : `${uv[0]} ${uv[1]}`;
    return {
      "head": side(startCap, tab.start, true),
      "tail": side(endCap, tab.end, false),
      "at": (q, atEnd) => pt([atEnd ? length - inset - q.x : inset + q.x, flip ? across - q.y : q.y]),
      // A step to a point, along `arc` (the side's own, into it) drawn
      // the way the side runs (`inward`: from the outer edge in) at its
      // start or end: convex corners turn one way, fillets the other
      "to": (q, atEnd, arc, inward) => {
        const xy = pt([atEnd ? length - inset - q.x : inset + q.x, flip ? across - q.y : q.y]);
        if (!arc)
          return `L ${xy} `;
        // A cap's own arc (_tabSideCap) keeps its sweep as drawn
        // downwards in the item; the rest turn by their side, the start's
        // drawn in and the end's out alike (mirrored and reversed), the
        // other way round reversed
        const down = inward !== flip;
        const own = arc.down !== undefined ? (down ? arc.down : 1 - arc.down) : (arc.convex ? 0 : 1) ^ (flip ? 1 : 0) ^ (inward === atEnd ? 1 : 0);
        return `A ${arc.r} ${arc.r} 0 0 ${own ^ (vertical ? 1 : 0)} ${xy} `;
      }
    };
  }

  // A tab's outline (path with `tab`): along its start side from the
  // outer edge in, along its inner side, back out along its end side,
  // then closed along the outer edge, or left open there (`open`, an
  // outline: a tab has no line along the edge it hangs from). Its outer
  // side keeps no inset, so a stroke runs right to that edge. `grow`:
  // _tabSides'.
  function _tabPath(length, across, startCap, endCap, vertical, inset, tab, open, grow) {
    const t = root._tabSides(length, across, startCap, endCap, vertical, inset, tab, grow ?? 0);
    const head = t.head, tail = t.tail;
    let d = `M ${t.at(head[0], false)} `;
    for (let k = 1; k < head.length; k++)
      d += t.to(head[k], false, head[k].arc, true);
    d += t.to(tail[tail.length - 1], true, null, false);
    for (let k = tail.length - 2; k >= 0; k--)
      d += t.to(tail[k], true, tail[k + 1].arc, false);
    return open ? d.trim() : d + "Z";
  }

  // A tab's Ends only marks (marks with `tab`): each side from the outer
  // edge in, round its inner corner and an arm `arm` along the inner side
  // (a `[ ]` open at the edge it hangs from)
  function _tabMarks(length, across, startCap, endCap, vertical, inset, tab, arm) {
    const t = root._tabSides(length, across, startCap, endCap, vertical, inset, tab, 0);
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
    return mark(t.head, false) + mark(t.tail, true);
  }

  // The outline of a background `length` along the bar and `across` it,
  // as an SVG path in its item's coordinates (on a vertical bar the length
  // runs down). `inset` shrinks it all round, so an outline's stroke stays
  // inside, except at a seam (`seamStart`/`seamEnd`), where it meets a
  // powerline neighbour and both strokes lie on the shared edge; caps keep
  // their depth for the full thickness, so neighbours' edges still meet.
  // A tab's (`tab`, from tab; null otherwise) is its own: see _tabPath.
  function path(length, across, radius, startCap, endCap, vertical, inset, seamStart, seamEnd, tab, open) {
    if (tab)
      return root._tabPath(length, across, startCap, endCap, vertical, inset, tab, open ?? false);
    const h = Math.max(0, across - inset * 2);
    const r = Math.min(radius, h / 2);
    const along0 = seamStart ? 0 : inset, along1 = seamEnd ? 0 : inset;
    const shift = along => q => Object.assign({}, q, {
          "x": along + q.x,
          "y": inset + q.y
        });
    const head = root._cap(startCap, true, h, root.depth(startCap, across), r).map(shift(along0));
    const tail = root._cap(endCap, false, h, root.depth(endCap, across), r).map(shift(along1));
    return root._outline(length, head, tail, vertical);
  }

  // A closed path from a start cap's and an end cap's points (_cap's, x
  // in from their own end, y across the whole thickness)
  function _outline(length, head, tail, vertical) {
    const pen = root._pen(length, vertical);
    let d = `M ${pen.pt(pen.atStart(head[0]))} ` + pen.to(pen.atEnd(tail[0]));
    for (let k = 1; k < tail.length; k++)
      d += pen.to(pen.atEnd(tail[k]), tail[k].arc);
    d += pen.to(pen.atStart(head[head.length - 1]));
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

  // A cap's line moved in from the edge it outlines, as _cap's points (x
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
    const d = root.depth(cap, across);
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

  // The outline of a background (path's), its line moved `inset` in all
  // round, square to every edge (a double outline's lines): a slant's or
  // an arrow's side stays parallel to the shape's, a round corner keeps
  // its centre. `alongStart`/`alongEnd` move the caps' lines by a
  // different amount (0 at a powerline seam, where the line lies on the
  // shared edge). Empty when the inset leaves no room.
  // A tab's (`tab`) is open along its outer edge, as its outline is.
  function offsetPath(length, across, radius, startCap, endCap, vertical, inset, alongStart, alongEnd, tab) {
    if (tab)
      return root._tabPath(length, across, startCap, endCap, vertical, inset, tab, true, inset);
    if (across - inset * 2 <= 0)
      return "";
    const head = root._offsetCap(startCap, true, across, radius, inset, alongStart);
    const tail = root._offsetCap(endCap, false, across, radius, inset, alongEnd);
    return root._outline(length, head, tail, vertical);
  }

  // An outline at its ends only (outlineStroke `ends`), as open SVG paths
  // over path's outline at `inset`: each cap's line with arms a quarter of
  // the thickness along the bar from its two corners, so it reads as a
  // bracket (round or flat `[ ]`, a slant's, an arrow's), but a capsule's
  // `( )` (and a powerline's half circles) alone. At a seam the cap before draws
  // the one mark (`seamStart` leaves the start out, and puts no inset on
  // the end there).
  // A tab's (`tab`): its two sides, open at the edge it hangs from
  // (_tabMarks).
  function marks(length, across, radius, startCap, endCap, vertical, inset, seamStart, seamEnd, tab) {
    if (tab)
      return root._tabMarks(length, across, startCap, endCap, vertical, inset, tab, tab.thickness / 4);
    const pen = root._pen(length, vertical);
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
    return (seamStart ? "" : mark(startCap, true, false)) + mark(endCap, false, seamEnd);
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
    case "curve":
      {
        const R = d > 0 ? (r * r + d * d) / (2 * d) : 0;
        return d > 0 ? R - Math.sqrt(Math.max(0, R * R - off * off)) : 0;
      }
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
