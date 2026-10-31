pragma Singleton

import QtQuick

// Pure geometry of the module grid shared by overlay pages, edge menus and
// the layouts editor. Modules are placed on a grid of quarter cards: each
// has a `place` { x, y, w, h } in grid units, four to a card. Holes are
// allowed; modules never overlap. OverlayConfig wraps these with the schema's module info.
QtObject {
  id: root

  // Card grid constants: internal design values, not user settings.
  // cardUnit: a card size where there's no screen to work one out from
  // (a menu whose monitor is gone) or only proportions matter (the
  // editor canvas, scaled to fit)
  readonly property int cardUnit: 500
  readonly property int cardSpacing: 20
  // The px a screen keeps clear on each side of its short one when
  // working out its card size (baseCard): fixed, so text and controls
  // growing (the Interface scale) never shrink the cards
  readonly property int screenMargin: 80
  // The largest a module's w or h may be (the schema's GridPlace maximum)
  readonly property int maxSpan: 32

  // A span of n grid units is n units plus the n - 1 gaps between them,
  // so span(4) is one card, span(2) half a card and span(8) two cards plus
  // the gap between them. `unit` is the card size, `gap` the px between
  // cards (cardSpacing unless given: a grid drawn zoomed has gapOf's).
  function unitOf(unit, gap) {
    return (unit - 3 * (gap ?? root.cardSpacing)) / 4;
  }

  function span(n, unit, gap) {
    return n * root.unitOf(unit, gap) + (n - 1) * (gap ?? root.cardSpacing);
  }

  // The card size (px) on a `width` × `height` screen at 100 %: two
  // cards (span(8): two cards and a gap) fill its short side less
  // screenMargin each side, so a monitor's cards are the same turned
  // either way. Every module grid starts from it (OverlayConfig.cardUnitOn)
  function baseCard(width, height) {
    return Math.max(1, (Math.min(width, height) - 2 * root.screenMargin - root.cardSpacing) / 2);
  }

  // What a grid's content is drawn at for a Module size of `scale` (a
  // factor): content lays out at the card size over it, so text and
  // controls grow and shrink with the cards only by the Module size,
  // never by the screen. 1 within 2 %, so it isn't resampled for nothing
  function zoomOf(scale) {
    return Math.abs(scale - 1) < 0.02 ? 1 : scale;
  }

  // The px between the cards of a grid drawn at `zoom`: the layout's,
  // drawn as its content is
  function gapOf(zoom) {
    return root.cardSpacing * zoom;
  }

  // A grid's own card size at card size `card` px, `gap` px between
  // cards: a double grid's (`fine`) units are split in two each way
  function gridUnitOf(card, fine, gap) {
    return fine ? root.fineUnit(card, gap) : Math.round(card);
  }

  // The card size of a double grid (`fineGrid`) at card size `unit`: two
  // of its units and the gap between them span one of `unit`'s, so places
  // scaled by scalePlace keep their size and spot exactly (half the card
  // would leave every span a little larger, the gaps staying the same).
  // Rounded down, so a doubled span is never longer than the one it doubles
  function fineUnit(unit, gap) {
    return Math.floor((unit - (gap ?? root.cardSpacing)) / 2);
  }

  // A size in grid units as cards: 4 → "1", 2 → "½", 5 → "1¼"
  function cards(units) {
    const whole = Math.floor(units / 4);
    const part = ["", "¼", "½", "¾"][units % 4];
    return part === "" ? String(whole) : (whole > 0 ? whole : "") + part;
  }

  // One grid unit plus the gap after it, in px, at card size `unit`
  function stepOf(unit, gap) {
    return root.unitOf(unit, gap) + (gap ?? root.cardSpacing);
  }

  // The lattice an edge menu's modules sit on along an edge `edgeLength`
  // px long, at card size `unit`: as many whole cells as fit between
  // `startPad` and `endPad`, centred there, then moved `shift` px towards
  // the end, `gap` px between cards. { origin (where cell 0 starts, in px
  // from the edge's start), step, cols (the cells of the centred run),
  // first, last (the cells wholly inside the room once moved), startPad }
  function menuLattice(edgeLength, unit, startPad, endPad, shift, gap) {
    const spacing = gap ?? root.cardSpacing;
    const step = root.stepOf(unit, spacing);
    const room = edgeLength - startPad - endPad;
    // A hair over (and under), so a room exactly n cells long holds n
    const cols = Math.max(0, Math.floor((room + spacing) / step + 0.001));
    const origin = startPad + (room - cols * step + spacing) / 2 + (shift ?? 0);
    return {
      "origin": origin,
      "step": step,
      "cols": cols,
      "first": Math.ceil((startPad - origin) / step - 0.001),
      "last": Math.floor((edgeLength - endPad - origin + spacing) / step + 0.001) - 1,
      "startPad": startPad
    };
  }

  // The cell a menu `units` cells long starts at on `lattice`: centred on
  // its run (the earlier of two middles), then `offset` cells towards the
  // end (negative: the start), kept on the lattice. null when it's longer
  // than the lattice.
  function menuCell(lattice, offset, units) {
    if (units > lattice.last - lattice.first + 1)
      return null;
    const cell = Math.floor((lattice.cols - units) / 2) + (offset ?? 0);
    return Math.max(lattice.first, Math.min(cell, lattice.last - units + 1));
  }

  // Where that menu starts along the edge, in px: at its cell, or at the
  // lattice's `startPad` when it's longer than the lattice (it scrolls)
  function alongStart(lattice, offset, units) {
    const cell = root.menuCell(lattice, offset, units);
    return cell === null ? lattice.startPad : lattice.origin + cell * lattice.step;
  }

  // The offset (see menuCell) that starts a menu `units` cells long at
  // `cell`
  function offsetFor(lattice, cell, units) {
    return cell - Math.floor((lattice.cols - units) / 2);
  }

  // The offsets that keep that menu on the lattice: { min, max }, both 0
  // when it's longer than the lattice
  function offsetRange(lattice, units) {
    if (units > lattice.last - lattice.first + 1)
      return {
        "min": 0,
        "max": 0
      };
    return {
      "min": root.offsetFor(lattice, lattice.first, units),
      "max": root.offsetFor(lattice, lattice.last - units + 1, units)
    };
  }

  // The screen (`width` × `height` px) around an edge menu with modules
  // reaching `bounds` (at card size `unit`) on `edge` ("left" | "right" |
  // "top" | "bottom"), starting `along` px along the edge and `across` px
  // in from it, `gap` px between cards. In grid units from the menu's grid
  // origin, as the editor draws it (its sides midway in the gaps):
  // { x, y, w, h }.
  function screenBox(width, height, unit, bounds, edge, along, across, gap) {
    const vertical = edge === "left" || edge === "right";
    const spacing = gap ?? root.cardSpacing;
    const step = root.stepOf(unit, spacing);
    const thick = vertical ? bounds.cols : bounds.rows;
    const thickPx = thick > 0 ? thick * step - spacing : 0;
    const acrossLen = vertical ? width : height;
    // The screen's start, in px from the grid's origin
    const alongFrom = -along;
    const acrossFrom = edge === "right" || edge === "bottom" ? thickPx + across - acrossLen : -across;
    const half = spacing / 2;
    return vertical ? {
      "x": (acrossFrom + half) / step,
      "y": (alongFrom + half) / step,
      "w": width / step,
      "h": height / step
    } : {
      "x": (alongFrom + half) / step,
      "y": (acrossFrom + half) / step,
      "w": width / step,
      "h": height / step
    };
  }

  // A place as the [x, y, w, h] rect modules get as `slotRect`
  function rectOf(place) {
    return [place?.x ?? 0, place?.y ?? 0, place?.w ?? 4, place?.h ?? 4];
  }

  // A rect's shape: "square" while its longer side is under 1.5 times the
  // shorter (so 4 × 3 and 5 × 4 are square), else "horizontal" or
  // "vertical". Modules pick their orientation from it; any module takes
  // any size
  function slotShape(rect) {
    const w = rect[2], h = rect[3];
    return Math.max(w, h) < Math.min(w, h) * 1.5 ? "square" : w > h ? "horizontal" : "vertical";
  }

  // How far the modules reach, in grid units
  function bounds(modules) {
    let cols = 0;
    let rows = 0;
    (modules ?? []).forEach(module => {
      const p = module?.place;
      if (!p)
        return;
      cols = Math.max(cols, p.x + p.w);
      rows = Math.max(rows, p.y + p.h);
    });
    return {
      "cols": cols,
      "rows": rows
    };
  }

  // The order modules are revealed in, top left to bottom right: each
  // module's rank (0 first), by the diagonal its top left corner is on,
  // then the higher one. Modules without a place come last
  function revealOrder(modules) {
    const key = module => {
      const p = module?.place;
      return p ? [p.x + p.y, p.y] : [Infinity, Infinity];
    };
    const sorted = (modules ?? []).map((module, index) => ({
          "key": key(module),
          "index": index
        })).sort((a, b) => a.key[0] - b.key[0] || a.key[1] - b.key[1] || a.index - b.index);
    const ranks = [];
    sorted.forEach((entry, rank) => ranks[entry.index] = rank);
    return ranks;
  }

  function overlaps(a, b) {
    return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
  }

  // Whether `place` is on the grid and clear of every module but the one at
  // `ignore` (an index; -1 for none)
  function canPlace(modules, place, ignore) {
    if (!place || place.x < 0 || place.y < 0 || place.w < 1 || place.h < 1)
      return false;
    return !(modules ?? []).some((module, i) => i !== ignore && module?.place && root.overlaps(module.place, place));
  }

  // The first free w × h spot in reading order within the modules' bounds
  // (at least `minCols` wide), else to the right of them
  function firstFree(modules, w, h, minCols) {
    const b = root.bounds(modules);
    const cols = Math.max(b.cols, minCols ?? 0, w);
    for (let y = 0; y + h <= b.rows; y++) {
      for (let x = 0; x + w <= cols; x++) {
        const place = {
          "x": x,
          "y": y,
          "w": w,
          "h": h
        };
        if (root.canPlace(modules, place, -1))
          return place;
      }
    }
    if (b.cols === 0)
      return {
        "x": 0,
        "y": 0,
        "w": w,
        "h": h
      };
    // Below when the grid is wider than tall, else to the right
    return b.cols > b.rows * 2 ? {
      "x": 0,
      "y": b.rows,
      "w": w,
      "h": h
    } : {
      "x": b.cols,
      "y": 0,
      "w": w,
      "h": h
    };
  }

  function _copy(place) {
    return place ? {
      "x": place.x,
      "y": place.y,
      "w": place.w,
      "h": place.h
    } : null;
  }

  // Whether `place` is clear of every one of `places` (null entries are
  // skipped) but the one at `ignore`, and inside `area` ({ cols, rows })
  // when there is one. Negative x and y are fine without an area.
  function clearOf(places, place, ignore, area) {
    if (!place || place.w < 1 || place.h < 1)
      return false;
    if (area && !root.within(place, area.cols, area.rows))
      return false;
    return !(places ?? []).some((p, i) => i !== ignore && p && root.overlaps(p, place));
  }

  // `places` (an array of { x, y, w, h }, null entries skipped) with the
  // one at `index` put at `place` (-1: a new one, appended), and every
  // other it lands on pushed along `dir` ({ x, y }, one of them 1 or -1)
  // just past it, cascading. The one put never moves: anything pushed
  // into it goes past it too. Returns a new array, or null when something
  // ends up outside `area` ({ cols, rows }, when given). Negative places
  // are fine without an area.
  function push(places, index, place, dir, area) {
    return root.pushGroup(places, [[index, place]], dir, area);
  }

  // push() for several put at once: `puts` is [[index, place], …] (index
  // -1: a new one, appended in order), none of them overlapping another.
  // None of them move; everything they land on is pushed past them.
  function pushGroup(places, puts, dir, area) {
    const out = (places ?? []).map(p => root._copy(p));
    const fixed = [];
    puts.forEach(([index, place]) => {
      const at = index < 0 ? out.length : index;
      out[at] = root._copy(place);
      fixed.push(at);
    });
    // Moves out[i] along dir until it's past out[j]
    const past = (i, j) => {
      const a = out[i];
      const b = out[j];
      if (dir.y > 0)
        a.y = b.y + b.h;
      else if (dir.y < 0)
        a.y = b.y - a.h;
      else if (dir.x > 0)
        a.x = b.x + b.w;
      else
        a.x = b.x - a.w;
    };
    const queue = fixed.slice();
    let guard = 0;
    while (queue.length > 0) {
      if (++guard > 10000)
        return null;
      const p = queue.shift();
      const pFixed = fixed.includes(p);
      for (let i = 0; i < out.length; i++) {
        if (i === p || !out[i] || !root.overlaps(out[i], out[p]))
          continue;
        if (fixed.includes(i)) {
          if (pFixed)
            continue;
          // Pushed into one put: it goes past that instead
          past(p, i);
          queue.push(p);
          break;
        }
        past(i, p);
        queue.push(i);
      }
    }
    if (area && out.some(p => p && !root.within(p, area.cols, area.rows)))
      return null;
    return out;
  }

  // The free rows between the one at `index` and the grid's edge
  // (`toward` -1: row 0; 1: `lastRow`), or the next module that way in its
  // columns
  function _freeTowards(places, index, toward, lastRow) {
    const cur = places[index];
    const inColumns = places.filter((p, j) => j !== index && p && p.x < cur.x + cur.w && cur.x < p.x + p.w);
    const free = toward < 0 ? cur.y - Math.max(0, ...inColumns.filter(p => p.y + p.h <= cur.y).map(p => p.y + p.h)) : Math.min(lastRow, ...inColumns.filter(p => p.y >= cur.y + cur.h).map(p => p.y)) - (cur.y + cur.h);
    return Math.max(0, free);
  }

  // How the one at `index` grows by `rows` alone (grown()): { up, down },
  // the rows it takes above and below its place
  function growthAround(places, index, rows, towards) {
    const toward = towards === 1 ? 1 : -1;
    const lastRow = root.bounds((places ?? []).map(p => ({
          "place": p
        }))).rows;
    if (!places?.[index] || rows <= 0)
      return {
        "up": 0,
        "down": 0
      };
    const take = Math.min(rows, root._freeTowards(places, index, toward, lastRow));
    return toward < 0 ? {
      "up": take,
      "down": rows - take
    } : {
      "up": rows - take,
      "down": take
    };
  }

  // `places` (nulls skipped) with some grown taller: `growth[i]` more rows
  // for the one at i (0 or missing: as placed). Each first takes the free
  // rows in its columns towards the grid's edge (`towards`: -1, up to row
  // 0, the default; 1, down to the grid's last row), then grows the rest
  // away from it, pushing what it then overlaps on away just past it,
  // cascading: modules beyond it in its columns move, others stay. Grown
  // nearest the edge first, so one pushed by another grows from where it
  // lands. Shifted back so no place is above row 0. Returns a new array.
  function grown(places, growth, towards) {
    const toward = towards === 1 ? 1 : -1;
    let out = (places ?? []).map(p => root._copy(p));
    const lastRow = root.bounds(out.map(p => ({
          "place": p
        }))).rows;
    const order = out.map((p, i) => i).filter(i => out[i] && (growth?.[i] ?? 0) > 0).sort((a, b) => toward < 0 ? out[a].y - out[b].y || out[a].x - out[b].x : (out[b].y + out[b].h) - (out[a].y + out[a].h) || out[a].x - out[b].x);
    for (const i of order) {
      const cur = out[i];
      const take = Math.min(growth[i], root._freeTowards(out, i, toward, lastRow));
      const rest = growth[i] - take;
      const put = root._copy(cur);
      put.h += growth[i];
      // Up by what it takes towards a top edge, or by what it grows away
      // from a bottom one
      put.y -= toward < 0 ? take : rest;
      if (put.h > root.maxSpan) {
        if (toward > 0)
          put.y += put.h - root.maxSpan;
        put.h = root.maxSpan;
      }
      out = root.pushGroup(out, [[i, put]], {
        "x": 0,
        "y": -toward
      }) ?? out;
    }
    const top = Math.min(0, ...out.filter(p => p).map(p => p.y));
    if (top < 0)
      out.forEach(p => {
        if (p)
          p.y -= top;
      });
    return out;
  }

  // The smallest place covering every one of `places` (nulls skipped),
  // else null
  function cover(places) {
    const list = (places ?? []).filter(p => p);
    if (list.length === 0)
      return null;
    const x = Math.min(...list.map(p => p.x));
    const y = Math.min(...list.map(p => p.y));
    return {
      "x": x,
      "y": y,
      "w": Math.max(...list.map(p => p.x + p.w)) - x,
      "h": Math.max(...list.map(p => p.y + p.h)) - y
    };
  }

  // The best free spot for a module of size `want` ([w, h]) dropped with
  // the pointer on `cell` ({ x, y }): the largest down to `min` ([w, h])
  // that covers the cell, clear of `places` (and inside `area`, when
  // given). Among equal sizes, the one closest to `want`'s shape, then the
  // one most nearly centred on the cell. Null when the cell is taken or
  // nothing fits.
  function fitPlace(places, cell, want, min, area) {
    const one = {
      "x": cell.x,
      "y": cell.y,
      "w": 1,
      "h": 1
    };
    if (!root.clearOf(places, one, -1, area))
      return null;
    const shape = Math.log(want[0] / want[1]);
    const sizes = [];
    for (let w = want[0]; w >= Math.max(1, min[0]); w--)
      for (let h = want[1]; h >= Math.max(1, min[1]); h--)
        sizes.push([w, h]);
    sizes.sort((a, b) => (b[0] * b[1] - a[0] * a[1]) || (Math.abs(Math.log(a[0] / a[1]) - shape) - Math.abs(Math.log(b[0] / b[1]) - shape)));
    for (const [w, h] of sizes) {
      const midX = Math.floor((w - 1) / 2);
      const midY = Math.floor((h - 1) / 2);
      let best = null;
      let bestDist = Infinity;
      for (let ox = 0; ox < w; ox++) {
        for (let oy = 0; oy < h; oy++) {
          const dist = (ox - midX) * (ox - midX) + (oy - midY) * (oy - midY);
          if (dist >= bestDist)
            continue;
          const place = {
            "x": cell.x - ox,
            "y": cell.y - oy,
            "w": w,
            "h": h
          };
          if (root.clearOf(places, place, -1, area)) {
            best = place;
            bestDist = dist;
          }
        }
      }
      if (best)
        return best;
    }
    return null;
  }

  // `place` resized by dragging its `handle` (the sides it moves: "n",
  // "ne", "e", "se", "s", "sw", "w", "nw") `dx`, `dy` units: the opposite
  // sides stay put, and each span stays between 1 and maxSpan
  function resizeFrom(place, handle, dx, dy) {
    const out = root._copy(place);
    const clamp = n => Math.max(1, Math.min(root.maxSpan, n));
    if (handle.includes("e"))
      out.w = clamp(place.w + dx);
    else if (handle.includes("w")) {
      out.w = clamp(place.w - dx);
      out.x = place.x + place.w - out.w;
    }
    if (handle.includes("s"))
      out.h = clamp(place.h + dy);
    else if (handle.includes("n")) {
      out.h = clamp(place.h - dy);
      out.y = place.y + place.h - out.h;
    }
    return out;
  }

  // `place` on a grid with units split in two each way (`finer`), or
  // merged back in pairs: it keeps its spot and size. Merging rounds each
  // edge, so modules that met still meet; a span stays at least 1 and at
  // most maxSpan.
  function scalePlace(place, finer) {
    if (finer)
      return {
        "x": place.x * 2,
        "y": place.y * 2,
        "w": Math.min(root.maxSpan, place.w * 2),
        "h": Math.min(root.maxSpan, place.h * 2)
      };
    const x = Math.round(place.x / 2);
    const y = Math.round(place.y / 2);
    return {
      "x": x,
      "y": y,
      "w": Math.max(1, Math.round((place.x + place.w) / 2) - x),
      "h": Math.max(1, Math.round((place.y + place.h) / 2) - y)
    };
  }

  // Whether `place` lies wholly inside a `cols` × `rows` grid
  function within(place, cols, rows) {
    return !!place && place.x >= 0 && place.y >= 0 && place.x + place.w <= cols && place.y + place.h <= rows;
  }

  // The first free w × h spot in reading order inside a `cols` × `rows`
  // grid (a lock screen's), else null
  function firstFreeIn(modules, w, h, cols, rows) {
    for (let y = 0; y + h <= rows; y++) {
      for (let x = 0; x + w <= cols; x++) {
        const place = {
          "x": x,
          "y": y,
          "w": w,
          "h": h
        };
        if (root.canPlace(modules, place, -1))
          return place;
      }
    }
    return null;
  }

  // A screen layout's grid (a ScreenGrid { columns, rows, fine }: the
  // lock screen's, the greeter's, a desktop layout's) in the units its
  // places use: columns × rows, each split in two with `fine`. { cols, rows }
  // reads: Desktop.items.grid, Lockscreen.layout.grid, Greeter.layout.grid
  function screenGrid(grid) {
    const scale = grid?.fine ? 2 : 1;
    return {
      "cols": (grid?.columns ?? 0) * scale,
      "rows": (grid?.rows ?? 0) * scale
    };
  }

  // The card size at which a `cols` × `rows` grid fits `width` × `height`
  // px with `margin` px all round (a lock screen's grid on its screen),
  // its gaps `ratio` px per px of card size: the axis with less room
  // decides, and stretching (trackSizes) fills the other
  function latticeUnit(cols, rows, width, height, margin, ratio) {
    // The px `count` units and their gaps take, per px of card size
    const per = count => count * (1 - 3 * ratio) / 4 + (count - 1) * ratio;
    const fit = (count, room) => (room - 2 * margin) / per(Math.max(1, count));
    return Math.max(1, Math.floor(Math.min(fit(cols, width), fit(rows, height))));
  }

  // How many units at card size `unit` (`gap` px between cards) fit
  // `width` × `height` px with `margin` px all round: a screen layout's
  // grid on a screen, { cols, rows }, at least one each way. Each count
  // is even (rounded down; a lone unit stays one), so the screen's centre
  // falls between units and the editor's centre guides between cells
  function screenLattice(unit, width, height, margin, gap) {
    const spacing = gap ?? root.cardSpacing;
    const step = root.stepOf(unit, spacing);
    const fit = room => root.evenCount(Math.max(1, Math.floor((room - 2 * margin + spacing) / step)), false);
    return {
      "cols": fit(width),
      "rows": fit(height)
    };
  }

  // `count` (at least 1) made even, so a grid's middle falls between
  // units: rounded down, or up with `up`; 1 stays 1
  function evenCount(count, up) {
    if (count <= 1 || count % 2 === 0)
      return count;
    return up ? count + 1 : count - 1;
  }

  // The groups of `places` that touch or overlap (sharing some length of
  // an edge; a corner alone doesn't join a module in a corner to the
  // middle), each [indices], so a stack of modules moves as one. Null
  // places are left out
  function touchingGroups(places) {
    const list = places ?? [];
    const group = list.map((_, i) => i);
    const find = i => group[i] === i ? i : (group[i] = find(group[i]));
    const meet = (a, aLen, b, bLen) => a <= b + bLen && b <= a + aLen;
    const share = (a, aLen, b, bLen) => a < b + bLen && b < a + aLen;
    const touch = (a, b) => (share(a.x, a.w, b.x, b.w) && meet(a.y, a.h, b.y, b.h)) || (share(a.y, a.h, b.y, b.h) && meet(a.x, a.w, b.x, b.w));
    for (let i = 0; i < list.length; i++)
      for (let j = i + 1; j < list.length; j++)
        if (list[i] && list[j] && touch(list[i], list[j]))
          group[find(i)] = find(j);
    const groups = {};
    list.forEach((place, i) => {
      if (!place)
        return;
      const key = find(i);
      (groups[key] = groups[key] ?? []).push(i);
    });
    return Object.keys(groups).map(key => groups[key]);
  }

  // `places` (null for none) placed on a `from` grid ({ cols, rows }),
  // moved onto a `to` grid. Modules that touch move as one group
  // (touchingGroups); on each axis a group keeps to the side its centre
  // is nearest (the first third: the start, the last third: the end),
  // else its centre keeps its share of the grid, so a corner stays a
  // corner and the middle the middle on a wider or smaller grid. Null
  // when that leaves one off `to` or over another
  function anchorPlaces(places, from, to) {
    const list = places ?? [];
    const shift = (pos, len, fromCount, toCount) => {
      const centre = pos + len / 2;
      if (centre < fromCount / 3)
        return 0;
      if (centre > fromCount * 2 / 3)
        return toCount - fromCount;
      return Math.round(centre * toCount / fromCount - len / 2) - pos;
    };
    const moved = list.map(() => null);
    root.touchingGroups(list).forEach(members => {
      const box = root.bounds(members.map(i => ({
            "place": list[i]
          })));
      const left = Math.min(...members.map(i => list[i].x));
      const top = Math.min(...members.map(i => list[i].y));
      const dx = shift(left, box.cols - left, from.cols, to.cols);
      const dy = shift(top, box.rows - top, from.rows, to.rows);
      members.forEach(i => moved[i] = {
          "x": list[i].x + dx,
          "y": list[i].y + dy,
          "w": list[i].w,
          "h": list[i].h
        });
    });
    const placed = moved.filter(place => place !== null);
    if (placed.some(place => !root.within(place, to.cols, to.rows)))
      return null;
    for (let i = 0; i < placed.length; i++)
      for (let j = i + 1; j < placed.length; j++)
        if (root.overlaps(placed[i], placed[j]))
          return null;
    return moved;
  }

  // A screen layout's modules on a `width` × `height` px room at card size
  // `unit`, `margin` px all round: on the grid that fits there
  // (screenLattice; with `fine`, a double grid, its units split in two
  // each way, so it's always whole units), each kept to its nearest side
  // (anchorPlaces) from `from`, the grid they were placed on (in the same
  // units). When they don't fit that way the cards shrink, a step at a
  // time, until they do (on `from` itself at the latest, where nothing
  // moves), else as a last resort they stay on `from` (or as far as they
  // reach) fitted into the room (latticeUnit). Its content is drawn at
  // `zoom` (zoomOf its Module size), and shrunk cards shrink it and the
  // gaps with them. { cols, rows, unit (its cards' px), gap, zoom, places,
  // shrunk (smaller than `unit` asked) }
  function screenArrangement(places, from, unit, width, height, margin, fine, zoom) {
    const scale = fine ? 2 : 1;
    // The gap per px of a whole card, and a card's own size and zoom when
    // the whole card is `card` px
    const per = root.gapOf(zoom) / unit;
    const gridUnit = card => root.gridUnitOf(card, fine, per * card);
    const zoomAt = card => root.zoomOf(zoom * card / unit);
    const asked = gridUnit(unit);
    let card = unit;
    for (let step = 0; step < 40 && card > 4 * root.cardSpacing; step++) {
      const whole = root.screenLattice(card, width, height, margin, per * card);
      const lattice = {
        "cols": whole.cols * scale,
        "rows": whole.rows * scale
      };
      const anchored = root.anchorPlaces(places, from, lattice);
      if (anchored)
        return {
          "cols": lattice.cols,
          "rows": lattice.rows,
          "unit": gridUnit(card),
          "gap": per * card,
          "zoom": zoomAt(card),
          "places": anchored,
          "shrunk": step > 0
        };
      if (lattice.cols >= from.cols && lattice.rows >= from.rows)
        break;
      card *= 0.96;
    }
    // As far as they reach, each count made even in whole units as
    // screenLattice's are (rounded up, so every module still fits)
    const reached = root.layoutReach(places, from);
    const even = count => root.evenCount(Math.ceil(count / scale), true) * scale;
    const reach = {
      "cols": even(reached.cols),
      "rows": even(reached.rows)
    };
    // A double grid's units are (card - gap) / 2: its gap per px of unit
    const ratio = fine ? 2 * per / (1 - per) : per;
    const fitted = Math.min(asked, root.latticeUnit(reach.cols, reach.rows, width, height, margin, ratio));
    return {
      "cols": reach.cols,
      "rows": reach.rows,
      "unit": fitted,
      "gap": ratio * fitted,
      "zoom": root.zoomOf(zoom * fitted / asked),
      "places": places ?? [],
      "shrunk": fitted < asked
    };
  }

  // The grid `places` (null for none) placed on a `from` grid ({ cols,
  // rows }) take: `from`, or as far as they reach past it, at least one
  // unit each way
  function layoutReach(places, from) {
    const reach = root.bounds((places ?? []).filter(place => place).map(place => ({
          "place": place
        })));
    return {
      "cols": Math.max(from.cols, reach.cols, 1),
      "rows": Math.max(from.rows, reach.rows, 1)
    };
  }

  // Shifts the modules (in place) so the topmost and leftmost touch 0.
  // Returns the shift taken off, { x, y } (0, 0 when nothing moved).
  // `hold` ({ x, y }, each optional): on a held axis a gap before the
  // modules stays, and they're only shifted back off negative places.
  function normalize(modules, hold) {
    const placed = (modules ?? []).filter(module => module?.place);
    if (placed.length === 0)
      return {
        "x": 0,
        "y": 0
      };
    let minX = Math.min(...placed.map(module => module.place.x));
    let minY = Math.min(...placed.map(module => module.place.y));
    if (hold?.x)
      minX = Math.min(minX, 0);
    if (hold?.y)
      minY = Math.min(minY, 0);
    placed.forEach(module => {
      module.place.x -= minX;
      module.place.y -= minY;
    });
    return {
      "x": minX,
      "y": minY
    };
  }

  // The size of one grid unit across and down, and of the whole grid, for
  // `bounds` at card size `unit`. `stretch` ({ width, height, fit }, each
  // optional) is room to grow into: that axis's units share it evenly. A
  // grid never shrinks below its natural size, unless `fit`: then it takes
  // exactly the room, shrinking down to half a unit at the least. `gap`:
  // the px between cards (cardSpacing unless given), kept in the result
  function trackSizes(bounds, unit, stretch, gap) {
    const spacing = gap ?? root.cardSpacing;
    const size = root.unitOf(unit, spacing);
    const least = stretch?.fit ? size / 2 : size;
    const grow = (count, room) => count > 0 && room > 0 ? Math.max(least, (room - (count - 1) * spacing) / count) : size;
    const unitW = grow(bounds.cols, stretch?.width ?? 0);
    const unitH = grow(bounds.rows, stretch?.height ?? 0);
    return {
      "unitW": unitW,
      "unitH": unitH,
      "gap": spacing,
      "width": bounds.cols > 0 ? bounds.cols * unitW + (bounds.cols - 1) * spacing : 0,
      "height": bounds.rows > 0 ? bounds.rows * unitH + (bounds.rows - 1) * spacing : 0
    };
  }

  // A place's pixel rect for trackSizes' `sizes`
  function rectPx(place, sizes) {
    const spacing = sizes.gap ?? root.cardSpacing;
    return {
      "x": place.x * (sizes.unitW + spacing),
      "y": place.y * (sizes.unitH + spacing),
      "width": place.w * sizes.unitW + (place.w - 1) * spacing,
      "height": place.h * sizes.unitH + (place.h - 1) * spacing
    };
  }

  // How much an area `width` × `height` px with card size `unit` shrinks
  // modules reaching `bounds`: 1 where they fit
  function fitScale(bounds, width, height, unit) {
    const sizes = root.trackSizes(bounds, unit);
    return sizes.width <= 0 ? 1 : Math.min(1, width / sizes.width, height / sizes.height);
  }
  // The overlay's cards in `height` px of room (drawn px): `card` px,
  // content drawn at `zoom`, but never so big that a page two cards high
  // (span(8), its gap drawn at the zoom too) overflows the height. A page
  // too wide is shrunk on its own (OverlayPages.fitScale). { drawn, the
  // card size shown; unit, the size content lays out at (drawn / zoom);
  // zoom }. Rounded down where the height limits it, so a page two cards
  // high fits exactly rather than a pixel over (and shrunk by a hair)
  function overlayLayout(height, card, zoom) {
    const drawn = Math.max(1, Math.min(Math.round(card), Math.floor((height - root.gapOf(zoom)) / 2)));
    return {
      "drawn": drawn,
      "unit": Math.max(1, Math.floor(drawn / zoom + 1e-6)),
      "zoom": zoom
    };
  }

  // --- Edge menus on their screen ---

  // A menu's lattice along its edge, `edgeLength` px long (menuLattice,
  // moved by `menu.gridOffset`), `gap` px between its cards
  function latticeOf(menu, edgeLength, unit, startPad, endPad, gap) {
    return root.menuLattice(edgeLength, unit, startPad, endPad, menu.gridOffset, gap);
  }

  // How many cells a menu's modules (reaching `bounds`, else its own)
  // take along its edge
  function unitsAlong(menu, bounds) {
    const reach = bounds ?? root.bounds(menu.layout.modules);
    return menu.edge === "left" || menu.edge === "right" ? reach.rows : reach.cols;
  }

  // Whether a menu takes its whole edge, stretched along it: one set to
  // (`length` "edge"), and an integrated one always, as its strip spans
  // the edge
  function menuFillsEdge(menu) {
    return menu.length === "edge" || menu.mode === "integrated";
  }

  // Whether a gap before a menu's modules along its edge is kept: a
  // whole-edge floating menu's, laid out on purpose (the layouts editor
  // holds it). An integrated menu's modules start at its edge's start
  // (menuModules)
  function menuKeepsLead(menu) {
    return menu.length === "edge" && menu.mode !== "integrated";
  }

  // A menu's `modules` (its own by default) as it lays them out: one
  // taking its whole edge without keeping a lead (menuKeepsLead) moved
  // back along the edge to start at its first module, so an offset lone
  // module still spans the edge; others as placed
  function menuModules(menu, modules) {
    const list = modules ?? menu.layout.modules ?? [];
    if (!root.menuFillsEdge(menu) || root.menuKeepsLead(menu))
      return list;
    const key = menu.edge === "left" || menu.edge === "right" ? "y" : "x";
    const starts = list.filter(module => module?.place).map(module => module.place[key]);
    const lead = starts.length > 0 ? Math.min(...starts) : 0;
    if (lead <= 0)
      return list;
    return list.map(module => {
      if (!module?.place)
        return module;
      const place = Object.assign({}, module.place);
      place[key] -= lead;
      return Object.assign({}, module, {
        "place": place
      });
    });
  }

  // Where a menu's modules start along its edge, `edgeLength` px long: on
  // its lattice, `menu.offset` cells from centred (alongStart), or at
  // `startPad` when it takes the whole edge (menuFillsEdge)
  function menuAlong(menu, edgeLength, unit, startPad, endPad, gap) {
    if (root.menuFillsEdge(menu))
      return startPad;
    return root.alongStart(root.latticeOf(menu, edgeLength, unit, startPad, endPad, gap), menu.offset, root.unitsAlong(menu));
  }

  // Where a menu's modules (reaching `bounds`, at card size `unit`) sit on
  // a `screenWidth` × `screenHeight` screen, `gap` px between its cards,
  // its `frame` (EdgeMenuManager's frames) around them, in px: { along (from the edge's start), across
  // (from the edge), length, depth (the grid along and across the edge),
  // edgeLength, lattice (latticeOf), units (cells along the edge), cell
  // (where they start on the lattice: null when the menu takes its whole
  // edge or is longer than the lattice), frame, screenWidth, screenHeight }
  function menuPlacement(menu, bounds, unit, frame, screenWidth, screenHeight, gap) {
    const vertical = menu.edge === "left" || menu.edge === "right";
    const sizes = root.trackSizes(bounds, unit, null, gap);
    const edgeLength = vertical ? screenHeight : screenWidth;
    const lattice = root.latticeOf(menu, edgeLength, unit, frame.startPad, frame.endPad, gap);
    const units = root.unitsAlong(menu, bounds);
    const cell = root.menuFillsEdge(menu) ? null : root.menuCell(lattice, menu.offset, units);
    return {
      "along": cell === null ? frame.startPad : lattice.origin + cell * lattice.step,
      "across": frame.across,
      "length": vertical ? sizes.height : sizes.width,
      "depth": vertical ? sizes.width : sizes.height,
      "edgeLength": edgeLength,
      "lattice": lattice,
      "units": units,
      "cell": cell,
      "frame": frame,
      "screenWidth": screenWidth,
      "screenHeight": screenHeight
    };
  }

  // A menu as it sits on its screen (`place`, from menuPlacement), in
  // screen px: { rect (its box: the modules plus the frame's `after` all
  // round), modules: [{ type, rect }] } (rects { x, y, width, height }),
  // fitted to its edge when it takes the whole edge (as EdgeMenuBody:
  // menuFillsEdge, menuModules), `gap` px between its cards
  function menuOnScreen(menu, place, unit, gap) {
    const vertical = menu.edge === "left" || menu.edge === "right";
    const room = place.edgeLength - place.frame.startPad - place.frame.endPad;
    const modules = root.menuModules(menu);
    const stretch = !root.menuFillsEdge(menu) ? null : vertical ? {
      "height": room,
      "fit": true
    } : {
      "width": room,
      "fit": true
    };
    const sizes = root.trackSizes(root.bounds(modules), unit, stretch, gap);
    const depth = vertical ? sizes.width : sizes.height;
    const acrossAt = menu.edge === "right" ? place.screenWidth - place.across - depth : menu.edge === "bottom" ? place.screenHeight - place.across - depth : place.across;
    const x = vertical ? acrossAt : place.along;
    const y = vertical ? place.along : acrossAt;
    const pad = place.frame.after;
    return {
      "rect": {
        "x": x - pad,
        "y": y - pad,
        "width": sizes.width + pad * 2,
        "height": sizes.height + pad * 2
      },
      "modules": modules.map(module => {
        const r = root.rectPx(module.place, sizes);
        return {
          "type": module.type,
          "rect": {
            "x": x + r.x,
            "y": y + r.y,
            "width": r.width,
            "height": r.height
          }
        };
      })
    };
  }

  // How deep the band along a menu's edge is (`place`, from
  // menuPlacement): the strip an integrated menu reserves, else the room
  // the bars and border take, which the menu sits past
  function menuReservedDepth(place) {
    return place.frame.reserves ? place.across + place.depth + place.frame.after : place.frame.before;
  }

  // --- The layouts editor's canvas ---

  // The grid the editor draws for modules reaching `bounds`: `lead` units
  // before them and `trail` after (at least 8 × 4 units), or with a screen
  // (`screenBox`, from screenBox) reaching one unit past it all round.
  // { leadCols, leadRows (units before 0, 0), cols, rows (in all), view
  // (what canvasFit fits: { x, y, w, h } in units from 0, 0) }. The view
  // of a screen is the screen (and any grid past it) and a unit round it,
  // in fractions of a unit, so it stays put while the modules move on it.
  function canvasExtent(bounds, screenBox, lead, trail) {
    if (!screenBox) {
      const cols = lead + Math.max(bounds.cols, 8) + trail;
      const rows = lead + Math.max(bounds.rows, 4) + trail;
      return {
        "leadCols": lead,
        "leadRows": lead,
        "cols": cols,
        "rows": rows,
        "view": {
          "x": -lead,
          "y": -lead,
          "w": cols,
          "h": rows
        }
      };
    }
    // A hair under, so a side exactly on a unit doesn't add one
    const leadCols = Math.max(0, Math.ceil(-screenBox.x - 0.001)) + 1;
    const leadRows = Math.max(0, Math.ceil(-screenBox.y - 0.001)) + 1;
    const x = Math.min(screenBox.x - 1, -1);
    const y = Math.min(screenBox.y - 1, -1);
    return {
      "leadCols": leadCols,
      "leadRows": leadRows,
      "cols": leadCols + Math.max(bounds.cols, Math.ceil(screenBox.x + screenBox.w - 0.001)) + 1,
      "rows": leadRows + Math.max(bounds.rows, Math.ceil(screenBox.y + screenBox.h - 0.001)) + 1,
      "view": {
        "x": x,
        "y": y,
        "w": Math.max(screenBox.x + screenBox.w + 1, bounds.cols + 1) - x,
        "h": Math.max(screenBox.y + screenBox.h + 1, bounds.rows + 1) - y
      }
    };
  }

  // The view of that grid (canvasExtent) drawn centred in an area `width`
  // × `height` px, scaled from cardUnit to fit (at most
  // `maxScale`): { scale, step (a unit and the gap after it), gap,
  // unitSize, originX, originY (where unit 0, 0 sits) }
  function canvasFit(extent, width, height, maxScale) {
    const view = extent.view;
    const refStep = root.stepOf(root.cardUnit);
    const scale = Math.max(0.05, Math.min(maxScale, width / (view.w * refStep), height / (view.h * refStep)));
    const step = refStep * scale;
    const gap = root.cardSpacing * scale;
    return {
      "scale": scale,
      "step": step,
      "gap": gap,
      "unitSize": step - gap,
      "originX": (width - view.w * step + gap) / 2 - view.x * step,
      "originY": (height - view.h * step + gap) / 2 - view.y * step
    };
  }

  // A place ({ x, y, w, h } in units) on the canvas (`fit`, from
  // canvasFit), in px: { x, y, width, height }
  function canvasRect(fit, place) {
    return {
      "x": fit.originX + place.x * fit.step,
      "y": fit.originY + place.y * fit.step,
      "width": place.w * fit.unitSize + (place.w - 1) * fit.gap,
      "height": place.h * fit.unitSize + (place.h - 1) * fit.gap
    };
  }

  // A screen box (from screenBox) on the canvas, in px, its sides midway
  // in the gaps
  function canvasScreenRect(fit, box) {
    return {
      "x": fit.originX + box.x * fit.step - fit.gap / 2,
      "y": fit.originY + box.y * fit.step - fit.gap / 2,
      "width": box.w * fit.step,
      "height": box.h * fit.step
    };
  }

  // Where a w × h module dropped with the pointer at `x`, `y` (canvas px)
  // lands: the unit it's held by stays under the pointer. `grab`: where
  // it's held, in px from its top left, or null to hold it by the middle.
  // { x, y, w, h }
  function canvasDropPlace(fit, x, y, w, h, grab) {
    const col = Math.floor((x - fit.originX + fit.gap / 2) / fit.step);
    const row = Math.floor((y - fit.originY + fit.gap / 2) / fit.step);
    const grabCol = grab ? Math.max(0, Math.min(w - 1, Math.floor(grab.x / fit.step))) : Math.floor((w - 1) / 2);
    const grabRow = grab ? Math.max(0, Math.min(h - 1, Math.floor(grab.y / fit.step))) : Math.floor((h - 1) / 2);
    return {
      "x": col - grabCol,
      "y": row - grabRow,
      "w": w,
      "h": h
    };
  }

  // What a module's alignment is judged against: the bounded grid
  // (`area`, { cols, rows }) when there is one, else the cover of the
  // other modules' `places` (the indices in `exclude`, and nulls,
  // skipped). An edge menu's (`screen`, its screenBox, with its `edge`):
  // the screen along the edge, and the others' cover across it (with no
  // others, the excluded ones': nothing to centre across). { x, y, w, h }
  // in units (fractional along an edge menu's screen), else null
  function guideFrame(area, places, exclude, screen, edge) {
    if (area)
      return {
        "x": 0,
        "y": 0,
        "w": area.cols,
        "h": area.rows
      };
    const others = root.cover((places ?? []).filter((p, i) => !(exclude ?? []).includes(i)));
    if (!screen)
      return others;
    const across = others ?? root.cover(places);
    if (!across)
      return null;
    const vertical = edge === "left" || edge === "right";
    return {
      "x": vertical ? across.x : screen.x,
      "y": vertical ? screen.y : across.y,
      "w": vertical ? across.w : screen.w,
      "h": vertical ? screen.h : across.h
    };
  }

  // A place's lines on `axis` ("x" | "y"), in units: { start, end, centre }
  function _lines(place, axis) {
    const start = axis === "x" ? place.x : place.y;
    const size = axis === "x" ? place.w : place.h;
    return {
      "start": start,
      "end": start + size,
      "centre": start + size / 2
    };
  }

  // Where `place` lines up with the other `places` (the indices in
  // `exclude`, and nulls, skipped) and with `frame` (guideFrame): its
  // start, end or centre on an axis the same as one of theirs, or its
  // centre on the frame's. One guide per line, running over everything
  // aligned on it: [{ axis ("x": a vertical line at x = `at`; "y": a
  // horizontal one), kind ("start" | "end" | "centre"), at, from, to (its
  // extent along the other axis), frame (it's the frame's centre) }], all
  // in units
  function alignments(place, places, exclude, frame) {
    if (!place)
      return [];
    const out = [];
    const add = (axis, kind, at, other, isFrame) => {
      const along = axis === "x" ? "y" : "x";
      const mine = root._lines(place, along);
      const theirs = root._lines(other, along);
      const from = Math.min(mine.start, theirs.start);
      const to = Math.max(mine.end, theirs.end);
      const hit = out.find(g => g.axis === axis && g.kind === kind && g.at === at);
      if (hit) {
        hit.from = Math.min(hit.from, from);
        hit.to = Math.max(hit.to, to);
        hit.frame = hit.frame || isFrame;
      } else {
        out.push({
          "axis": axis,
          "kind": kind,
          "at": at,
          "from": from,
          "to": to,
          "frame": isFrame
        });
      }
    };
    (places ?? []).forEach((other, i) => {
      if (!other || (exclude ?? []).includes(i))
        return;
      ["x", "y"].forEach(axis => {
        const mine = root._lines(place, axis);
        const theirs = root._lines(other, axis);
        ["start", "end", "centre"].forEach(kind => {
          if (mine[kind] === theirs[kind])
            add(axis, kind, mine[kind], other, false);
        });
      });
    });
    if (frame) {
      ["x", "y"].forEach(axis => {
        const centre = root._lines(frame, axis).centre;
        if (Math.abs(root._lines(place, axis).centre - centre) < 0.001)
          add(axis, "centre", centre, frame, true);
      });
    }
    return out;
  }

  // The two centre lines of `box` ({ x, y, w, h }), as guides
  // (alignments), else []
  function centreGuides(box) {
    if (!box || box.w <= 0 || box.h <= 0)
      return [];
    return ["x", "y"].map(axis => {
      const along = root._lines(box, axis === "x" ? "y" : "x");
      return {
        "axis": axis,
        "kind": "centre",
        "at": root._lines(box, axis).centre,
        "from": along.start,
        "to": along.end,
        "frame": true
      };
    });
  }

  // The start on `axis` ("x" | "y") that centres `box` ({ x, y, w, h }) in
  // `frame` (guideFrame), else null: no box or frame, or it'd sit between
  // units (their sizes differ by an odd count, or an edge menu's screen
  // centre is off its lattice)
  function centredIn(box, frame, axis) {
    if (!box || !frame)
      return null;
    const at = axis === "x" ? frame.x + (frame.w - box.w) / 2 : frame.y + (frame.h - box.h) / 2;
    return Math.abs(at - Math.round(at)) > 0.001 ? null : Math.round(at);
  }

  // A guide (alignments) on the canvas (`fit`, from canvasFit) in px:
  // { x1, y1, x2, y2 }. A start lies on its units' leading side, an end on
  // their trailing one (before the gap), a centre midway
  function canvasGuide(fit, guide) {
    const across = guide.axis === "x";
    const pos = (origin, at) => origin + at * fit.step;
    const origin = across ? fit.originX : fit.originY;
    const at = pos(origin, guide.at) - (guide.kind === "start" ? 0 : guide.kind === "end" ? fit.gap : fit.gap / 2);
    const along = across ? fit.originY : fit.originX;
    const from = pos(along, guide.from);
    const to = pos(along, guide.to) - fit.gap;
    return across ? {
      "x1": at,
      "y1": from,
      "x2": at,
      "y2": to
    } : {
      "x1": from,
      "y1": at,
      "x2": to,
      "y2": at
    };
  }

  // The room between `place` and each side of `frame` (guideFrame) on the
  // canvas (`fit`): [{ side ("left" | "right" | "top" | "bottom"), units
  // (whole: rounded), exact (not rounded: an edge menu's screen side can
  // be between units), even (the opposite side has the same), x1, y1, x2,
  // y2 (a line across it, through the place's middle, in px) }], only
  // sides with room
  function canvasMargins(fit, place, frame) {
    if (!place || !frame)
      return [];
    const r = root.canvasRect(fit, place);
    const midX = r.x + r.width / 2;
    const midY = r.y + r.height / 2;
    const frameLeft = fit.originX + frame.x * fit.step;
    const frameTop = fit.originY + frame.y * fit.step;
    const frameRight = fit.originX + (frame.x + frame.w) * fit.step - fit.gap;
    const frameBottom = fit.originY + (frame.y + frame.h) * fit.step - fit.gap;
    const units = {
      "left": place.x - frame.x,
      "right": frame.x + frame.w - place.x - place.w,
      "top": place.y - frame.y,
      "bottom": frame.y + frame.h - place.y - place.h
    };
    const opposite = {
      "left": "right",
      "right": "left",
      "top": "bottom",
      "bottom": "top"
    };
    const lines = {
      "left": [frameLeft, midY, r.x, midY],
      "right": [r.x + r.width, midY, frameRight, midY],
      "top": [midX, frameTop, midX, r.y],
      "bottom": [midX, r.y + r.height, midX, frameBottom]
    };
    return ["left", "right", "top", "bottom"].filter(side => units[side] > 0.001).map(side => ({
          "side": side,
          "units": Math.round(units[side]),
          "exact": Math.abs(units[side] - Math.round(units[side])) < 0.001,
          "even": Math.abs(units[side] - units[opposite[side]]) < 0.001,
          "x1": lines[side][0],
          "y1": lines[side][1],
          "x2": lines[side][2],
          "y2": lines[side][3]
        }));
  }

  // The band `depth` px deep inside `rect` ({ x, y, width, height }) along
  // its `edge` side ("left" | "right" | "top" | "bottom")
  function edgeBand(rect, edge, depth) {
    switch (edge) {
    case "left":
      return {
        "x": rect.x,
        "y": rect.y,
        "width": depth,
        "height": rect.height
      };
    case "right":
      return {
        "x": rect.x + rect.width - depth,
        "y": rect.y,
        "width": depth,
        "height": rect.height
      };
    case "top":
      return {
        "x": rect.x,
        "y": rect.y,
        "width": rect.width,
        "height": depth
      };
    case "bottom":
      return {
        "x": rect.x,
        "y": rect.y + rect.height - depth,
        "width": rect.width,
        "height": depth
      };
    }
    return {
      "x": 0,
      "y": 0,
      "width": 0,
      "height": 0
    };
  }

  // A bar `thick` px wide centred on `rect`'s `edge` side, running along
  // `span`'s extent on that side (a rect; `rect` itself for the whole side)
  function edgeBar(rect, edge, span, thick) {
    const alongRows = edge === "left" || edge === "right";
    const across = edge === "left" ? rect.x : edge === "right" ? rect.x + rect.width : edge === "top" ? rect.y : rect.y + rect.height;
    const start = alongRows ? span.y : span.x;
    const length = alongRows ? span.height : span.width;
    return alongRows ? {
      "x": across - thick / 2,
      "y": start,
      "width": thick,
      "height": length
    } : {
      "x": start,
      "y": across - thick / 2,
      "width": length,
      "height": thick
    };
  }

  // Moves arr[from] to insertion index `to`, counted as if it were still
  // in place. Returns the index it lands at, or -1 for no move.
  function moveTo(arr, from, to) {
    if (!arr || from < 0 || from >= arr.length)
      return -1;
    let at = Math.max(0, Math.min(to, arr.length));
    if (at > from)
      at--;
    if (at === from)
      return -1;
    const [item] = arr.splice(from, 1);
    arr.splice(at, 0, item);
    return at;
  }
}
