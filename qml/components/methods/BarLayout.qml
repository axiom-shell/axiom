pragma Singleton

import QtQuick

// Pure main-axis layout for a bar (BarContainer) and its sections
// (WidgetGroup). A bar has five sections, [left, leftCenter, center,
// rightCenter, right]; a widget's measure is { pref, min, priority }.
QtObject {
  id: root

  // Length of the given sizes laid end to end, `spacing` between them.
  // Zero sizes (hidden widgets, or ones with nothing to show) take no
  // spacing, as they take no room when laid out.
  function span(sizes, spacing) {
    const shown = sizes.filter(s => s > 0);
    return shown.reduce((sum, s) => sum + s, 0) + Math.max(0, shown.length - 1) * spacing;
  }

  // How far a divider drawn between a section's widgets (WidgetGroup's
  // SeparatorMark) reaches across the bar
  function dividerLength(style, widgetSize) {
    return widgetSize * (style === "chevron" ? 0.6 : 0.5);
  }

  // The gap between a section's widgets with such a divider in each: the
  // room it takes along the bar (a slash leans 20°; a chevron's glyph is
  // about 0.3 of its size), with `margin` to the widget either side
  function dividerGap(style, thickness, widgetSize, margin) {
    const length = root.dividerLength(style, widgetSize);
    const lean = 20 * Math.PI / 180;
    const along = {
      "line": thickness,
      "dot": thickness * 2,
      "slash": length * Math.sin(lean) + thickness * Math.cos(lean),
      "chevron": length * 0.3
    }[style] ?? 0;
    return Math.ceil(along) + 2 * margin;
  }

  // How far a section's dividers at its ends (`edge` flags: Separator
  // widgets) reach in from them, as { lead, trail }: their sizes and the
  // spacing on their inner side. Such a divider stands in the gap between
  // sections rather than in its own, so it neither moves the center
  // section off center nor widens a pill. Zero sizes are passed over; a
  // section of nothing but dividers has none (they're its content).
  function edgeHang(sizes, edge, spacing) {
    const shown = sizes.map((size, i) => ({
          "size": size,
          "edge": edge[i] ?? false
        })).filter(w => w.size > 0);
    if (shown.every(w => w.edge))
      return {
        "lead": 0,
        "trail": 0
      };
    const reach = list => {
      let sum = 0;
      for (const w of list) {
        if (!w.edge)
          break;
        sum += w.size + spacing;
      }
      return sum;
    };
    return {
      "lead": reach(shown),
      "trail": reach(shown.slice().reverse())
    };
  }

  // Where the center section starts so that its content, without the
  // dividers at its ends (`hang`, from edgeHang), sits centered, kept
  // between `lo` and `hi`
  function _centerStart(c, length, lo, hi, hang) {
    const skew = ((hang?.trail ?? 0) - (hang?.lead ?? 0)) / 2;
    return Math.max(lo, Math.min((length - c) / 2 + skew, hi));
  }

  // A margin as [start, end]: one number for both ends, or a pair
  function _margins(margin) {
    return Array.isArray(margin) ? margin : [margin, margin];
  }

  // Returns [{offset, extent}] for each section along the main axis, from
  // their preferred and minimum lengths. `margin` is kept clear at the ends
  // (one number for both, or [start, end]: a bar's ends may meet
  // different things, BarEnds) and `gap` between adjacent non-empty sections. With `lockCenter`, the
  // center section always sits dead center at its full size and each side
  // fits itself into the room left on its own half; otherwise the center
  // slides towards the roomier side when crowded. `centerHang` (edgeHang)
  // is left out of what's centered.
  function layoutSections(pref, min, length, margin, gap, lockCenter, centerHang) {
    const [m0, m1] = root._margins(margin);
    const sum = values => values.reduce((a, b) => a + b, 0);
    const gapsFor = sections => gap * sections.filter(i => pref[i] > 0).length;
    // Preferred sizes if they fit, else squeezed towards the minimums,
    // else the minimums scaled down to whatever room there is
    const fit = (p, m, room) => {
      room = Math.max(0, room);
      const sumPref = sum(p);
      const sumMin = sum(m);
      if (sumPref <= room)
        return p.slice();
      if (sumMin <= room) {
        const squeeze = (sumPref - room) / (sumPref - sumMin);
        return p.map((v, i) => v - (v - m[i]) * squeeze);
      }
      return m.map(v => sumMin > 0 ? v * room / sumMin : 0);
    };

    let size, centerStart;
    if (lockCenter) {
      const c = Math.min(pref[2], Math.max(0, length - m0 - m1));
      centerStart = root._centerStart(c, length, m0, length - m1 - c, centerHang);
      const [l, lc] = fit([pref[0], pref[1]], [min[0], min[1]], centerStart - m0 - gapsFor([0, 1]));
      const [rc, r] = fit([pref[3], pref[4]], [min[3], min[4]], length - m1 - centerStart - c - gapsFor([3, 4]));
      size = [l, lc, c, rc, r];
    } else {
      size = fit(pref, min, length - m0 - m1 - gapsFor([0, 1, 3, 4]));
      const [l, lc, c, rc, r] = size;
      const lo = m0 + (l > 0 ? l + gap : 0) + (lc > 0 ? lc + gap : 0);
      const hi = length - m1 - (r > 0 ? r + gap : 0) - (rc > 0 ? rc + gap : 0) - c;
      centerStart = root._centerStart(c, length, lo, hi, centerHang);
    }

    const [l, lc, c, rc, r] = size;
    const before = lc > 0 ? lc + gap : 0;

    return [
      {
        "offset": m0,
        "extent": l
      },
      {
        "offset": centerStart - before,
        "extent": lc
      },
      {
        "offset": centerStart,
        "extent": c
      },
      {
        "offset": centerStart + c + (rc > 0 ? gap : 0),
        "extent": rc
      },
      {
        "offset": length - m1 - r,
        "extent": r
      }
    ];
  }

  // measures: per section, [{pref, min, priority, divides}]. Returns, per section,
  // the widget indices to hide so that every section's minimum length, plus
  // margins and gaps as in layoutSections, fits the bar; `spacing` is the
  // spacing between widgets within a section. The lowest priority goes
  // first. Ties go to the outer sections first and the center last, and
  // within a section to the widget listed last. With `lockCenter`, each half
  // of the bar must fit beside the full-size center on its own, and only the
  // overflowing half loses widgets; the center is only touched if it can't
  // fit the bar. The center's dividers (`divides`) are left out of what's
  // centered, as in layoutSections.
  function overflowHidden(measures, length, margin, gap, spacing, lockCenter) {
    const [m0, m1] = root._margins(margin);
    const hidden = measures.map(() => []);
    const spanOf = (s, key) => root.span(measures[s].filter((m, i) => m.pref > 0 && !hidden[s].includes(i)).map(m => m[key]), spacing);
    const minSpan = s => spanOf(s, "min");
    const sideNeed = sections => sections.reduce((sum, s) => {
        const len = minSpan(s);
        return sum + (len > 0 ? len + gap : 0);
      }, 0);
    const room = length - m0 - m1 + 0.5;

    // The sections to drop from (in tie order), or null when it all fits
    const overflowing = () => {
      if (!lockCenter) {
        const spans = measures.map((m, s) => minSpan(s));
        const needed = spans.reduce((a, b) => a + b, 0) + gap * [0, 1, 3, 4].filter(s => spans[s] > 0).length;
        return needed > room ? [4, 0, 3, 1, 2] : null;
      }
      if (minSpan(2) > room)
        return [2];
      const c = Math.min(spanOf(2, "pref"), length - m0 - m1);
      const hang = root.edgeHang(measures[2].map((m, i) => hidden[2].includes(i) ? 0 : m.pref), measures[2].map(m => m.divides), spacing);
      const start = root._centerStart(c, length, m0, length - m1 - c, hang);
      if (sideNeed([0, 1]) > start - m0 + 0.5)
        return [0, 1];
      if (sideNeed([3, 4]) > length - m1 - start - c + 0.5)
        return [4, 3];
      return null;
    };

    const dropped = [];
    let order;
    while (length > 0 && (order = overflowing())) {
      let drop = null;
      order.forEach(s => {
        for (let i = measures[s].length - 1; i >= 0; i--) {
          const m = measures[s][i];
          if (m.pref > 0 && !hidden[s].includes(i) && (!drop || m.priority < drop.priority))
            drop = {
              "section": s,
              "index": i,
              "priority": m.priority
            };
        }
      });
      if (!drop)
        break;
      hidden[drop.section].push(drop.index);
      dropped.push(drop);
    }
    // Hiding a big widget can free more room than was missing; bring back
    // whatever still fits, most important (last dropped) first
    for (let d = dropped.length - 1; d >= 0; d--) {
      const list = hidden[dropped[d].section];
      list.splice(list.indexOf(dropped[d].index), 1);
      if (overflowing())
        list.push(dropped[d].index);
    }
    return hidden;
  }

  // The runs of true flags, as { start, count, members }: the widgets that
  // share a background (merged) or a powerline chain. A false flag (a
  // widget shown without a background) ends a run; a null one (a widget
  // showing nothing) is passed over, so `members` lists the indices in it.
  function runs(flags) {
    const out = [];
    let open = false;
    flags.forEach((on, i) => {
      if (on === null || on === undefined)
        return;
      if (!on) {
        open = false;
        return;
      }
      if (open) {
        const last = out[out.length - 1];
        last.count++;
        last.members.push(i);
      } else {
        out.push({
          "start": i,
          "count": 1,
          "members": [i]
        });
        open = true;
      }
    });
    return out;
  }

  // Each index's place in its run, { run, index, count }, or null off them
  function runPlaces(flags) {
    const places = flags.map(() => null);
    root.runs(flags).forEach((run, r) => {
      run.members.forEach((member, k) => {
        places[member] = {
          "run": r,
          "index": k,
          "count": run.count
        };
      });
    });
    return places;
  }

  // A floating bar's islands along it, from its sections' spans ({ start,
  // end }, the empty ones left out): each span grown by `gap` (its widgets'
  // room to the island's ends) within the limits, islands at most `merge`
  // apart joined. With `whole`, one island from limit to limit. Shaped like
  // pills ({ start, length, joinStart, joinEnd }; an island joins nothing),
  // so the pill code reads them.
  function islandRects(spans, gap, merge, limitStart, limitEnd, whole) {
    const rect = (start, end) => ({
          "start": start,
          "length": end - start,
          "joinStart": false,
          "joinEnd": false
        });
    if (whole)
      return [rect(limitStart, limitEnd)];
    const grown = spans.map(span => ({
          "start": Math.max(limitStart, span.start - gap),
          "end": Math.min(limitEnd, span.end + gap)
        })).sort((a, b) => a.start - b.start);
    return root._mergeSpans(grown, merge).map(m => rect(m.start, m.end));
  }

  // The stretches as drawn on `rects` (the pills along a bar `length`
  // long): one per pill reaching past its ends or squared, { index,
  // start, end, squareStart, squareEnd, joinStart, joinEnd }, the
  // stretches on it combined (stretchOf). One stretched on to an end to
  // join the edge there joins it once it's reached it.
  function shownStretches(rects, stretches, length) {
    const shown = [];
    (rects ?? []).forEach((rect, i) => {
      const target = root.stretchOf(stretches, i);
      if (!target)
        return;
      const start = Math.min(rect.start, target.start), end = Math.max(rect.start + rect.length, target.end);
      if (start >= rect.start && end <= rect.start + rect.length && !target.squareStart && !target.squareEnd)
        return;
      shown.push({
        "index": i,
        "start": start,
        "end": end,
        "squareStart": target.squareStart,
        "squareEnd": target.squareEnd,
        "joinStart": target.joinStart && start <= 0.5,
        "joinEnd": target.joinEnd && end >= length - 0.5
      });
    });
    return shown;
  }

  // The pill a stretch stands on, as an index into `rects` (the pills
  // now): its `index`, unless it carries its pill at rest (`pill`, {
  // start, length }) and that's no longer there, where an end reach's stub
  // came or went before the stretch was sent again; then the pill over
  // where that one was, or -1.
  function pillIndex(rects, stretch) {
    const i = stretch.index;
    const pill = stretch.pill;
    const at = (rects ?? [])[i];
    if (!pill || at && Math.abs(at.start - pill.start) <= 0.5 && Math.abs(at.length - pill.length) <= 0.5)
      return at ? i : -1;
    const mid = pill.start + pill.length / 2;
    return (rects ?? []).findIndex(r => r.start <= mid && mid <= r.start + r.length);
  }

  // `stretches` on the pills they stand on now (pillIndex), any whose
  // pill has gone left out
  function onPills(rects, stretches) {
    return (stretches ?? []).map(st => {
      const i = root.pillIndex(rects, st);
      return i === st.index ? st : i < 0 ? null : Object.assign({}, st, {
        "index": i
      });
    }).filter(st => st !== null);
  }

  // The pill and island ends squared for a surface whose wall runs on
  // from them past the bar's inner edge (a popout flush to the end, a
  // submenu joined straight into it, a popout on the perpendicular edge
  // an end reach runs a pill on to), from the `stretches` as sent, where
  // `shapes` (stretchIslands) draws them squared. Each casts as if that
  // wall ran on (`source`, a copy of the end past the inner edge in the
  // shadow's source, wide: a thin strip's blur is much weaker), and is cut
  // past the inner edge beside it, where the surface's shadow, cast the
  // same way from its side (AttachedSurface), takes over: both at full
  // strength where they meet, with no step. It's cut under the surface too
  // (`holes`), as far as the run-on's shadow spreads (the surface casts
  // there), or it glows round the run-on while the surface slides. None of
  // it reaches past the surface's box (a stretch's `box`, { start, end };
  // without one, the stretch itself: an end reach's pill runs the length
  // of its surface). All only while the surface is out over the stroke
  // (a stretch's `covered`): squared before it slid out, the pill's own
  // wall lost its shadow.
  // `g`: { reach (the shadow's), across (the bar's depth), inner (where
  // its inner edge is across it), near (a left or top bar) }.
  // -> [{ source, holes }], each area { along, length, from, deep }
  // (`from`..`from + deep` across the bar).
  function flushEnds(stretches, shapes, g) {
    const reach = g.reach, inner = g.inner, near = g.near;
    const area = (along, length, from, deep) => ({
          "along": along,
          "length": length,
          "from": from,
          "deep": deep
        });
    // From the inner edge out, past the bar's far side
    const outward = (along, length) => area(along, length, near ? inner : -reach, near ? g.across - inner + reach : inner + reach);
    // `room`: how far the surface's box reaches in from the end
    const end = (at, atStart, room) => {
      const length = Math.min(room, reach * 2), under = Math.min(room, length + reach);
      return {
        "source": area(atStart ? at : at - length, length, near ? inner : inner - reach, reach),
        "holes": [outward(atStart ? at - reach : at, reach), outward(atStart ? at : at - under, under)]
      };
    };
    // ...where the pill or island is drawn ending there, squared
    const drawn = (at, atStart) => (shapes ?? []).some(r => (atStart ? r.squareStart : r.squareEnd) && Math.abs((atStart ? r.start : r.start + r.length) - at) <= 1);
    const ends = [];
    (stretches ?? []).forEach(st => {
      if (st.covered === false)
        return;
      const box = st.box ?? st;
      if (st.squareStart && box.end > st.start && drawn(st.start, true))
        ends.push(end(st.start, true, box.end - st.start));
      if (st.squareEnd && st.end > box.start && drawn(st.end, false))
        ends.push(end(st.end, false, st.end - box.start));
    });
    return ends;
  }

  // The stretches on pill `index` (each { index, start, end, squareStart,
  // squareEnd, joinStart, joinEnd }: one per surface standing on it) as
  // one, or null. An end is squared (or joins the perpendicular edge) when
  // a stretch reaching furthest that way does (any of them, on a tie).
  function stretchOf(stretches, index) {
    const on = (stretches ?? []).filter(s => s?.index === index);
    if (on.length === 0)
      return null;
    const start = Math.min(...on.map(s => s.start));
    const end = Math.max(...on.map(s => s.end));
    return {
      "index": index,
      "start": start,
      "end": end,
      "squareStart": on.some(s => s.start === start && (s.squareStart ?? false)),
      "squareEnd": on.some(s => s.end === end && (s.squareEnd ?? false)),
      "joinStart": on.some(s => s.start === start && (s.joinStart ?? false)),
      "joinEnd": on.some(s => s.end === end && (s.joinEnd ?? false))
    };
  }

  // The islands (or pills) as drawn: `stretches` (see stretchOf) grow
  // them to carry the surfaces open on them, each then joining any it
  // comes within `merge` of. { start, length, joinStart, joinEnd,
  // squareStart, squareEnd }: a squared end has its inner corner square,
  // where a popout runs flush into it; a joined one (a pill's) meets the
  // perpendicular edge, as does a pill stretched on to it to join it
  // (the stretch's joinStart/joinEnd). A stretch may reach past the pills
  // before or after its own, so they're merged in order of where they start.
  function stretchIslands(rects, stretches, merge) {
    const spans = rects.map((r, i) => {
      const stretch = root.stretchOf(stretches, i);
      return {
        "start": stretch ? Math.min(r.start, stretch.start) : r.start,
        "end": stretch ? Math.max(r.start + r.length, stretch.end) : r.start + r.length,
        "joinStart": (r.joinStart ?? false) || (stretch?.joinStart ?? false),
        "joinEnd": (r.joinEnd ?? false) || (stretch?.joinEnd ?? false),
        "squareStart": stretch?.squareStart ?? false,
        "squareEnd": stretch?.squareEnd ?? false
      };
    }).sort((a, b) => a.start - b.start);
    return root._mergeSpans(spans, merge).map(m => ({
          "start": m.start,
          "length": m.end - m.start,
          "joinStart": m.joinStart ?? false,
          "joinEnd": m.joinEnd ?? false,
          "squareStart": m.squareStart ?? false,
          "squareEnd": m.squareEnd ?? false
        }));
  }

  // Pills asked to reach an end of the bar, by surfaces joining them there
  // from the perpendicular edge (a pill bar meeting this one at a corner, a
  // popout whose side runs along this bar): `requests` [{ atStart, to,
  // straight }] each want a pill running from that end to `to`, joined to
  // the edge there (straight: flush off it, with no fillet into it, the
  // surface joining it drawing the corner instead). The end pill is
  // stretched there when it joins that end or comes within `merge` of
  // `to`; otherwise a pill up to `stub` long (no further than `to`, so it
  // grows from the corner with a request following a surface sliding
  // out) is added at the end and stretched. A request reaching nowhere
  // past the end asks nothing. `square`: the pill's corner at `to` is
  // square, where a surface's wall runs straight into it (when that
  // request reaches furthest).
  // -> { rects (pills with any stubs, in order), stretches (as stretchOf
  // takes them, indices into rects), straightStart, straightEnd }.
  function endReaches(rects, requests, length, merge, stub) {
    const out = rects.slice();
    const stretches = [];
    const at = atStart => (requests ?? []).filter(r => r && r.atStart === atStart && (atStart ? r.to > 0.5 : r.to < length - 0.5));
    const starts = at(true), ends = at(false);
    if (starts.length > 0) {
      const to = Math.max(...starts.map(r => r.to));
      const first = out[0];
      if (!first || !first.joinStart && first.start > to + merge)
        out.unshift({
          "start": 0,
          "length": Math.min(stub, length, to),
          "joinStart": true,
          "joinEnd": false
        });
    }
    if (ends.length > 0) {
      const to = Math.min(...ends.map(r => r.to));
      const last = out[out.length - 1];
      if (!last || !last.joinEnd && last.start + last.length < to - merge)
        out.push({
          "start": Math.max(0, length - stub, to),
          "length": Math.min(stub, length, length - to),
          "joinStart": false,
          "joinEnd": true
        });
    }
    if (starts.length > 0) {
      const first = out[0];
      const end = Math.max(first.start + first.length, Math.max(...starts.map(r => r.to)));
      stretches.push({
        "index": 0,
        "start": 0,
        "end": end,
        "joinStart": true,
        "squareEnd": starts.some(r => (r.square ?? false) && r.to >= end - 0.5)
      });
    }
    if (ends.length > 0) {
      const last = out[out.length - 1];
      const start = Math.min(last.start, Math.min(...ends.map(r => r.to)));
      stretches.push({
        "index": out.length - 1,
        "start": start,
        "end": length,
        "joinEnd": true,
        "squareStart": ends.some(r => (r.square ?? false) && r.to <= start + 0.5)
      });
    }
    return {
      "rects": out,
      "stretches": stretches,
      "straightStart": starts.some(r => r.straight ?? false),
      "straightEnd": ends.some(r => r.straight ?? false)
    };
  }

  // Sorted { start, end, ... } spans with those at most `merge` apart
  // joined, each keeping the flags of the span its ends came from
  function _mergeSpans(spans, merge) {
    const merged = [];
    spans.forEach(span => {
      const last = merged[merged.length - 1];
      if (!last || span.start - last.end > merge) {
        merged.push(Object.assign({}, span));
      } else if (span.end > last.end) {
        last.end = span.end;
        last.squareEnd = span.squareEnd;
        last.joinEnd = span.joinEnd;
      }
    });
    return merged;
  }

  // One section's widgets within `maxExtent`: measures [{pref, min,
  // priority}] and shown [bool] -> { sizes, offsets, visible }. Should even
  // the minimum sizes not fit, the lowest-priority widgets (the last listed
  // on a tie) are hidden; then elastic widgets shrink towards their minimum
  // sizes in proportion to how much they can give.
  function allocate(measures, shown, maxExtent, spacing) {
    const visible = shown.slice();
    const total = key => root.span(measures.filter((m, i) => visible[i]).map(m => m[key]), spacing);

    // Half a pixel of slack, so fractional text widths don't hide a widget
    const room = maxExtent + 0.5;
    while (total("min") > room) {
      let drop = -1;
      measures.forEach((m, i) => {
        if (visible[i] && (drop < 0 || m.priority <= measures[drop].priority))
          drop = i;
      });
      if (drop < 0)
        break;
      visible[drop] = false;
    }

    const pref = total("pref");
    const min = total("min");
    const squeeze = pref > room && pref > min ? Math.min(1, (pref - maxExtent) / (pref - min)) : 0;

    const sizes = measures.map((m, i) => visible[i] ? Math.floor(m.pref - (m.pref - m.min) * squeeze) : 0);
    const offsets = [];
    let pos = 0;
    sizes.forEach(size => {
      offsets.push(pos);
      if (size > 0)
        pos += size + spacing;
    });
    return {
      "sizes": sizes,
      "offsets": offsets,
      "visible": visible
    };
  }
}
