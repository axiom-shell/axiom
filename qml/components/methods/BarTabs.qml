pragma Singleton
import QtQuick

// Tabs (the look's shape `tab`): a widget's background reaching from it out
// to the outer edge of what it sits on, its outer corners square or flared
// (a concave fillet), its inner ones rounded. The fillet a bar's tabs share
// (tabFillet), a tab's shape (tab), what bounds its ends (tabLimits), how
// far its content moves across (tabShift), and its two sides' points
// (sides), which BarOutlines draws.
QtObject {
  id: root

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

  // A box's tab on `bar` (an enriched barConfig: its look's shape, its
  // radius, thickness and edge), its ends bounded by `limits` (tabLimits),
  // or null where the look's shape isn't a tab
  function barTab(bar, limits) {
    const shape = bar.look.shape;
    return shape.name === "tab" ? root.tab(bar.radius, bar.thickness, shape.tabFillet, !(bar.right || bar.bottom), limits) : null;
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
  // { radius, gap } or null), an outline spec's `tab` (BarShapes.outline)
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

  // How far across a tab's content (and the separator marks between tabs)
  // moves to sit centred in the tab: half its `reach` past the widget,
  // toward the edge it hangs from (`outerFar`: past the far side, a bottom
  // or right bar), whole pixels
  function tabShift(reach, outerFar) {
    return Math.round(reach / 2) * (outerFar ? 1 : -1);
  }

  // What bounds a tab running `start` to `end` along the bar at each end:
  // the inner side of the surface it hangs from, from `bounds` [{ start,
  // end, startRadius, endRadius }] (the curves of its corners at each of
  // its ends: an island's, the rounded border's), as tab's `limits`:
  // [{ gap, radius }, …], or null where none holds it, an end no nearer
  // its bound than the curve's radius included (tab draws it as with
  // none), so the limits only change where they change the tab
  function tabLimits(start, end, bounds) {
    const middle = (start + end) / 2;
    const bound = (bounds ?? []).find(b => b.start <= middle && middle <= b.end) ?? null;
    if (!bound)
      return [null, null];
    const limit = (gap, radius) => gap < radius ? {
        "gap": gap,
        "radius": radius
      } : null;
    return [limit(start - bound.start, bound.startRadius), limit(bound.end - end, bound.endRadius)];
  }

  // A side of a tab that isn't a tab's (a merged run's flat middle,
  // split's divider), as sides' points from its outer edge in: the cap's
  // (BarShapes.capPoints),
  // `h` deep (`d` its depth), turned over when the outer edge is at the
  // far side (`flip`), each arc kept on the later point with its sweep as
  // drawn down the item (`down`)
  function _sideCap(cap, atStart, h, d, flip) {
    const pts = BarShapes.capPoints(cap, atStart, h, d, 0);
    // capPoints' sweeps: a tail's as drawn down it, a head's as drawn up
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

  // A tab's two sides (BarOutlines.path with a `tab`), in outline spec
  // `o`'s tab (BarShapes.outline), each from the outer edge in, as
  // { x in from its end, y down from the outer edge, arc into it }, and
  // a pen putting them in item coordinates: drawn as if the outer edge
  // were at the top, then flipped across when it's at the far side, and
  // swapped on a vertical bar (each a reflection, which flips the arcs).
  // The sides lie `inset` in, but the outer edge keeps none, nor an open
  // end (the spec's `openStart`/`openEnd`). `grow` moves
  // the lines that far in from the shape's own while round corners keep
  // their centres (a double outline's lines, BarOutlines.offsetPath): the inner
  // corners' radius less it, a fillet's or a bound's curve's more or less.
  function sides(o, inset, grow) {
    const length = o.length, across = o.across, vertical = o.vertical, tab = o.tab;
    const h = Math.max(0, across - inset);
    const along0 = o.openStart ? 0 : inset, along1 = o.openEnd ? 0 : inset;
    const room = Math.max(0, length - along0 - along1);
    const r = Math.max(0, Math.min(tab.radius - grow, room / 2, h / 2));
    const flip = !tab.outerStart;
    const p = (x, y, arc) => ({
          "x": x,
          "y": y,
          "arc": arc ?? null
        });
    const side = (cap, end, atStart) => {
      if (cap !== "tab")
        return root._sideCap(cap, atStart, h, BarShapes.depth(cap, tab.thickness), flip);
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
    const fillet = (cap, end) => cap === "tab" && !end.corner && end.flare > 0;
    return {
      "head": side(o.startCap, tab.start, true),
      "tail": side(o.endCap, tab.end, false),
      // A side begins in a flared fillet (its first two points), and how
      // long the inner side is between the sides' insets
      "headFillet": fillet(o.startCap, tab.start),
      "tailFillet": fillet(o.endCap, tab.end),
      "room": room,
      "at": (q, atEnd) => pt([atEnd ? length - along1 - q.x : along0 + q.x, flip ? across - q.y : q.y]),
      // A step to a point, along `arc` (the side's own, into it) drawn
      // the way the side runs (`inward`: from the outer edge in) at its
      // start or end: convex corners turn one way, fillets the other
      "to": (q, atEnd, arc, inward) => {
        const xy = pt([atEnd ? length - along1 - q.x : along0 + q.x, flip ? across - q.y : q.y]);
        if (!arc)
          return `L ${xy} `;
        // A cap's own arc (_sideCap) keeps its sweep as drawn
        // downwards in the item; the rest turn by their side, the start's
        // drawn in and the end's out alike (mirrored and reversed), the
        // other way round reversed
        const down = inward !== flip;
        const own = arc.down !== undefined ? (down ? arc.down : 1 - arc.down) : (arc.convex ? 0 : 1) ^ (flip ? 1 : 0) ^ (inward === atEnd ? 1 : 0);
        return `A ${arc.r} ${arc.r} 0 0 ${own ^ (vertical ? 1 : 0)} ${xy} `;
      }
    };
  }
}
