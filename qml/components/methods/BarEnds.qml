pragma Singleton

import QtQuick

// What each end of a bar meets, where bars on perpendicular edges share a
// corner (pure). Hyprland hands a corner to the bar it arranges first,
// which the bars' layer rules decide (render.LayerRulesLua):
// solid bars, then the border, then pill bars, then floating ones, then
// transparent ones; between two of a kind the bar on the screen's shorter
// edge first (`shortEdge`: the side bars on a landscape monitor), so the
// longer bar gives up its length. The other bar's window then ends at the
// owner's reserved line.
//
// Bars may stack on one edge: the compositor arranges them outer first in
// that same order of kinds (stacksOn), each in what the ones before it
// left, and placeStack says where each lies; an end then meets the bars on
// the perpendicular edge it makes way for (endsOf).
//
// A bar is an enriched bar entry (BarsConfig.enrichBarConfig): `id`,
// `vertical`, `shortEdge`, `solid`, `kind`, `insideBorder`, `island`,
// `extent`, `floatingGap`, `floatingGapAuto`, `trim` (how much less than its
// extent it reserves, alone on its edge), `enabled`, `reserveSpace`,
// `monitor`, `top`/`bottom`/`left`/`right`.
// `opts`: { border (the screen border is on), borderWidth, margin (the
// border's width, Appearance.screenMargin), gapsOut (per edge name),
// floatGaps (what an Automatic float gap keeps, per edge name) }.
//
// An end is { kind, joinable, straight, held, reach, over, gap }:
// - kind: "border" (the border's stroke), "bare" (a bare screen edge),
//   "solidBar" (a solid bar's inner stroke, with the border off),
//   "pillBar" (a pill bar it yields to, as a pill bar itself: its end pill
//   merges into that bar's end pill, joining its far stroke as a solid
//   bar's; BarContainer has that bar grow one there if it has none) or
//   "bar" (a bar it yields to that has no stroke to join: a held end)
// - joinable: a pill at that end may join what's there; straight: the
//   join runs straight off it (a bare screen edge) rather than curving
//   into a stroke with a fillet
// - reach: how far the bar's window reaches past its end onto the stroke
//   there (BarPanel's margin), so bar-window 0 is the stroke's outer edge
// - held: the end keeps clear of the bar it yields to, as a surface held
//   off an edge: `over` is how far into the window that bar's frame line
//   (its inner edge) lies, `gap` how far past it the bar's end keeps
// - barId, from: see endsOf
QtObject {
  id: root

  // Who wins a shared corner: solid, then pills, then floating (bars and
  // pills held off the edge), then transparent
  function rank(bar) {
    if (bar.solid)
      return 3;
    if (bar.island)
      return 1;
    return bar.kind === "transparent" ? 0 : 2;
  }

  /**
   * How a full bar of `kind` ("solid", "pills" or "transparent") is built
   * across, from its widgets' `thickness` and its `edgePadding`, with
   * `opts` (border, borderWidth, margin). The body is the widgets and
   * their padding either side, at least as deep as the border's strip
   * laid over a solid bar's inner part (so no gap opens under it). A
   * solid bar is the body, and its own stroke deeper with the border off.
   * Pills are the body and their own far stroke, border on or off: a pill
   * bar on the border reaches back over the frame to the screen edge
   * (placeStack's outerReach), so solid and pills reserve the same and
   * place their widgets alike. A transparent bar lies on the border's
   * stroke, its widgets their padding past it.
   * -> { extent (from the window's outer edge), crossStart (where its
   *    widgets start, from there), pillDepth (how far a pill reaches from
   *    there; 0 off a pill bar) }
   */
  function crossGeometry(kind, thickness, edgePadding, opts) {
    const bw = opts.borderWidth;
    const body = Math.max(opts.border ? opts.margin - bw : 0, edgePadding + thickness + edgePadding);
    if (kind === "solid")
      return {
        "extent": body + (opts.border ? 0 : bw),
        "crossStart": (body - thickness) / 2,
        "pillDepth": 0
      };
    if (kind === "pills")
      return {
        "extent": body + bw,
        "crossStart": (body - thickness) / 2,
        "pillDepth": body + bw
      };
    const outer = opts.border ? bw : 0;
    return {
      "extent": outer + edgePadding + thickness + edgePadding,
      "crossStart": outer + edgePadding,
      "pillDepth": 0
    };
  }

  // Whether a bar lies along its screen's shorter edge (`width` × `height`
  // the screen's): a side bar on a landscape or square screen, a top or
  // bottom one on a portrait screen. Of two bars of a kind, it takes the
  // corner.
  function onShortEdge(vertical, width, height) {
    return vertical ? width >= height : width < height;
  }

  // Whether `bar` makes way at a corner for `other`, the bar on the
  // perpendicular edge there. A bar that reserves nothing pushes nothing
  // aside, so nothing yields to it.
  function yieldsTo(bar, other) {
    if (!other || other === bar || !other.enabled || !other.reserveSpace)
      return false;
    const a = root.rank(bar), b = root.rank(other);
    return b > a || (b === a && !bar.shortEdge && !!other.shortEdge);
  }

  // The edges a bar's start and end meet: top and bottom for a side bar,
  // left and right for a top or bottom one
  function endEdges(bar) {
    return bar.vertical ? ["top", "bottom"] : ["left", "right"];
  }

  // An end meeting the frame: the border's stroke, or a bare screen edge
  function _frame(bar, opts) {
    return {
      "kind": opts.border ? "border" : "bare",
      "joinable": true,
      "straight": !opts.border,
      "held": false,
      "reach": bar.insideBorder ? opts.borderWidth : 0,
      "over": 0,
      "gap": 0
    };
  }

  // An end joining the far stroke of the bar it yields to (`kind`
  // "solidBar" or "pillBar"), its window reaching back onto that stroke
  function _barStroke(kind, opts) {
    return {
      "kind": kind,
      "joinable": true,
      "straight": false,
      "held": false,
      "reach": opts.borderWidth,
      "over": 0,
      "gap": 0
    };
  }

  // What one end of `bar` meets, `other` the bar on the perpendicular
  // edge there (or null), `edge` that edge's name
  function endOf(bar, other, edge, opts) {
    if (!root.yieldsTo(bar, other))
      return root._frame(bar, opts);
    // A solid bar sits outside the border: a bar inside it meets the
    // border's stroke as ever, the border strip lying on the solid bar.
    // With the border off, it meets the solid bar's own inner stroke,
    // which it joins as it would the border (a fillet into it).
    if (other.solid) {
      if (opts.border || bar.solid)
        return root._frame(bar, opts);
      return root._barStroke("solidBar", opts);
    }
    // Two pill bars: the yielding one's window ends at the other's
    // reserved line, the far side of its pills, so it reaches back onto
    // their far stroke
    if (bar.kind === "pills" && other.kind === "pills")
      return root._barStroke("pillBar", opts);
    // Nothing to join: held clear of it. Its window ends at that bar's
    // reserved line, `trim` short of its inner edge (a transparent bar's
    // gaps_out). Its own float gap past that edge, or (Automatic, and for
    // bars without one) as far as windows start past it: a floating bar's
    // Automatic gap is floatGaps', the screen margin with no backend.
    const over = other.trim ?? 0;
    const auto = Math.max(0, ((bar.island ? opts.floatGaps : opts.gapsOut)?.[edge] ?? 0) - over);
    return {
      "kind": "bar",
      "joinable": false,
      "straight": false,
      "held": true,
      "reach": 0,
      "over": over,
      "gap": bar.island && !bar.floatingGapAuto ? bar.floatingGap : auto
    };
  }

  // { start, end } for a bar, `stacks` the bars on its screen by edge
  // name, outer first (stacksOn, each with its place: placeStack). An end
  // meets the bars on the perpendicular edge it makes way for, which
  // Hyprland arranges before it: a prefix of that edge's stack, as layer
  // rules order kinds the same way on every edge. What it meets is the
  // innermost of them, and its window ends past them all: `from` is how
  // far from that perpendicular screen edge (the border's margin too,
  // for a bar inside it), before its `reach`, and `barId` the id of the
  // bar it meets ("" for the frame).
  function endsOf(bar, stacks, opts) {
    const end = side => {
      const before = (stacks[side] ?? []).filter(other => root.yieldsTo(bar, other));
      const meets = before.length > 0 ? before[before.length - 1] : null;
      const from = before.reduce((sum, other) => sum + other.taken, opts.border && !bar.solid ? opts.margin : 0);
      return Object.assign(root.endOf(bar, meets, side, opts), {
        "barId": meets?.id ?? "",
        "from": from
      });
    };
    const [s, e] = root.endEdges(bar);
    return {
      "start": end(s),
      "end": end(e)
    };
  }

  function _edgeName(bar) {
    return bar.top ? "top" : bar.bottom ? "bottom" : bar.left ? "left" : "right";
  }

  // Where a kind of bar is arranged on its edge: solid bars (then the
  // border), pill bars, floating bars, floating pills, transparent bars.
  // Floating bars and floating pills share a layer rule, so their order
  // is LayerSlot's rank (layerRank).
  function kindIndex(bar) {
    return ["solid", "pills", "floating", "floatingPills", "transparent"].indexOf(bar.kind);
  }

  // The enabled bars on a screen (`monitor`) by edge name, each edge's
  // outer first, as the compositor arranges them: those reserving space
  // by kind (kindIndex), then those reserving none (laid out in what's
  // left once everything has reserved); within a kind, in config order
  function stacksOn(bars, monitor) {
    const stacks = {
      "top": [],
      "bottom": [],
      "left": [],
      "right": []
    };
    bars.forEach((bar, index) => {
      if (bar.enabled && bar.monitor === monitor)
        stacks[root._edgeName(bar)].push({
          "bar": bar,
          "index": index
        });
    });
    const key = e => [e.bar.reserveSpace ? 0 : 1, root.kindIndex(e.bar), e.index];
    const compare = (a, b) => {
      const ka = key(a), kb = key(b);
      return ka[0] - kb[0] || ka[1] - kb[1] || ka[2] - kb[2];
    };
    for (const edge in stacks)
      stacks[edge] = stacks[edge].sort(compare).map(e => e.bar);
    return stacks;
  }

  // The innermost enabled bar on each edge of a screen (`monitor`), or
  // null: what surfaces arranged after every bar (edge popouts, docks,
  // floating menus) meet
  function edgesOn(bars, monitor) {
    const stacks = root.stacksOn(bars, monitor);
    const edges = {};
    for (const edge in stacks)
      edges[edge] = stacks[edge].length > 0 ? stacks[edge][stacks[edge].length - 1] : null;
    return edges;
  }

  /**
   * Each bar of an edge's stack (stacksOn, outer first) with its place in
   * it, as the compositor arranges them: the reserving solid bars from
   * the screen edge, the border's margin, the other reserving bars, then
   * those reserving nothing, laid over what's left. Adds:
   *   stackIndex (0 outermost), innermost (the last on the edge),
   *   facesWindows (no bar inside it reserves space, so windows start
   *     right past it), trim (reserveTrim while it faces the windows; a
   *     bar with one reserving inside it reserves its whole extent),
   *   offBorder (the border's stroke isn't on it: a bar inside the border
   *     with another inside the border outside it, or a solid bar with
   *     the border on that the border's strip doesn't lie over, one with
   *     another solid bar inside it),
   *   zone (the exclusive zone it sets: BarPanel), taken (how much it
   *     reserves: its zone and its -borderWidth margin inside the border),
   *   outer (where its window's outer edge is, from the screen edge),
   *   outerReach (how far its window reaches back past where it's laid:
   *     onto the border's stroke for a bar inside the border, or for a
   *     pill bar on the border itself, over the whole frame: BarPanel's
   *     outer margin), stripCover (how far in from its window's outer
   *     edge the border's stroke lies under such a pill bar, where its
   *     pills hang off; else 0),
   *   frame (its inner side, from the screen edge: its inner edge, the
   *     border's stroke for a solid bar it lies over, or where a solid bar
   *     reserving nothing is laid, inside the border, which it covers)
   * Integrated edge menus' zones, arranged before it all, aren't counted.
   */
  function placeStack(stack, opts) {
    const w = opts.border ? opts.borderWidth : 0;
    const solids = stack.filter(bar => bar.solid && bar.reserveSpace);
    const strip = opts.border && solids.length > 0 ? solids[solids.length - 1] : null;
    const placed = [];
    let line = 0;
    let borderLaid = !opts.border;
    let insideBefore = false;
    stack.forEach((bar, index) => {
      // The border's strip is arranged after the reserving solid bars
      if (!borderLaid && !(bar.solid && bar.reserveSpace)) {
        line += opts.margin;
        borderLaid = true;
      }
      const next = stack.slice(index + 1).find(other => other.reserveSpace) ?? null;
      const facesWindows = next === null;
      // Only a bar facing the windows trims (a transparent bar's gaps_out,
      // its reserveTrim): one with a reserving bar inside it reserves its
      // whole extent. (Transparent bars are laid last, so nothing but
      // another transparent bar reserves inside one.)
      const trim = facesWindows ? bar.trim : 0;
      const onStrip = bar === strip;
      let zone = 0;
      if (bar.reserveSpace)
        zone = Math.max(0, (onStrip ? bar.extent - opts.margin + opts.borderWidth : bar.extent) - trim);
      // A bar inside the border reaches back onto its stroke. A pill bar
      // lying on the border itself reaches back over the whole frame to
      // the screen edge, its pills over the strip (`stripCover`, past
      // which they hang off the stroke), so it lies, reserves and places
      // its widgets as a solid bar would
      const onFrame = opts.border && bar.kind === "pills" && line === opts.margin;
      const reach = onFrame ? opts.margin : bar.insideBorder ? w : 0;
      const taken = zone > 0 ? zone - reach : 0;
      const outer = line - reach;
      let frame = outer + bar.extent;
      if (bar.solid && opts.border)
        frame = !bar.reserveSpace ? outer : onStrip ? outer + bar.extent + opts.borderWidth : outer + bar.extent;
      placed.push(Object.assign({}, bar, {
        "stackIndex": index,
        "innermost": index === stack.length - 1,
        "facesWindows": facesWindows,
        "trim": trim,
        "offBorder": opts.border && (bar.solid ? bar.reserveSpace && !onStrip : bar.insideBorder && insideBefore),
        "zone": zone,
        "taken": taken,
        "outer": outer,
        "frame": frame,
        "outerReach": reach,
        "stripCover": onFrame ? opts.margin - opts.borderWidth : 0
      }));
      if (bar.insideBorder && bar.reserveSpace)
        insideBefore = true;
      line += taken;
    });
    return placed;
  }

  /**
   * The bar a bar's own popouts grow out of, in its edge's placed stack
   * (placeStack, outer first): past every connected bar lying inside it,
   * the innermost of the run. A solid or pill bar connects to the
   * reserving solid or pill bar next inside it (the border's strip lies
   * between them, or the pills hang off the solid bar's stroke), so its
   * popout grows out of that bar as an edge popout would: from its pill,
   * stretched to carry it, or between them from the border. The run stops
   * at a transparent or floating bar (nothing joins them: covered), at
   * one reserving nothing and at a pill bar off the border (its pills
   * stroke no outer side). Any other bar is its own.
   */
  function connectedFrom(placed, bar) {
    const index = placed.findIndex(other => other.id === bar.id);
    if (index < 0)
      return bar;
    const connects = other => other.reserveSpace && (other.solid || (other.kind === "pills" && !other.offBorder));
    if (!connects(placed[index]))
      return placed[index];
    let last = index;
    while (last + 1 < placed.length && connects(placed[last + 1]))
      last++;
    return placed[last];
  }

  /**
   * Where the popouts of the bars outside a bar on its edge lie over it,
   * as spans along the edge in screen px ({ start, end }): what gives way
   * on it while they're open (its islands and sections fade, as a popout's
   * fill, drawn in the blur window under every bar, can't cover them).
   * `bar` and `stack` are placed (placeStack), `claims` PopoutManager's
   * entries (footprints in screen px), `zone` what integrated menus
   * reserve before the stack, `size` the screen's { width, height }. Only
   * bar popouts on its screen from a bar outside it that doesn't grow out
   * of it or a bar inside it (connectedFrom: their pills stretch to carry
   * them) count, and only where a footprint crosses its band across.
   */
  function coveredSpans(bar, stack, claims, screenName, zone, size) {
    const edge = root._edgeName(bar);
    const index = id => stack.findIndex(other => other.id === id);
    const own = index(bar.id);
    if (own < 0)
      return [];
    const covering = claims.filter(c => {
      if (c.kind !== "bar" || c.screen !== screenName || c.edge !== edge)
        return false;
      const from = index(c.barId);
      return from >= 0 && from < own && index(stack[from].attachId ?? stack[from].id) < own;
    });
    const near = zone + bar.outer, far = zone + bar.frame;
    const spans = [];
    covering.forEach(c => (c.footprint ?? []).forEach(r => {
        const across = edge === "top" ? [r.y, r.y + r.height] : edge === "bottom" ? [size.height - r.y - r.height, size.height - r.y] : edge === "left" ? [r.x, r.x + r.width] : [size.width - r.x - r.width, size.width - r.x];
        if (across[1] <= near || across[0] >= far)
          return;
        spans.push(bar.vertical ? {
          "start": r.y,
          "end": r.y + r.height
        } : {
          "start": r.x,
          "end": r.x + r.width
        });
      }));
    return spans;
  }

  /**
   * What an edge's placed stack (placeStack) leaves on it, from its screen
   * edge, integrated menus not counted: reserved (where windows start,
   * before gaps_out: the border's margin and every bar's taken space),
   * frame (the innermost bar's inner side, else the border's), corner
   * (where the border's rounded inner corner lies: past the reserving
   * solid bars, its strip on the last; 0 with the border off), strip (the
   * border's strip lies over a reserving solid bar), solidZone
   * (what the reserving solid bars reserve, before the border's strip),
   * insideTaken (what the bars inside the border take, which the
   * border's corner pieces are pulled back out past), inner (the
   * innermost bar, or null), facing (the innermost reserving bar, which
   * `reserved` ends at, else inner)
   */
  function edgeOf(placed, opts) {
    const margin = opts.border ? opts.margin : 0;
    const inner = placed.length > 0 ? placed[placed.length - 1] : null;
    const reserving = placed.filter(bar => bar.reserveSpace);
    const sum = (bars, key) => bars.reduce((total, bar) => total + bar[key], 0);
    const solids = placed.filter(bar => bar.solid && bar.reserveSpace);
    const solidZone = sum(solids, "zone");
    return {
      "reserved": margin + sum(placed, "taken"),
      "frame": inner ? inner.frame : margin,
      "corner": opts.border ? solidZone + margin : 0,
      "strip": opts.border && solids.length > 0,
      "solidZone": solidZone,
      "insideTaken": sum(placed.filter(bar => bar.insideBorder), "taken"),
      "inner": inner,
      "facing": reserving.length > 0 ? reserving[reserving.length - 1] : inner
    };
  }

  // Among the enabled bars on its screen edge sharing its layer rule (its
  // kind, floating bars and floating pills alike: the namespace
  // BarsConfig.layerNamespace names), where a bar maps: floating bars
  // before floating pills, then in config order, so bars of a kind on one
  // edge stack in that order wherever the compositor breaks a tie by map
  // order (LayerSlot's rank). Bars on other edges never meet across it,
  // so they keep no order (one remade doesn't map the others again).
  function layerRanks(bars) {
    const group = bar => root._edgeName(bar) + ":" + (bar.solid ? "solid" : bar.island ? "floating" : bar.kind);
    const ranks = bars.map(() => 0);
    const entries = bars.map((bar, index) => ({
          "bar": bar,
          "index": index
        })).filter(e => e.bar.enabled);
    entries.forEach(e => {
      ranks[e.index] = entries.filter(o => o.bar.monitor === e.bar.monitor && group(o.bar) === group(e.bar) && (root.kindIndex(o.bar) < root.kindIndex(e.bar) || (root.kindIndex(o.bar) === root.kindIndex(e.bar) && o.index < e.index))).length;
    });
    return ranks;
  }

  // The bars, each placed in its edge's stack (placeStack; a disabled bar
  // as if alone there), with its LayerSlot rank (`layerRank`, layerRanks),
  // its `ends` (endsOf) among the bars on its screen and the id of the bar
  // its popouts grow out of (`attachId`, connectedFrom)
  function withEnds(bars, opts) {
    const ranks = root.layerRanks(bars);
    const placedByBar = new Map();
    const monitors = [...new Set(bars.map(bar => bar.monitor))];
    for (const monitor of monitors) {
      const stacks = root.stacksOn(bars, monitor);
      for (const edge in stacks)
        root.placeStack(stacks[edge], opts).forEach(p => placedByBar.set(stacks[edge][p.stackIndex], p));
    }
    const placed = bars.map((bar, index) => Object.assign(placedByBar.get(bar) ?? root.placeStack([bar], opts)[0], {
        "layerRank": ranks[index]
      }));
    const stacksByMonitor = new Map();
    const stacksOf = monitor => {
      if (!stacksByMonitor.has(monitor))
        stacksByMonitor.set(monitor, root.stacksOn(placed, monitor));
      return stacksByMonitor.get(monitor);
    };
    return placed.map(bar => Object.assign(bar, {
        "ends": root.endsOf(bar, stacksOf(bar.monitor), opts),
        "attachId": root.connectedFrom(stacksOf(bar.monitor)[root._edgeName(bar)], bar).id
      }));
  }
}
