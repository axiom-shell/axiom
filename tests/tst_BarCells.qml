import QtQuick
import QtTest
import qs.components.methods

// A widget's parts laid out as cells of the bar's run (BarCells)
TestCase {
  name: "BarCells"

  // Cells laid out as segments of the bar's run (Workspaces with its
  // Background off): separate, each alone in the shape's ends
  function test_separate_cells_are_each_alone() {
    const s = BarCells.cellSegment({
      "name": "arrow",
      "ends": "shaped"
    }, "separate", false, {
      "index": 1,
      "count": 3
    }, 1, 3, 30);
    compare([s.startCap, s.endCap, s.back, s.lead, s.trail], ["arrowIn", "arrowOut", 0, 15, 15]);
    const r = BarCells.cellSegment({
      "name": "rounded",
      "ends": "shaped"
    }, "separate", false, null, 0, 2, 30);
    compare([r.startCap, r.endCap, r.lead, r.trail], ["round", "round", 0, 0]);
    compare(BarCells.cellSegment({
      "name": "tab",
      "ends": "shaped"
    }, "separate", false, null, 0, 2, 30).startCap, "tab");
  }

  // Powerline: the cells chain on in the bar's chain, as one run with the
  // widget's neighbours
  function test_powerline_cells_chain_in_the_bars_chain() {
    // The widget second of three: its first cell fits against the cap
    // before it, never starts square beneath it (drawn over the bar's
    // backgrounds), and its cells end where the widget would
    const place = {
      "index": 1,
      "count": 3
    };
    const first = BarCells.cellSegment({
      "name": "arrow",
      "ends": "shaped"
    }, "powerline", true, place, 0, 2, 30);
    const last = BarCells.cellSegment({
      "name": "arrow",
      "ends": "shaped"
    }, "powerline", true, place, 1, 2, 30);
    compare([first.startCap, first.endCap, first.back, first.lead, first.trail, first.seamStart], ["arrowIn", "arrowOut", 15, 0, 15, true]);
    compare([last.startCap, last.endCap, last.back, last.lead, last.trail], ["arrowIn", "arrowOut", 15, 0, 15]);
    // Alone, the first cell takes the run's start and the last its end
    const a = BarCells.cellSegment({
      "name": "slant",
      "ends": "shaped"
    }, "powerline", true, null, 0, 3, 30);
    const z = BarCells.cellSegment({
      "name": "slant",
      "ends": "shaped"
    }, "powerline", true, null, 2, 3, 30);
    compare([a.startCap, a.back, a.lead], ["slant", 0, 5]);
    compare([z.endCap, z.back, z.trail], ["slant", 10, 5 + 5]);
    // The run's last widget: its last cell gives the run's end cap
    const end = BarCells.cellSegment({
      "name": "arrow",
      "ends": "pointed"
    }, "powerline", false, {
      "index": 2,
      "count": 3
    }, 2, 3, 30);
    compare([end.endCap, end.seamEnd], ["arrowOut", false]);
    // Opaque cells: a later one starts square beneath the one before; the
    // widget's first still fits against the cap before it
    const opaque = cell => BarCells.cellSegment({
        "name": "arrow",
        "ends": "shaped"
      }, "powerline", false, place, cell, 2, 30, true);
    compare([opaque(0).startCap, opaque(0).seamStart], ["arrowIn", true]);
    compare([opaque(1).startCap, opaque(1).back, opaque(1).seamStart], ["flat", 15, false]);
  }

  // Merged: the run draws the background, a cell keeps the run's end
  // room; one drawing a box of its own takes the caps it has alone
  function test_merged_cells_keep_the_runs_ends() {
    const place = {
      "index": 0,
      "count": 2
    };
    const first = BarCells.cellSegment({
      "name": "slant",
      "ends": "shaped"
    }, "merged", false, place, 0, 3, 30);
    const middle = BarCells.cellSegment({
      "name": "slant",
      "ends": "shaped"
    }, "merged", false, place, 1, 3, 30);
    compare([first.lead, first.trail, first.back], [5, 0, 0]);
    compare([middle.lead, middle.trail], [0, 0]);
    compare([middle.startCap, middle.endCap], ["slant", "slant"], "a box of its own: the caps it has alone");
    compare(middle.shownStart, "slant", "shown from its own start");
    const boxed = BarCells.cellSegment({
      "name": "slant",
      "ends": "shaped"
    }, "merged", true, place, 1, 3, 30);
    compare([boxed.lead, boxed.trail, boxed.seamStart, boxed.seamEnd], [5, 5, false, false]);
  }

  function test_cell_gap() {
    compare(BarCells.cellGap("powerline", 4), 0);
    compare(BarCells.cellGap("separate", 4), 4);
    compare(BarCells.cellGap("merged", 4), 4);
  }

  // Tab cells: the bar's fillet at the widget's ends, between cells no
  // more than half the gap, and the widget's bounds at its two ends
  function test_cell_tab() {
    const first = BarCells.cellTab(6, 30, 5, 4, true, [null, null], 0, 3);
    compare([first.start.flare, first.end.flare], [5, 2]);
    const middle = BarCells.cellTab(6, 30, 5, 4, true, [null, null], 1, 3);
    compare([middle.start.flare, middle.end.flare], [2, 2]);
    const bound = BarCells.cellTab(6, 30, 5, 20, true, [
      {
        "gap": 2,
        "radius": 10
      },
      {
        "gap": 2,
        "radius": 10
      }
    ], 2, 3);
    compare(bound.start.corner, null, "the bound is the widget's start, not this cell's");
    compare(bound.end.corner.radius, 10, "its end is the widget's");
    compare(BarCells.cellTab(6, 30, 5, 0, true, null, 1, 2).start.flare, 0, "no gap: square");
  }

  // An enriched bar as cellShape reads it: its look's shape and grouping,
  // its radius, thickness and side
  function cellBar(shape, grouping, fillet, extra) {
    return Object.assign({
      "look": {
        "shape": {
          "name": shape,
          "ends": "shaped",
          "tabFillet": fillet
        },
        "grouping": grouping
      },
      "radius": 6,
      "thickness": 30,
      "right": false,
      "bottom": false,
      "vertical": false
    }, extra ?? {});
  }

  // A cell's shape and room on a bar's look, from where its widget is
  // drawn and what it shows
  function test_cell_shape_and_room() {
    const look = cellBar("arrow", "powerline", 0);
    const run = {
      "sized": {
        "index": 0,
        "count": 2
      },
      "drawn": {
        "index": 1,
        "count": 2
      },
      "reachStart": 1,
      "reachEnd": 2,
      "tabLimits": [null, null]
    };
    const shape = BarCells.cellShape(look, run, false, false, 0, 0, 2);
    compare([shape.segment.startCap, shape.segment.back, shape.tab, shape.reachStart, shape.reachEnd], ["arrowIn", 15, null, 1, 2]);
    compare(BarCells.cellRoom(look, run, false, 0, 2).lead, 15, "room from what's shown");
    const tab = BarCells.cellShape(cellBar("tab", "separate", 0, {
      "bottom": true
    }), null, false, false, 4, 0, 1);
    compare([tab.segment.startCap, tab.tab.outerStart, tab.reachStart], ["tab", false, 0]);
  }

  // What a cell draws past its own bounds along the bar: back under the
  // cell before, and a flared tab's fillets past its sides, which every
  // clip holding cells keeps (cellMargins), the widget's own while it
  // resizes too (runDraws)
  function test_cells_draw_past_their_bounds() {
    const look = cellBar("tab", "separate", 5);
    const run = {
      "sized": null,
      "drawn": null,
      "reachStart": 4,
      "reachEnd": 0,
      "tabLimits": [null, null]
    };
    // The widget's ends take the bar's fillet, between cells half the gap
    const first = BarCells.cellShape(look, run, false, false, 4, 0, 3);
    const last = BarCells.cellShape(look, run, false, false, 4, 2, 3);
    compare([first.drawStart, first.drawEnd, last.drawStart, last.drawEnd], [5, 2, 2, 5]);
    compare(BarCells.cellMargins(first, last, false), {
      "left": 5,
      "top": 4,
      "right": 5,
      "bottom": 0
    });
    compare(BarCells.cellMargins(first, last, true), {
      "left": 4,
      "top": 5,
      "right": 0,
      "bottom": 5
    });
    compare(BarCells.runDraws(look, run), {
      "start": 5,
      "end": 5
    });
    // A powerline cell reaches back under the one before, nothing past its end
    const chain = cellBar("arrow", "powerline", 0);
    const placed = Object.assign({}, run, {
      "drawn": {
        "index": 1,
        "count": 3
      },
      "reachStart": 0
    });
    compare(BarCells.runDraws(chain, placed), {
      "start": 15,
      "end": 0
    });
    compare(BarCells.cellMargins(null, null, false), {
      "left": 0,
      "top": 0,
      "right": 0,
      "bottom": 0
    }, "no cells: nothing past it");
  }

  // Cells are hit in their boxes as drawn: a powerline's corners beside a
  // cell's end cap are the next cell's (its box shows there), the first
  // cell's reach back under the widget before is its own, and a tab's
  // reaches out to its edge
  function test_cells_hit_as_drawn() {
    const look = cellBar("arrow", "powerline", 0);
    const run = {
      "sized": null,
      "drawn": {
        "index": 1,
        "count": 3
      },
      "reachStart": 0,
      "reachEnd": 0,
      "tabLimits": [null, null]
    };
    // Two opaque cells 40 long: the second starts square beneath the
    // first, yet shows from the first's arrow
    const a = BarCells.cellShape(look, run, false, true, 0, 0, 2);
    const b = BarCells.cellShape(look, run, false, true, 0, 1, 2);
    compare([b.segment.startCap, b.segment.shownStart], ["flat", "arrowIn"]);
    // Near the shared end's edge (a at 39, b at -1): the arrow's point is a's, its corners b's
    verify(BarCells.cellContains(a, 39, 15, 40, 30, false), "the arrow's point");
    verify(!BarCells.cellContains(a, 39, 1, 40, 30, false), "a corner beside it isn't a's");
    verify(BarCells.cellContains(b, -1, 1, 40, 30, false), "it's the next cell's");
    verify(!BarCells.cellContains(b, -1, 15, 40, 30, false), "the point isn't the next cell's");
    // The first cell, back under the widget before, beside its cap
    verify(BarCells.cellContains(a, -14, 1, 40, 30, false));
    verify(!BarCells.cellContains(a, -14, 15, 40, 30, false));
    verify(!BarCells.cellContains(a, -16, 1, 40, 30, false), "no further back than it reaches");
    // Vertical: the same along y
    verify(BarCells.cellContains(b, 1, -1, 30, 40, true));
    verify(!BarCells.cellContains(a, 1, 39, 30, 40, true));
    // A tab cell reaches across out to its edge (4 before it), not along
    // into its fillets
    const tab = BarCells.cellShape(cellBar("tab", "separate", 5), Object.assign({}, run, {
      "reachStart": 4
    }), false, false, 4, 0, 2);
    verify(BarCells.cellContains(tab, 1, -3, 40, 30, false));
    verify(!BarCells.cellContains(tab, -1, -3, 40, 30, false));
    // No shape: its own box
    verify(BarCells.cellContains(null, 0, 0, 40, 30, false));
    verify(!BarCells.cellContains(null, 40, 0, 40, 30, false));
  }
}
