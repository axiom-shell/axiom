pragma Singleton
import QtQuick

// The shapes bar widget backgrounds take (the look's shape: a name, and a
// slanted or arrow widget's or run's ends), alone or in runs (the look's
// grouping): which cap each end of a widget gets, how much room its
// content keeps clear of them, where a box lies past its item (boxRect),
// and whether a point lies in it. Lengths run along the bar, `across` is
// the widget's thickness. Tabs are BarTabs, outlines as SVG paths
// BarOutlines, a widget's parts laid out as cells BarCells. Shape helpers
// read the look's resolved fields (look.shape, look.grouping, its traits),
// never its style's name.
//
// Caps: flat, round (the widget radius), capsule (half the thickness),
// arrowOut/arrowIn (a point or a notch), slant (a parallelogram's side),
// roundOut/roundIn (a half circle bulging out or in), curve (a shallow
// arc bulging out: split's divider), tab (a tab's side: BarTabs).
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

  // A run's own ends by `shape` (the look's: its name, and a slant's or
  // arrow's `ends`: shaped, pointed (an arrow's alone), rounded), [start,
  // end] (a lone widget's in separate)
  function _ends(shape) {
    const ends = shape.ends;
    if (ends === "rounded" && (shape.name === "slant" || shape.name === "arrow"))
      return ["round", "round"];
    switch (shape.name) {
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

  // Widget `index` of a run of `count` in a look's `shape` (look.shape:
  // { name, ends }), `grouping` (look.grouping) and `opaque` (its
  // `opaque` trait): { startCap, endCap, shownStart, levelStartCap,
  // levelEndCap, back, lead, trail, seamStart, seamEnd }. `back` is how
  // far its background reaches back under the one before; `lead`/`trail`
  // the room its content keeps at each end. In a merged run only the run's
  // ends have caps (the run is one background). `opaque`: the fill hides
  // what's under it, so a powerline segment can start square beneath the
  // one before instead of fitting against it. `seamStart`/`seamEnd`: that end meets a
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
  function segment(shape, grouping, opaque, index, count, across) {
    const ends = root._ends(shape);
    const joins = root._joins(shape.name);
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
  // a horizontal bar) on the way into the point, `h` across, `d` deep
  // (depth) and round corners of `r`. A slant is the one cap that differs
  // at the start: a parallelogram leans the same way at both.
  function capPoints(cap, atStart, h, d, r) {
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

  // An outline spec (what BarOutlines draws and BarTabs' sides lie in):
  // a background `length` along the bar and `across` it (on a vertical bar
  // the length runs down), round caps of `radius`, its `startCap` and
  // `endCap`; `seamStart`/`seamEnd`: that end meets a powerline
  // neighbour edge to edge (segment's); `tab`: a tab's shape (BarTabs.tab)
  // or null; `openStart`/`openEnd`: a merged run carries on past that end
  // into the next section's, drawn apart. What `o` leaves out is 0, false
  // or null.
  function outline(o) {
    return {
      "length": o.length ?? 0,
      "across": o.across ?? 0,
      "radius": o.radius ?? 0,
      "startCap": o.startCap ?? "flat",
      "endCap": o.endCap ?? "flat",
      "vertical": o.vertical === true,
      "seamStart": o.seamStart === true,
      "seamEnd": o.seamEnd === true,
      "tab": o.tab ?? null,
      "openStart": o.openStart === true,
      "openEnd": o.openEnd === true
    };
  }

  // Where a box drawn for an item at `rect` ({ x, y, width, height }, in
  // the coordinates it's placed in) lies: `back` further back along the
  // bar (under a powerline neighbour), `onward` further on past its end
  // (a merged run carrying on into the next section's), and across out
  // `reachNear` before its near side and `reachFar` past its far one (a
  // tab's reach to its edge): { x, y, width, height }. A widget's or run's
  // background, a widget's hit area and its parts' clip, and a cell's box
  // as a segment are each this rect.
  function boxRect(rect, back, reachNear, reachFar, vertical, onward) {
    const on = onward ?? 0;
    return {
      "x": rect.x - (vertical ? reachNear : back),
      "y": rect.y - (vertical ? back : reachNear),
      "width": rect.width + (vertical ? reachNear + reachFar : back + on),
      "height": rect.height + (vertical ? back + on : reachNear + reachFar)
    };
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
