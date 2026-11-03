pragma Singleton
import QtQuick

// Where a box that grows out of a screen edge goes along it: bar popouts,
// edge popouts (the launcher, OSDs, floating edge menus) and anything else
// drawn with AttachedSurface. One set of rules, so they all meet the frame,
// a bar's pills and a floating bar's islands the same way.
//
// Everything is along the edge in one coordinate system of the caller's
// (a bar window's, an edge popout's), and lengths are in px. No files,
// services or config: the caller passes the shape metrics.
//
// The content always sits where it wants (the caller's `aligned` start),
// moved only to stay within reach: the box grows around it to meet what
// it attaches to, rather than the content moving to make the box fit.
// Out of a pill or island, a box whose side ends just short of the pill's
// end (too close for a fillet) would grow flush to it, empty. With
// `pillGrows` (bar popouts, edge popouts, docks) the pill grows instead,
// past its end far enough to carry the fillet, and the box keeps to its
// content. Where a pill can't grow (submenus, whose "pill" is their
// parent's box) `nudge` moves the content the least way that leaves no
// empty growth: up to that end, or back far enough for the fillet. Either
// is less than a fillet's room, so it stays over its anchor.
//
// - A box whose fillet would come within a connector gap of a
//   perpendicular edge it can join (the border, a solid bar) joins it
//   instead (`joins`): the box reaches to that stroke, flush on it.
// - On a pill bar or a floating bar it grows out of the pill (or island)
//   under its centre, else the nearest one. A side whose fillet lands on
//   it (or on neighbours a stretch comes within `merge` of) keeps it; any
//   other reaches to its end and runs flush into it, the pill stretched to
//   the box where the box goes past it. Where that end is a pill joining
//   the perpendicular edge, the box joins that edge too. A pill bar
//   showing no pills has nothing to grow out of: the box grows from its
//   outer edge (`merged`). With `between`, a box centred between pills (or
//   islands) that keeps clear of them grows from the bar's outer edge too,
//   over the bar (`between`), rather than out of the nearest.
// - At an end with nothing to join (another bar on the perpendicular
//   edge, an integrated menu's strip) the caller may set a wall: where
//   the surface stops, its fillet included (SurfaceContext.wallAt puts
//   it a fillet short of where windows start, so the box is in line with
//   them, or clear of the frame's corner), and it never joins that edge.
//   Short of room there, the box moves in: radii never shrink.
QtObject {
  id: root

  // Room a side wall's fillet takes along the edge: its arc's run, from
  // where it leaves the stroke it grows from to the wall's stroke centre
  // (SurfaceOutline), so nothing straight of its own runs on along that
  // stroke past it; 0 when the radius is too tight for one (see
  // SurfaceOutline.metrics' `sharp`)
  function filletMargin(stroke, radius) {
    return radius < stroke / 2 ? 0 : radius - stroke / 2;
  }

  // Whether a box wanting `start` to `start + length` joins the
  // perpendicular edges: when it would be pushed back from one, or leave
  // less than a connector gap between its fillet and it. `lo`/`hi` are the
  // nearest and furthest its box may reach unjoined (its fillets' room
  // included); `length` Infinity (content that fills any room) joins both.
  function joins(start, length, lo, hi, gap, startOk, endOk) {
    const endless = !isFinite(length);
    return {
      "joinStart": !!startOk && (endless || start < lo + gap),
      "joinEnd": !!endOk && (endless || start + length > hi - gap)
    };
  }

  // Which way a bar popout grows while it's open, so its controls (kept on
  // the side it grows from) never move: away from the bar on a horizontal
  // one (`up` from a bottom bar), and along a vertical one `down` from
  // where it opened centred on its anchor, or `up` from its end when its
  // most length wouldn't fit below (a widget low on the bar). With room
  // neither way, the way with more. `s`: vertical, bottom, anchorStart,
  // anchorLength, openLength (the box's length as it opened), maxLength
  // (the most it may grow to), lo, hi (where an unjoined box keeps
  // within). Returns { direction: "down" | "up", pinned: along a vertical
  // bar, where the box's start (down) or end (up) stays; NaN on a
  // horizontal one, whose box stays centred }
  function growth(s) {
    if (!s.vertical)
      return {
        "direction": s.bottom ? "up" : "down",
        "pinned": NaN
      };
    const start = Math.max(s.lo, Math.min(s.anchorStart + (s.anchorLength - s.openLength) / 2, s.hi - s.openLength));
    const end = start + s.openLength;
    const length = Math.max(s.maxLength, s.openLength);
    const down = start + length <= s.hi || (end - length < s.lo && s.hi - start >= end - s.lo);
    return {
      "direction": down ? "down" : "up",
      "pinned": down ? start : end
    };
  }

  // The pill (or island) a box centred at `centre` belongs to, with its
  // index: the one under the centre, or for an island the nearest
  function pillAt(pills, centre, island) {
    let best = -1, bestDistance = Infinity;
    pills.forEach((p, i) => {
      const distance = Math.max(0, p.start - centre, centre - (p.start + p.length));
      if (distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    });
    if (best < 0 || (bestDistance > 0 && !island))
      return null;
    return Object.assign({
      "index": best
    }, pills[best]);
  }

  // The box's place along the edge. `s`:
  //   pills [{ start, length, joinStart, joinEnd }], pillBar (on a pill
  //     bar, even with none showing; else whether there are pills), island
  //     (they're a floating bar's islands), merge (pillMerge), centre
  //     (picks the pill)
  //   aligned (where the content's box would start), length (its length)
  //   joinStart, joinEnd (from `joins`), joinFrom, joinTo (where joined
  //     ends sit: the perpendicular strokes' outer edges)
  //   lo, hi (the range an unjoined box keeps within, fillets' room in)
  //   islandFrom, islandTo (where islands may reach)
  //   straight (a plain box's attach edge is a bare screen edge),
  //   straightMerged (likewise for one grown from a pill bar's outer edge)
  //   pillJoins (on a pill bar, a box joining a perpendicular edge joins
  //     it from any pill, which stretches on to that edge, from `pillFrom`
  //     or to `pillTo`, where the bar's ends are, and joins it too; and
  //     joinableStart/joinableEnd, whether that end can join at all: a
  //     side whose pill runs on past `lo`/`hi` joins it there)
  //   between (centred between pills or islands, a box that keeps more
  //     than `merge` and two fillets' room from each grows from the bar's
  //     outer edge over the bar rather than out of the nearest)
  //   pillGrows (a pill or island grows past its end to carry a fillet
  //     its side lands just short of, rather than the box growing empty to
  //     that end; see above)
  //   nudge (without pillGrows: out of a pill or island, the content may
  //     move a little rather than the box growing empty to the pill's end)
  //   gap (connector gap), stroke, radius
  //   wallFrom, wallTo (optional: at an end with nothing to join, where
  //     the surface stops, its fillet included; replaces lo/hi there, and
  //     out of a pill or island also keeps a full fillet and the pill's
  //     corner inside what it may reach, joinFrom/joinTo or
  //     islandFrom/islandTo)
  // Returns { mode: "plain" | "pill" | "island" | "merged" | "between",
  //   pill, start, end (the box), grow (the box past `length`),
  //   contentStart (where the content's `length` starts) and
  //   contentOffset (from the box's start), joinStart, joinEnd,
  //   flushStart, flushEnd, startMargin, endMargin (the surface's fillet
  //   room), surfaceStart, surfaceLength,
  //   stretch ({ index, start, end, squareStart, squareEnd, joinStart,
  //   joinEnd } or null) }
  function place(s) {
    const pills = s.pills ?? [];
    // A pill bar showing no pills still grows from its outer edge
    const pillBar = !s.island && (s.pillBar ?? pills.length > 0);
    const pill = pills.length > 0 && (s.island || pillBar) ? root.pillAt(pills, s.centre, true) : null;
    if (pill === null)
      return root._offPills(s, pillBar ? "merged" : "plain", pillBar ? !!s.straightMerged : !!s.straight);
    if (s.between && root.pillAt(pills, s.centre, false) === null) {
      const free = root._offPills(s, "between", !!s.straightMerged);
      if (root._clearOf(pills, free, root.filletMargin(s.stroke, s.radius) * 2, s.merge ?? 0))
        return free;
    }
    return root._onPill(s, pills, pill, !s.island);
  }

  // A box grown from the edge itself (or a bar's outer edge) rather than
  // out of a pill or island: its content where it wants, kept within
  // reach, a fillet each side unless joined or `straight`
  function _offPills(s, mode, straight) {
    const fm = root.filletMargin(s.stroke, s.radius);
    const length = s.length;
    // On whole pixels: a fillet ending mid-pixel leaves a pale pixel in
    // the stroke it joins
    // (at a wall, the fillet inside it too)
    const lo = s.joinStart ? s.joinFrom : isFinite(s.wallFrom ?? NaN) ? s.wallFrom + fm : s.lo;
    const hi = s.joinEnd ? s.joinTo : isFinite(s.wallTo ?? NaN) ? s.wallTo - fm : s.hi;
    const content = Math.round(Math.max(lo, Math.min(s.aligned, hi - length)));
    const start = s.joinStart ? s.joinFrom : content;
    const end = s.joinEnd ? s.joinTo : content + length;
    const startMargin = !s.joinStart && !straight ? fm : 0;
    const endMargin = !s.joinEnd && !straight ? fm : 0;
    return {
      "mode": mode,
      "pill": null,
      "start": start,
      "end": end,
      "grow": end - start - length,
      "contentStart": content,
      "contentOffset": content - start,
      "joinStart": !!s.joinStart,
      "joinEnd": !!s.joinEnd,
      "flushStart": false,
      "flushEnd": false,
      "startMargin": startMargin,
      "endMargin": endMargin,
      "surfaceStart": start - startMargin,
      "surfaceLength": startMargin + (end - start) + endMargin,
      "stretch": null
    };
  }

  // Whether box `b` keeps more than `merge`, and at least `room` (both
  // their fillets), from every pill: pills closer than `merge` draw as
  // one, and its fillet and a pill's would overlap closer than `room`
  function _clearOf(pills, b, room, merge) {
    return pills.every(p => {
      const gap = Math.max(p.start - b.end, b.start - (p.start + p.length));
      return gap > merge && gap >= room;
    });
  }

  // A pill (or island) stretch `target` ({ start, end, ... }) as drawn
  // `progress` (0..1) of the way out from the pill's own span `rest`
  // ({ start, length }), its flags kept: a surface's pill grows out to
  // carry it, and draws back after it, at the pace the surface sets
  // (PillStretch). Null with nothing grown (none, or progress 0).
  function progressStretch(rest, target, progress) {
    if (!target || !rest || progress <= 0)
      return null;
    const p = Math.min(1, progress);
    const restEnd = rest.start + rest.length;
    return Object.assign({}, target, {
      "start": rest.start - Math.max(0, rest.start - target.start) * p,
      "end": restEnd + Math.max(0, target.end - restEnd) * p
    });
  }

  /**
   * The stretch of a perpendicular edge's stroke that a surface joined to
   * it at an end covers, as the border takes it ({ edge, start, end }, px
   * along that edge): its fill runs along it from the surface's own edge
   * to its join's fillet. `edge` is the surface's edge ("top", "bottom",
   * "left" or "right"), `atStart` the end joined (top or left), `from` and
   * `depth` where the surface's item starts across its edge and how deep
   * it is (on screen), `cover` how far in from its attach side the join
   * covers (AttachedSurface.joinCover), `span` the screen's size across.
   * With `fillet` (AttachedSurface.joinFillet, > 0), also the radius it
   * curves into the stroke with at the far end of its cover (`endFillet`
   * from the near side, `startFillet` from the far one), which the border's
   * shadow follows round rather than leaving out the square it sits in.
   */
  function joinOpening(edge, atStart, from, depth, cover, span, fillet) {
    const vertical = edge === "left" || edge === "right";
    const far = edge === "right" || edge === "bottom";
    const reach = far ? from + depth - cover : from + cover;
    const opening = {
      "edge": vertical ? (atStart ? "top" : "bottom") : (atStart ? "left" : "right"),
      "start": far ? reach : 0,
      "end": far ? span : reach
    };
    if ((fillet ?? 0) > 0)
      opening[far ? "startFillet" : "endFillet"] = Math.max(0, Math.min(fillet, opening.end - opening.start));
    return opening;
  }

  /**
   * Whether a surface's end joined to a pill bar curves into its far
   * stroke with a fillet (PillBarJoin.filleted) rather than running
   * straight into a stub squared at its wall. `pills` are that bar's own
   * pills as laid out ({ start, length }, before any surface stretches
   * them), `wall` where the surface's far wall meets it (the bar's
   * coordinates), `atStart` whether the surface is at the bar's start end,
   * `radius` the fillet's (and the pill's corner's), `merge` its
   * pillMerge, `stroke` its stroke width.
   *
   * Filleted where a pill shows past the wall at all (past its outer
   * edge, half a stroke out, where a straight join would square it) and
   * starts within the fillet, its own corner and `merge` of it: the join
   * stretches it out to carry both. A pill showing past the wall can't
   * square at it (a stretch only grows): squared where it is, it stood
   * out of the wall's line, and a straight join there met its side in a
   * bare T.
   */
  function pillJoinFilleted(pills, wall, atStart, radius, merge, stroke) {
    const need = radius * 2;
    const edge = stroke / 2 + 0.5;
    return (pills ?? []).some(p => atStart ? p.start + p.length > wall + edge && p.start <= wall + need + merge : p.start < wall - edge && p.start + p.length >= wall - need - merge);
  }

  // How far the pill (or island) `own` reaches toward `target` (before it
  // when `before`): its own end, or that of the neighbours a stretch to
  // there would come within `merge` of, which then draw as one with it
  // (BarLayout.stretchIslands)
  function _islandReach(pills, own, target, before, merge) {
    let reach = before ? own.start : own.start + own.length;
    const others = pills.filter(p => before ? p.start < own.start : p.start > own.start).sort((a, b) => before ? b.start - a.start : a.start - b.start);
    for (const p of others) {
      if ((before ? target - (p.start + p.length) : p.start - target) > merge)
        break;
      reach = before ? p.start : p.start + p.length;
    }
    return reach;
  }

  // Growing out of pill (or island) `own`; a pill bar's (`isPill`) pills
  // may join the perpendicular edges at the bar's ends
  function _onPill(s, pills, own, isPill) {
    // Within reach: a pill bar's frame, or where islands may go
    const reachFrom = isPill ? s.joinFrom : s.islandFrom, reachTo = isPill ? s.joinTo : s.islandTo;
    const fm = root.filletMargin(s.stroke, s.radius);
    const need = fm + s.radius;
    // At a wall, the fillet inside it, and a full fillet and the pill's
    // corner inside the reach (the pill can't grow past the wall), so the
    // side never runs flush past the wall: short of room, the content
    // moves in rather than either rounding less
    const lo = isFinite(s.wallFrom ?? NaN) ? Math.max(s.wallFrom + fm, reachFrom + need) : reachFrom;
    const hi = isFinite(s.wallTo ?? NaN) ? Math.min(s.wallTo - fm, reachTo - need) : reachTo;
    const content = Math.round(Math.max(lo, Math.min(s.aligned, hi - s.length)));
    const placed = root._onPillAt(s, pills, own, isPill, content);
    // One side runs flush to the pill's end with empty box before it: try
    // the content up to that end, or back far enough for its fillet, and
    // take the nearer that grows nothing (the other side unchanged)
    if (!s.nudge || s.pillGrows || placed.grow <= 0 || placed.joinStart || placed.joinEnd || placed.flushStart === placed.flushEnd)
      return placed;
    const empty = placed.flushStart ? content - placed.start : placed.end - (content + s.length);
    const toward = placed.flushStart ? -empty : empty;
    const away = placed.flushStart ? need - empty : empty - need;
    const tries = Math.abs(toward) <= Math.abs(away) ? [toward, away] : [away, toward];
    for (const shift of tries) {
      const moved = content + Math.round(shift);
      if (moved < lo || moved > hi - s.length)
        continue;
      const nudged = root._onPillAt(s, pills, own, isPill, moved);
      if (nudged.grow === 0 && !nudged.joinStart && !nudged.joinEnd)
        return nudged;
    }
    return placed;
  }

  // The box out of pill (or island) `own` with its content at `content`
  function _onPillAt(s, pills, own, isPill, content) {
    const fm = root.filletMargin(s.stroke, s.radius);
    const length = s.length, r = s.radius;
    // Room past the box for a fillet: its margin, and the pill's rounded
    // corner beyond, which a fillet can't land on
    const need = fm + r;
    const from = root._islandReach(pills, own, content - need, true, s.merge);
    const to = root._islandReach(pills, own, content + length + need, false, s.merge);
    // A side whose fillet doesn't fit reaches to the pill's end, or past it
    // the pill stretching to it, running flush into it; or where that's a
    // pill joining the perpendicular edge, joining that edge too. With
    // `pillGrows`, a side short of that end keeps its fillet instead, the
    // pill growing past its end to carry it, unless it can't grow there
    // (it joins the edge, or the fillet would pass where pills may reach)
    const lo = isPill ? s.joinFrom : s.islandFrom, hi = isPill ? s.joinTo : s.islandTo;
    // (never past a wall)
    // A pill running past where an unjoined box may reach (`lo`/`hi`: on
    // past a perpendicular bar's far stroke, at a corner its bar owns)
    // joins an edge that can be joined (`joinableStart`/`joinableEnd`)
    // rather than a flush side running on past there behind what's on it
    const overStart = !!s.pillJoins && !!s.joinableStart && from < s.lo;
    const overEnd = !!s.pillJoins && !!s.joinableEnd && to > s.hi;
    const edgeStart = isPill && !isFinite(s.wallFrom ?? NaN) && (pills.some(p => p.joinStart && p.start === from) || !!s.pillJoins && !!s.joinStart || overStart);
    const edgeEnd = isPill && !isFinite(s.wallTo ?? NaN) && (pills.some(p => p.joinEnd && p.start + p.length === to) || !!s.pillJoins && !!s.joinEnd || overEnd);
    // Too tight a radius for a fillet or corner (none needs room): a side
    // reaching the pill's end runs flush into it, its wall continuing the
    // pill's, rather than standing on its corner, where the box's backfill
    // cut the pill's stroke short
    const sharp = need <= 0;
    const grows0 = !!s.pillGrows && !sharp && content >= from && content - need >= lo && !edgeStart;
    const grows1 = !!s.pillGrows && !sharp && content + length <= to && content + length + need <= hi && !edgeEnd;
    // A side that joins the edge (`joinStart`/`joinEnd`: within a connector
    // gap of it, see joins) does where its pill can reach it, as does one
    // whose fillet would pass the stroke there (a pill joining the edge may
    // run on past it, under a bar that makes way for this one at that
    // corner)
    const past0 = edgeStart && (content - need < lo || !!s.joinStart), past1 = edgeEnd && (content + length + need > hi || !!s.joinEnd);
    const short0 = (content - need < from || sharp && content <= from || past0) && !grows0;
    const short1 = (content + length + need > to || sharp && content + length >= to || past1) && !grows1;
    const joinStart = short0 && edgeStart;
    const joinEnd = short1 && edgeEnd;
    const flushStart = short0 && !joinStart, flushEnd = short1 && !joinEnd;
    const start = joinStart ? s.joinFrom : flushStart ? Math.min(content, from) : content;
    const end = joinEnd ? s.joinTo : flushEnd ? Math.max(content + length, to) : content + length;
    const startMargin = short0 ? 0 : fm;
    const endMargin = short1 ? 0 : fm;
    const surfaceStart = start - startMargin;
    const surfaceLength = startMargin + (end - start) + endMargin;
    // To a flush side's end, squaring the pill's corner there, else far
    // enough for the fillet; joined, to the bar's end (where a joined pill
    // already reaches), joining the edge there
    const stretchFrom = joinStart ? Math.min(from, s.pillFrom ?? s.joinFrom) : flushStart ? start : Math.min(own.start, surfaceStart - r);
    const stretchTo = joinEnd ? Math.max(to, s.pillTo ?? s.joinTo) : flushEnd ? end : Math.max(own.start + own.length, surfaceStart + surfaceLength + r);
    const stretched = stretchFrom !== own.start || stretchTo !== own.start + own.length || flushStart || flushEnd;
    return {
      "mode": isPill ? "pill" : "island",
      "pill": own,
      "start": start,
      "end": end,
      "grow": end - start - length,
      "contentStart": content,
      "contentOffset": content - start,
      "joinStart": joinStart,
      "joinEnd": joinEnd,
      "flushStart": flushStart,
      "flushEnd": flushEnd,
      "startMargin": startMargin,
      "endMargin": endMargin,
      "surfaceStart": surfaceStart,
      "surfaceLength": surfaceLength,
      "stretch": stretched ? {
        "index": own.index,
        "start": stretchFrom,
        "end": stretchTo,
        "squareStart": flushStart,
        "squareEnd": flushEnd,
        "joinStart": joinStart,
        "joinEnd": joinEnd
      } : null
    };
  }
}
