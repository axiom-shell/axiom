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
    }, 1, 3, 30, false, 20);
    compare([s.startCap, s.endCap, s.back, s.lead, s.trail], ["arrowIn", "arrowOut", 0, 15, 10]);
    const r = BarCells.cellSegment({
      "name": "rounded",
      "ends": "shaped"
    }, "separate", false, null, 0, 2, 30, false, 20);
    compare([r.startCap, r.endCap, r.lead, r.trail], ["round", "round", 0, 0]);
    compare(BarCells.cellSegment({
      "name": "tab",
      "ends": "shaped"
    }, "separate", false, null, 0, 2, 30, false, 20).startCap, "tab");
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
    }, "powerline", true, place, 0, 2, 30, false, 20);
    const last = BarCells.cellSegment({
      "name": "arrow",
      "ends": "shaped"
    }, "powerline", true, place, 1, 2, 30, false, 20);
    compare([first.startCap, first.endCap, first.back, first.lead, first.trail, first.seamStart], ["arrowIn", "arrowOut", 15, 0, 15, true]);
    compare([last.startCap, last.endCap, last.back, last.lead, last.trail], ["arrowIn", "arrowOut", 15, 0, 15]);
    // Alone, the first cell takes the run's start and the last its end
    const a = BarCells.cellSegment({
      "name": "slant",
      "ends": "shaped"
    }, "powerline", true, null, 0, 3, 30, false, 20);
    const z = BarCells.cellSegment({
      "name": "slant",
      "ends": "shaped"
    }, "powerline", true, null, 2, 3, 30, false, 20);
    compare([a.startCap, a.back, a.lead], ["slant", 0, 9]);
    compare([z.endCap, z.back, z.trail], ["slant", 10, 5 + 9]);
    // The run's last widget: its last cell gives the run's end cap
    const end = BarCells.cellSegment({
      "name": "arrow",
      "ends": "pointed"
    }, "powerline", false, {
      "index": 2,
      "count": 3
    }, 2, 3, 30, false, 20);
    compare([end.endCap, end.seamEnd], ["arrowOut", false]);
    // Opaque cells: a later one starts square beneath the one before; the
    // widget's first still fits against the cap before it
    const opaque = cell => BarCells.cellSegment({
        "name": "arrow",
        "ends": "shaped"
      }, "powerline", false, place, cell, 2, 30, true, 20);
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
    }, "merged", false, place, 0, 3, 30, false, 20);
    const middle = BarCells.cellSegment({
      "name": "slant",
      "ends": "shaped"
    }, "merged", false, place, 1, 3, 30, false, 20);
    compare([first.lead, first.trail, first.back], [9, 0, 0]);
    compare([middle.lead, middle.trail], [0, 0]);
    compare([middle.startCap, middle.endCap], ["slant", "slant"], "a box of its own: the caps it has alone");
    compare(middle.shownStart, "slant", "shown from its own start");
    const boxed = BarCells.cellSegment({
      "name": "slant",
      "ends": "shaped"
    }, "merged", true, place, 1, 3, 30, false, 20);
    compare([boxed.lead, boxed.trail, boxed.seamStart, boxed.seamEnd], [9, 9, false, false]);
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
    const shape = BarCells.cellShape(look, run, false, false, 0, 0, 2, 20);
    compare([shape.segment.startCap, shape.segment.back, shape.tab, shape.reachStart, shape.reachEnd], ["arrowIn", 15, null, 1, 2]);
    compare(BarCells.cellRoom(look, run, false, 0, 2, 20).lead, 15, "room from what's shown");
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

  // A cell's own box's outline: a double one in half-width lines
  function test_cell_outline() {
    compare(BarCells.cellOutline(null), null);
    compare(BarCells.cellOutline({
      "width": 2,
      "stroke": "solid"
    }), {
      "width": 2,
      "stroke": "solid"
    });
    compare(BarCells.cellOutline({
      "width": 3,
      "stroke": "double"
    }).width, 1);
    compare(BarCells.cellOutline({
      "width": 1,
      "stroke": "double"
    }).width, 1, "at least 1 px");
  }

  // A cell's room at an end keeps clear of the stroke drawn there: a
  // merged run's (the look's whole band), else its own box's (a double
  // in half-width lines); a box of its own in a run draws its stroke in
  // its fill's color, so only its caps count
  function test_cell_room_keeps_clear_of_the_stroke() {
    const shape = stroke => ({
          "name": "rounded",
          "ends": "shaped",
          "radius": 8,
          "outline": stroke ? {
            "width": 2,
            "stroke": stroke
          } : null
        });
    const place = {
      "index": 0,
      "count": 2
    };
    const lead = (stroke, grouping, boxed) => BarCells.cellSegment(shape(stroke), grouping, boxed, place, 0, 3, 30, false, 20).lead;
    // Separate: its own box, a double's three 1 px lines (8 - sqrt(5² - 3²))
    compare(lead("double", "separate", false), 4);
    compare(lead("solid", "separate", false), 3);
    compare(lead(null, "separate", false), 1);
    // Merged: the run's band (past the content's edge row: the corner)
    compare(lead("double", "merged", false), 8);
    compare(lead("solid", "merged", false), 3);
    // Merged, a box of its own: its caps alone
    compare(lead("double", "merged", true), 1);
    // Powerline: the cells' own boxes
    compare(lead("double", "powerline", false), 4);
    compare(lead("solid", "powerline", true), 1);
    // The run's middle keeps none
    compare(BarCells.cellSegment(shape("solid"), "merged", false, place, 1, 3, 30, false, 20).lead, 0);
    // Content 14 across (a number) lies inside the corner's straight
    // side: the stroke's band alone, a merged run's or its own box's
    compare(BarCells.cellSegment(shape("double"), "merged", false, place, 0, 3, 30, false, 14).lead, 6);
    compare(BarCells.cellSegment(shape("double"), "separate", false, place, 0, 3, 30, false, 14).lead, 3);
  }

  // A cell's box: round caps of its own radius alone, a segment's caps,
  // seams, tab and reach as one, in its own box's outline
  function test_cell_box() {
    const look = {
      "outline": {
        "width": 4,
        "stroke": "double"
      }
    };
    compare(BarCells.cellBox(look, null, 5), {
      "outline": {
        "startCap": "round",
        "endCap": "round",
        "radius": 5
      },
      "reach": null,
      "strokeWidth": 2,
      "strokeStyle": "double"
    });
    const shape = {
      "segment": {
        "startCap": "arrowIn",
        "endCap": "arrowOut",
        "seamStart": true,
        "seamEnd": false,
        "back": 13
      },
      "tab": null,
      "reachStart": 1,
      "reachEnd": 2
    };
    compare(BarCells.cellBox({
      "outline": null
    }, shape, 5), {
      "outline": {
        "startCap": "arrowIn",
        "endCap": "arrowOut",
        "seamStart": true,
        "seamEnd": false,
        "tab": null
      },
      "reach": {
        "back": 13,
        "near": 1,
        "far": 2
      },
      "strokeWidth": 0,
      "strokeStyle": "solid"
    });
  }

  // A bar look for the cell rules: a style's traits as they matter here
  function cellLookOf(grouping, traits) {
    return {
      "grouping": grouping,
      "traits": Object.assign({
        "boxed": true,
        "line": false,
        "tints": false,
        "boxedInRun": false,
        "cellOpaque": true
      }, traits)
    };
  }

  // How cells show: a box of their own off a run, in a merged run on the
  // bar only where they still box themselves; framed by a box or a line
  function test_cell_look() {
    const flags = (look, solid, onBar) => {
      const c = BarCells.cellLook(look, solid, onBar);
      return [c.boxedInRun, c.opaque, c.boxes, c.boxed, c.framed, c.slides, c.clearsActive];
    };
    const filled = cellLookOf("separate", {});
    compare(flags(filled, false, true), [false, true, true, true, true, true, false]);
    const merged = cellLookOf("merged", {});
    compare(flags(merged, false, true), [false, true, true, false, false, true, false], "the run draws their box");
    compare(flags(merged, false, false), [false, true, true, true, true, true, false], "a popout: not in a run");
    compare(flags(merged, true, true), [true, true, true, true, true, true, false], "solid boxes box themselves in a run");
    const underline = cellLookOf("separate", {
      "boxed": false,
      "line": true,
      "cellOpaque": false
    });
    compare(flags(underline, false, true), [false, false, false, false, true, true, false], "framed by the line");
    const plain = cellLookOf("separate", {
      "boxed": false,
      "cellOpaque": false
    });
    compare(flags(plain, false, true).slice(2), [false, false, false, false, false], "nothing frames them");
    compare(BarCells.cellLook(cellLookOf("separate", {
      "tints": true
    }), false, true).clearsActive, true, "a tint shows through");
    compare(flags(null, false, true), [false, false, false, false, false, false, false], "no look yet");
  }

  // The inner side is away from the bar's own screen edge
  function test_inner_edges() {
    compare(BarCells.innerEdges({
      "top": true
    }), Qt.BottomEdge);
    compare(BarCells.innerEdges({
      "bottom": true
    }), Qt.TopEdge);
    compare(BarCells.innerEdges({
      "left": true
    }), Qt.RightEdge);
    compare(BarCells.innerEdges({}), Qt.LeftEdge);
    compare(BarCells.innerEdges(null), Qt.LeftEdge);
  }

  // A cell's length at rest: square boxed, with numbers or app icons;
  // narrower for a dot or nothing straight on the bar
  function test_cell_length() {
    const bare = cellLookOf("separate", {
      "boxed": false
    });
    compare(BarCells.cellLength(cellLookOf("separate", {}), false, "dots", false, 26), 26, "boxed");
    compare(BarCells.cellLength(bare, true, "dots", false, 26), 26, "solid boxes");
    compare(BarCells.cellLength(bare, false, "numbers", false, 26), 26, "numbers");
    compare(BarCells.cellLength(bare, false, "dots", true, 26), 26, "app icons");
    compare(BarCells.cellLength(bare, false, "dots", false, 26), 16, "a dot on the bar");
  }
}
