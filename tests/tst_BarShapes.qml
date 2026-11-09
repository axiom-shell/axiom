import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "BarShapes"

  // The path's points as [x, y] pairs (arc radii and flags skipped)
  function points(path) {
    const out = [];
    const tokens = path.trim().split(/\s+/);
    for (let i = 0; i < tokens.length; ) {
      const op = tokens[i];
      if (op === "M" || op === "L") {
        out.push([Number(tokens[i + 1]), Number(tokens[i + 2])]);
        i += 3;
      } else if (op === "A") {
        out.push([Number(tokens[i + 6]), Number(tokens[i + 7])]);
        i += 8;
      } else {
        i += 1;
      }
    }
    return out;
  }

  function bounds(path) {
    const pts = points(path);
    return {
      "minX": Math.min(...pts.map(p => p[0])),
      "maxX": Math.max(...pts.map(p => p[0])),
      "minY": Math.min(...pts.map(p => p[1])),
      "maxY": Math.max(...pts.map(p => p[1]))
    };
  }

  function test_flat_is_a_rectangle() {
    compare(BarShapes.path(100, 30, 6, "flat", "flat", false, 0), "M 0 0 L 100 0 L 100 30 L 0 30 Z");
  }

  function test_zero_radius_round_is_square() {
    compare(BarShapes.path(100, 30, 0, "round", "round", false, 0), "M 0 0 L 100 0 L 100 30 L 0 30 Z");
  }

  function test_every_cap_stays_in_its_box_data() {
    return ["flat", "round", "capsule", "arrowOut", "arrowIn", "slant", "roundOut", "roundIn", "curve"].map(cap => ({
          "tag": cap,
          "cap": cap
        }));
  }
  function test_every_cap_stays_in_its_box(data) {
    for (const vertical of [false, true]) {
      const b = bounds(BarShapes.path(120, 30, 6, data.cap, data.cap, vertical, 0));
      const w = vertical ? 30 : 120, h = vertical ? 120 : 30;
      verify(b.minX >= 0 && b.maxX <= w && b.minY >= 0 && b.maxY <= h, JSON.stringify(b));
    }
  }

  function test_vertical_swaps_the_axes_and_flips_arcs() {
    const across = BarShapes.path(100, 30, 6, "round", "round", false, 0);
    const down = BarShapes.path(100, 30, 6, "round", "round", true, 0);
    compare(points(down), points(across).map(p => [p[1], p[0]]));
    verify(across.includes("A 6 6 0 0 1"));
    verify(down.includes("A 6 6 0 0 0") && !down.includes("A 6 6 0 0 1"));
  }

  function test_inset_shrinks_all_round() {
    const b = bounds(BarShapes.path(100, 30, 6, "round", "round", false, 1));
    compare([b.minX, b.maxX, b.minY, b.maxY], [1, 99, 1, 29]);
  }

  function test_arrow_points_at_the_end() {
    const pts = points(BarShapes.path(100, 30, 0, "flat", "arrowOut", false, 0));
    verify(pts.some(p => p[0] === 100 && p[1] === 15), "tip mid-way across");
    verify(pts.some(p => p[0] === 85 && p[1] === 0), "shoulder a depth back");
  }

  function test_slant_is_a_parallelogram() {
    // Both sides lean the same way: top inset at the start, bottom at the end
    const pts = points(BarShapes.path(100, 30, 0, "slant", "slant", false, 0));
    compare(pts.slice(0, 4), [[10, 0], [100, 0], [90, 30], [0, 30]]);
  }

  function test_separate_widgets_have_both_ends() {
    const s = BarShapes.segment("arrow", "shaped", "separate", true, 1, 3, 30);
    compare([s.startCap, s.endCap, s.back, s.lead, s.trail], ["arrowIn", "arrowOut", 0, 15, 15]);
    const r = BarShapes.segment("rounded", "shaped", "separate", true, 0, 1, 30);
    compare([r.startCap, r.endCap, r.lead, r.trail], ["round", "round", 0, 0]);
  }

  function test_merged_runs_cap_only_their_ends() {
    const first = BarShapes.segment("slant", "shaped", "merged", true, 0, 3, 30);
    const middle = BarShapes.segment("slant", "shaped", "merged", true, 1, 3, 30);
    const last = BarShapes.segment("slant", "shaped", "merged", true, 2, 3, 30);
    compare([first.startCap, first.lead, first.trail], ["slant", 5, 0]);
    compare([middle.startCap, middle.endCap, middle.lead, middle.trail, middle.back], ["flat", "flat", 0, 0, 0]);
    compare([last.endCap, last.trail], ["slant", 5]);
  }

  function test_levels_keep_their_own_caps() {
    const middle = BarShapes.segment("capsule", "shaped", "merged", true, 1, 3, 30);
    compare([middle.levelStartCap, middle.levelEndCap], ["capsule", "capsule"]);
    const first = BarShapes.segment("rounded", "shaped", "merged", true, 0, 2, 30);
    compare([first.levelStartCap, first.levelEndCap], ["round", "round"]);
    const lone = BarShapes.segment("arrow", "shaped", "separate", true, 0, 1, 30);
    compare([lone.levelStartCap, lone.levelEndCap], ["arrowIn", "arrowOut"]);
    const segment = BarShapes.segment("arrow", "shaped", "powerline", false, 1, 3, 30);
    compare([segment.levelStartCap, segment.levelEndCap], ["arrowIn", "arrowOut"]);
  }

  function test_powerline_segments_overlap() {
    const first = BarShapes.segment("arrow", "shaped", "powerline", true, 0, 2, 30);
    const second = BarShapes.segment("arrow", "shaped", "powerline", true, 1, 2, 30);
    compare([first.startCap, first.endCap, first.back, first.lead], ["arrowIn", "arrowOut", 0, 15]);
    // Opaque: square, beneath the arrow before it
    compare([second.startCap, second.back, second.lead], ["flat", 15, 0]);
    compare(second.endCap, "arrowOut");
    // See-through: fitted against it instead
    compare(BarShapes.segment("arrow", "shaped", "powerline", false, 1, 2, 30).startCap, "arrowIn");
    compare(BarShapes.segment("rounded", "shaped", "powerline", false, 1, 2, 30).startCap, "roundIn");
    compare(BarShapes.segment("slant", "shaped", "powerline", false, 1, 2, 30).startCap, "slant");
  }

  // Content sits centred on what shows of a segment: from half a join
  // before its box (the cap before reaching in) to half a join before its
  // end (its own cap tapering)
  function test_powerline_content_is_centred_on_what_shows() {
    const join = 15;
    const at = index => BarShapes.segment("arrow", "shaped", "powerline", true, index, 3, 30);
    const first = at(0), middle = at(1), last = at(2);
    compare([first.lead, first.trail], [15, join / 2]);
    compare([middle.lead, middle.trail], [0, join]);
    compare([last.lead, last.trail], [0, join / 2 + 15]);
  }

  // widgetEnds: a run's own ends notched and pointed (shaped), pointed at
  // both (an arrow's alone: a slant keeps its slant), or rounded
  function test_run_ends() {
    const caps = (shape, ends, grouping) => {
      const first = BarShapes.segment(shape, ends, grouping, true, 0, 2, 30);
      const last = BarShapes.segment(shape, ends, grouping, true, 1, 2, 30);
      return [first.startCap, last.endCap, first.lead];
    };
    ["separate", "merged", "powerline"].forEach(grouping => {
      compare(caps("arrow", "shaped", grouping), ["arrowIn", "arrowOut", 15]);
      compare(caps("arrow", "pointed", grouping), ["arrowOut", "arrowOut", 15]);
      compare(caps("arrow", "rounded", grouping), ["round", "round", 0]);
      compare(caps("slant", "pointed", grouping), ["slant", "slant", 5]);
      compare(caps("slant", "rounded", grouping), ["round", "round", 0]);
      compare(caps("capsule", "rounded", grouping), ["capsule", "capsule", 0]);
    });
    // Rounded ends keep a powerline's joins, and its content centred
    const last = BarShapes.segment("arrow", "rounded", "powerline", true, 1, 2, 30);
    compare([last.back, last.trail], [15, 7.5]);
  }

  function test_powerline_seams() {
    const opaque = BarShapes.segment("rounded", "shaped", "powerline", true, 1, 3, 30);
    const clear = BarShapes.segment("rounded", "shaped", "powerline", false, 1, 3, 30);
    compare([opaque.seamStart, opaque.seamEnd], [false, false]);
    compare([clear.seamStart, clear.seamEnd], [true, true]);
    const alone = BarShapes.segment("rounded", "shaped", "separate", false, 0, 1, 30);
    compare([alone.seamStart, alone.seamEnd], [false, false]);
  }

  function test_seam_keeps_the_inset_off_that_end() {
    const b = bounds(BarShapes.path(100, 30, 0, "flat", "flat", false, 1, true, false));
    compare([b.minX, b.maxX, b.minY, b.maxY], [0, 99, 1, 29]);
  }

  function test_shown_start_follows_the_cap_before() {
    compare(BarShapes.segment("slant", "shaped", "powerline", true, 1, 2, 30).shownStart, "slant");
    compare(BarShapes.segment("arrow", "shaped", "powerline", true, 1, 2, 30).shownStart, "arrowIn");
    compare(BarShapes.segment("slant", "shaped", "merged", true, 1, 3, 30).shownStart, "flat");
    compare(BarShapes.segment("slant", "shaped", "separate", true, 0, 1, 30).shownStart, "slant");
  }

  function test_contains_follows_the_caps() {
    // A parallelogram 100 by 30, its sides 10 deep: the top runs 10 to 100,
    // the bottom 0 to 90
    verify(!BarShapes.contains(2, 1, 100, 30, "slant", "slant"));
    verify(BarShapes.contains(2, 29, 100, 30, "slant", "slant"));
    verify(BarShapes.contains(98, 1, 100, 30, "slant", "slant"));
    verify(!BarShapes.contains(98, 29, 100, 30, "slant", "slant"));
    // An arrow's point and notch
    verify(BarShapes.contains(1, 15, 100, 30, "arrowOut", "arrowOut"));
    verify(!BarShapes.contains(1, 1, 100, 30, "arrowOut", "arrowOut"));
    verify(!BarShapes.contains(1, 15, 100, 30, "arrowIn", "arrowOut"));
    verify(BarShapes.contains(1, 1, 100, 30, "arrowIn", "arrowOut"));
    verify(BarShapes.contains(50, 15, 100, 30, "flat", "flat"));
    verify(!BarShapes.contains(50, 31, 100, 30, "flat", "flat"));
  }

  function test_divider_cap_matches_the_shape_or_is_chosen() {
    compare(BarShapes.dividerCap("slant", "match"), "slant");
    compare(BarShapes.dividerCap("arrow", "match"), "arrowOut");
    compare(BarShapes.dividerCap("rounded", "match"), "flat");
    compare(BarShapes.dividerCap("capsule", "match"), "flat");
    compare(BarShapes.dividerCap("capsule", "slant"), "slant");
    compare(BarShapes.dividerCap("slant", "straight"), "flat");
    compare(BarShapes.dividerCap("rounded", "arrow"), "arrowOut");
    compare(BarShapes.dividerCap("rounded", "curve"), "curve");
  }

  function test_split_room_holds_the_divider_or_the_badge() {
    // Joined: the padding either side and the divider's depth
    compare(BarShapes.splitRoom("joined", "flat", 30, 10, 6, 4), 20);
    compare(BarShapes.splitRoom("joined", "slant", 30, 10, 6, 4), 30);
    compare(BarShapes.splitRoom("joined", "arrowOut", 30, 10, 6, 4), 35);
    // A badge: its reach round the icon, then the usual spacing
    compare(BarShapes.splitRoom("badge", "slant", 30, 10, 6, 4), 10);
  }

  function test_curve_is_a_shallow_arc_to_the_end() {
    // Bulging a quarter of the thickness: its middle reaches the end, its
    // corners stop that far in
    const d = BarShapes.depth("curve", 40);
    compare(d, 10);
    verify(BarShapes.contains(99.5, 20, 100, 40, "flat", "curve"));
    verify(!BarShapes.contains(95, 0.5, 100, 40, "flat", "curve"));
    verify(BarShapes.contains(89, 0.5, 100, 40, "flat", "curve"));
    const b = bounds(BarShapes.path(100, 40, 0, "flat", "curve", false, 0));
    compare(b.maxX, 90);
  }

  // Tabs (widgetShape tab): a widget's background out to the edge it
  // hangs from
  function square(outerStart) {
    return BarShapes.tab(6, 26, 0, outerStart, [null, null]);
  }

  function test_tab_caps_keep_no_room() {
    const lone = BarShapes.segment("tab", "shaped", "separate", true, 0, 1, 30);
    compare([lone.startCap, lone.endCap, lone.lead, lone.trail, lone.back], ["tab", "tab", 0, 0, 0]);
    const middle = BarShapes.segment("tab", "shaped", "merged", true, 1, 3, 30);
    compare([middle.startCap, middle.endCap, middle.levelStartCap], ["flat", "flat", "tab"]);
  }

  function test_tab_radius_and_flare() {
    const t = BarShapes.tab(20, 26, 5, true, [null, null]);
    compare([t.radius, t.start.flare, t.end.flare], [13, 5, 5]);
    const s = BarShapes.tab(6, 26, 0, false, [null, null]);
    compare([s.radius, s.start.flare, s.outerStart], [6, 0, false]);
  }

  // One fillet for every tab on a bar: the corner radius, within half the
  // widget gap and the room at the bar's ends; none when square
  function test_tab_fillet() {
    compare(BarShapes.tabFillet(6, 26, "flared", 20, 8), 6);
    compare(BarShapes.tabFillet(6, 26, "flared", 4, 8), 2);
    compare(BarShapes.tabFillet(20, 26, "flared", 40, Infinity), 13);
    compare(BarShapes.tabFillet(6, 26, "flared", 20, 5), 5);
    compare(BarShapes.tabFillet(6, 26, "flared", 0, 8), 0);
    compare(BarShapes.tabFillet(6, 26, "square", 20, 8), 0);
  }

  // An end nearer a bound than its curve takes the curve, else the
  // bar's fillet like every other tab
  function test_tab_limits() {
    const near = BarShapes.tab(6, 26, 4, true, [
      {
        "gap": 4,
        "radius": 10
      },
      {
        "gap": 3,
        "radius": 0
      }
    ]);
    compare(near.start.corner, {
      "radius": 10,
      "gap": 4
    });
    compare(near.start.flare, 0);
    compare([near.end.corner, near.end.flare], [null, 4]);
  }

  function test_tab_limits_find_the_bound_holding_it() {
    const bounds = [
      {
        "start": 0,
        "end": 100,
        "startRadius": 8,
        "endRadius": 8
      },
      {
        "start": 150,
        "end": 300,
        "startRadius": 8,
        "endRadius": 0
      }
    ];
    compare(BarShapes.tabLimits(155, 200, bounds), [
      {
        "gap": 5,
        "radius": 8
      },
      {
        "gap": 100,
        "radius": 0
      }
    ]);
    compare(BarShapes.tabLimits(110, 140, bounds), [null, null]);
    compare(BarShapes.tabLimits(10, 20, []), [null, null]);
  }

  function test_square_tab_reaches_its_outer_edge() {
    // Outer edge on top: square corners there, rounded below
    const top = BarShapes.path(100, 30, 0, "tab", "tab", false, 0, false, false, square(true));
    const pts = points(top);
    verify(pts.some(p => p[0] === 0 && p[1] === 0) && pts.some(p => p[0] === 100 && p[1] === 0), top);
    verify(!pts.some(p => p[0] === 0 && p[1] === 30), "inner corners rounded: " + top);
    verify(top.endsWith("Z"));
    // On the far side, flipped
    const bottom = points(BarShapes.path(100, 30, 0, "tab", "tab", false, 0, false, false, square(false)));
    compare(bottom, pts.map(p => [p[0], 30 - p[1]]));
  }

  function test_tab_outline_is_open_along_its_outer_edge() {
    const open = BarShapes.path(100, 30, 0, "tab", "tab", false, 1, false, false, square(true), true);
    verify(!open.includes("Z"));
    const pts = points(open);
    // From the outer edge down, round and back up to it, inset but on
    // the outer side
    compare(pts[0], [1, 0]);
    compare(pts[pts.length - 1], [99, 0]);
    compare(bounds(open).maxY, 29);
  }

  function test_flared_tab_curves_out_into_the_edge() {
    const t = BarShapes.tab(6, 26, 6, true, [null, null]);
    const path = BarShapes.path(100, 30, 0, "tab", "tab", false, 0, false, false, t);
    const b = bounds(path);
    compare([b.minX, b.maxX, b.minY, b.maxY], [-6, 106, 0, 30]);
    // Concave: swept the other way from the inner corners
    verify(path.includes("A 6 6 0 0 1 0 6") && path.includes("A 6 6 0 0 0 6 30"), path);
  }

  function test_tab_vertical_swaps_the_axes_and_flips_arcs() {
    const t = BarShapes.tab(6, 26, 6, true, [null, null]);
    const across = BarShapes.path(100, 30, 0, "tab", "tab", false, 0, false, false, t);
    const down = BarShapes.path(100, 30, 0, "tab", "tab", true, 0, false, false, t);
    compare(points(down), points(across).map(p => [p[1], p[0]]));
    verify(down.includes("A 6 6 0 0 0 6 0") && down.includes("A 6 6 0 0 1 30 6"), down);
  }

  // At an island's end the tab's outer corner follows the island's curve:
  // from the outer edge at radius − gap in, round to its side
  function test_tab_takes_a_bounds_corner_curve() {
    const t = BarShapes.tab(6, 26, "square", true, [
      {
        "gap": 4,
        "radius": 10
      },
      null]);
    const path = BarShapes.path(100, 30, 0, "tab", "tab", false, 0, false, false, t);
    compare(points(path)[0], [6, 0]);
    // 10 − √(10² − 6²) = 2 down the side
    verify(path.includes("A 10 10 0 0 0 0 2"), path);
  }

  function test_tab_hits_reach_its_outer_edge() {
    verify(BarShapes.contains(1, 1, 100, 30, "tab", "tab"));
    verify(BarShapes.contains(99, 29, 100, 30, "tab", "tab"));
  }
}
