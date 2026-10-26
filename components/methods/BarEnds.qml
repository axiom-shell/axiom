pragma Singleton

import QtQuick

// What each end of a bar meets, where bars on perpendicular edges share a
// corner (pure). Hyprland hands a corner to the bar it arranges first,
// which the bars' layer rules decide (HyprLua.layerRulesLua):
// solid bars, then the border, then pill bars, then transparent ones, then
// floating ones; between two of a kind the bar on the screen's shorter
// edge first (`shortEdge`: the side bars on a landscape monitor), so the
// longer bar gives up its length. The other bar's window then ends at the
// owner's reserved line.
//
// A bar is an enriched bar entry (BarsConfig.enrichBarConfig): `vertical`,
// `shortEdge`, `solid`, `background`, `insideBorder`, `island`, `floatGap`,
// `floatGapAuto`, `trim` (how much less than its extent it reserves),
// `enabled`, `reserveSpace`, `monitor`, `top`/`bottom`/`left`/`right`.
// `opts`: { border (the screen border is on), borderWidth, gapsOut (per
// edge name) }.
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
QtObject {
  id: root

  // Who wins a shared corner: solid, then pills, then transparent, then
  // floating (bars and pills held off the edge)
  function rank(bar) {
    if (bar.solid)
      return 3;
    if (bar.island)
      return 0;
    return bar.background === "transparent" ? 1 : 2;
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
    if (bar.background === "pills" && other.background === "pills")
      return root._barStroke("pillBar", opts);
    // Nothing to join: held clear of it. Its window ends at that bar's
    // reserved line, `trim` short of its inner edge (a transparent bar's
    // gaps_out). Its own float gap past that edge, or (Automatic, and for
    // bars without one) as far as windows start past it.
    const over = other.trim ?? 0;
    const auto = Math.max(0, (opts.gapsOut?.[edge] ?? 0) - over);
    return {
      "kind": "bar",
      "joinable": false,
      "straight": false,
      "held": true,
      "reach": 0,
      "over": over,
      "gap": bar.island && !bar.floatGapAuto ? bar.floatGap : auto
    };
  }

  // { start, end } for a bar, `edges` the bars on its screen by edge name
  // (the first enabled one on each)
  function endsOf(bar, edges, opts) {
    const [s, e] = root.endEdges(bar);
    return {
      "start": root.endOf(bar, edges[s] ?? null, s, opts),
      "end": root.endOf(bar, edges[e] ?? null, e, opts)
    };
  }

  // The enabled bars on a screen (`monitor`) by edge name, the first on
  // each edge
  function edgesOn(bars, monitor) {
    const edges = {
      "top": null,
      "bottom": null,
      "left": null,
      "right": null
    };
    bars.forEach(bar => {
      if (!bar.enabled || bar.monitor !== monitor)
        return;
      const edge = bar.top ? "top" : bar.bottom ? "bottom" : bar.left ? "left" : "right";
      if (!edges[edge])
        edges[edge] = bar;
    });
    return edges;
  }

  // The bars, each with its `ends` (endsOf) among the bars on its screen
  function withEnds(bars, opts) {
    return bars.map(bar => Object.assign({}, bar, {
        "ends": root.endsOf(bar, root.edgesOn(bars, bar.monitor), opts)
      }));
  }
}
