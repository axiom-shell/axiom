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

  function test_offset_path_shrinks_square_to_each_edge() {
    // Flat ends: the inset all round, or at a seam the end's own
    const b = bounds(BarShapes.offsetPath(100, 30, 0, "flat", "flat", false, 3, 3, 3));
    compare([b.minX, b.maxX, b.minY, b.maxY], [3, 97, 3, 27]);
    const seam = bounds(BarShapes.offsetPath(100, 30, 0, "flat", "flat", false, 3, 3, 0));
    compare([seam.minX, seam.maxX], [3, 100]);
    // A round corner keeps its centre: its radius less the inset
    verify(BarShapes.offsetPath(100, 30, 8, "round", "round", false, 3, 3, 3).includes("A 5 5 0 0 1"));
    compare(BarShapes.offsetPath(100, 30, 2, "round", "round", false, 3, 3, 3), BarShapes.offsetPath(100, 30, 0, "flat", "flat", false, 3, 3, 3));
    // A capsule's half circle shrinks about its centre
    verify(BarShapes.offsetPath(100, 30, 0, "capsule", "capsule", false, 3, 3, 3).includes("A 12 12 0 0 1"));
    compare(BarShapes.offsetPath(100, 30, 0, "flat", "flat", false, 15, 15, 15), "", "no room");
  }

  // The distance from point p to the line through a and b
  function distance(p, a, b) {
    const dx = b[0] - a[0], dy = b[1] - a[1];
    return Math.abs(dy * (p[0] - a[0]) - dx * (p[1] - a[1])) / Math.sqrt(dx * dx + dy * dy);
  }

  function test_offset_path_keeps_slants_and_arrows_parallel_data() {
    return [
      {
        "tag": "slant",
        "cap": "slant"
      },
      {
        "tag": "arrowOut",
        "cap": "arrowOut"
      },
      {
        "tag": "arrowIn",
        "cap": "arrowIn"
      }
    ];
  }
  function test_offset_path_keeps_slants_and_arrows_parallel(data) {
    // The end cap's points, outer and moved 4 in: each inner point lies 4
    // from the outer cap's line beside it
    const outer = points(BarShapes.offsetPath(100, 30, 0, "flat", data.cap, false, 0, 0, 0)).filter(p => p[0] > 50);
    const inner = points(BarShapes.offsetPath(100, 30, 0, "flat", data.cap, false, 4, 0, 4)).filter(p => p[0] > 50);
    compare(outer.length, inner.length);
    for (let k = 0; k + 1 < outer.length; k++)
      fuzzyCompare(distance(inner[k], outer[k], outer[k + 1]), 4, 0.001, data.cap + " point " + k);
  }

  function test_offset_path_bows_round_joins_about_their_centre() {
    // A powerline's half circles: out shrinks, in grows, both about the
    // circle the seam lies on
    verify(BarShapes.offsetPath(100, 30, 0, "flat", "roundOut", false, 3, 0, 3).includes("A 12 12 0 0 1"));
    verify(BarShapes.offsetPath(100, 30, 0, "roundIn", "flat", false, 3, 3, 0).includes("A 18 18"));
  }

  function test_marks_are_the_ends_alone() {
    // Two open paths: no close, one move per end
    const both = BarShapes.marks(100, 30, 0, "round", "round", false, 1, false, false);
    verify(!both.includes("Z"));
    compare(both.split("M").length - 1, 2);
    // A square end's mark is a bracket: arms a quarter of the thickness
    const pts = points(both);
    compare(pts.slice(0, 4), [[8.5, 1], [1, 1], [1, 29], [8.5, 29]]);
    compare(pts.slice(4), [[91.5, 1], [99, 1], [99, 29], [91.5, 29]]);
    // A slant's or an arrow's line, with arms from its corners: a bracket
    compare(points(BarShapes.marks(100, 30, 0, "flat", "arrowOut", false, 0, false, false)).slice(4), [[77.5, 0], [85, 0], [100, 15], [85, 30], [77.5, 30]]);
    compare(points(BarShapes.marks(100, 30, 0, "slant", "flat", false, 0, false, false)).slice(0, 4), [[17.5, 0], [10, 0], [0, 30], [7.5, 30]]);
    // A capsule's half circle alone
    verify(BarShapes.marks(100, 30, 0, "capsule", "capsule", false, 1, false, false).includes("A 14 14"));
  }

  // A merged run carried on into the next section's, drawn apart: no line
  // across the join (a divider there), its long sides running to it
  function test_open_ends_leave_the_join_unlined() {
    const closed = BarShapes.path(100, 30, 0, "flat", "flat", false, 1, false, false, null, true);
    verify(closed.endsWith("Z"));
    const end = BarShapes.path(100, 30, 6, "round", "flat", false, 1, false, false, null, true, false, true);
    verify(!end.includes("Z"), end);
    const ep = points(end);
    // From the end's bottom corner round the start to its top corner, at
    // the very end (no inset there)
    compare(ep[0], [100, 29]);
    compare(ep[ep.length - 1], [100, 1]);
    verify(!ep.slice(1, -1).some(p => p[0] === 100), "nothing across the end: " + end);
    const start = points(BarShapes.path(100, 30, 6, "flat", "round", false, 1, false, false, null, true, true, false));
    compare(start[0], [0, 1]);
    compare(start[start.length - 1], [0, 29]);
    verify(!start.slice(1, -1).some(p => p[0] === 0), "nothing across the start");
    // Both: the two long sides alone
    compare(points(BarShapes.path(100, 30, 0, "flat", "flat", false, 1, false, false, null, true, true, true)), [[0, 1], [100, 1], [100, 29], [0, 29]]);
    // The fill stays closed, reaching the open end
    const fill = BarShapes.path(100, 30, 0, "flat", "flat", false, 1, false, false, null, false, false, true);
    verify(fill.endsWith("Z"));
    compare(bounds(fill).maxX, 100);
    // Every other stroke: a double's lines run to it, a mark is left out
    const double = BarShapes.offsetPath(100, 30, 0, "flat", "flat", false, 3, 3, 3, null, false, true);
    verify(!double.includes("Z"));
    compare(bounds(double).maxX, 100);
    compare(BarShapes.marks(100, 30, 0, "round", "flat", false, 1, false, false, null, false, true).split("M").length - 1, 1);
    compare(BarShapes.marks(100, 30, 0, "flat", "flat", false, 1, false, false, null, true, true), "");
    // Slanted runs meet flat at a join too
    verify(!BarShapes.path(100, 30, 0, "slant", "flat", false, 1, false, false, null, true, false, true).includes("Z"));
  }

  function test_tab_open_ends_leave_the_join_unlined() {
    const t = square(true);
    // The start side drawn, the inner side running on to the end, no side there
    const end = points(BarShapes.path(100, 30, 0, "tab", "flat", false, 1, false, false, t, true, false, true));
    compare(end[end.length - 1][0], 100);
    compare(end[end.length - 1][1], 29);
    compare(end.filter(p => p[0] === 100).length, 1);
    const start = points(BarShapes.path(100, 30, 0, "flat", "tab", false, 1, false, false, t, true, true, false));
    compare(start[0], [0, 29]);
    // Both: the inner side alone
    compare(points(BarShapes.path(100, 30, 0, "flat", "flat", false, 1, false, false, t, true, true, true)), [[0, 29], [100, 29]]);
    // Marks: none at an open end
    compare(BarShapes.marks(100, 30, 0, "flat", "flat", false, 1, false, false, t, true, true), "");
    // A double's lines too
    const double = points(BarShapes.offsetPath(100, 30, 0, "flat", "flat", false, 3, 3, 3, t, true, true));
    compare(double.map(p => p[0]), [0, 100]);
  }

  // The path's subpaths, each its points
  function subpaths(path) {
    return path.split("M").filter(part => part.trim() !== "").map(part => points("M" + part));
  }

  function mirrored(pts, length) {
    return pts.map(p => [Math.round((length - p[0]) * 1000) / 1000, Math.round(p[1] * 1000) / 1000]);
  }

  function rounded(pts) {
    return pts.map(p => [Math.round(p[0] * 1000) / 1000, Math.round(p[1] * 1000) / 1000]);
  }

  // A dash pattern runs along halves that mirror each other, from the
  // middle of the sides out, so both ends dash alike
  function test_dash_path_mirrors_its_halves_data() {
    return ["round", "capsule", "flat", "arrowOut"].map(cap => ({
          "tag": cap,
          "cap": cap
        }));
  }
  function test_dash_path_mirrors_its_halves(data) {
    const parts = subpaths(BarShapes.dashPath(100, 30, 6, data.cap, data.cap, false, 1, false, false, null));
    compare(parts.length, 2);
    compare(parts[0][0], [50, 1], "starts at the middle");
    compare(parts[1][0], [50, 1]);
    compare(rounded(parts[1]), mirrored(parts[0], 100), "the end's half mirrors the start's");
    compare(parts[0][parts[0].length - 1], [50, 29], "and ends at the other side's middle");
  }

  function test_dash_path_open_ends_run_out_from_the_middle() {
    const parts = subpaths(BarShapes.dashPath(100, 30, 0, "round", "flat", false, 1, false, false, null, false, true));
    compare(parts.length, 3);
    // (the middle between the start's inset and the open end)
    compare(parts[1], [[50.5, 1], [100, 1]]);
    compare(parts[2], [[50.5, 29], [100, 29]]);
  }

  function test_dashed_tab_sides_mirror_its_fillets_apart() {
    const t = BarShapes.tab(6, 26, 6, true, [null, null]);
    const parts = subpaths(BarShapes.dashPath(100, 30, 6, "tab", "tab", false, 1, false, false, t));
    compare(parts.length, 2);
    // From the inner side's middle out round each inner corner
    compare(parts[0][0], [50, 29]);
    compare(rounded(parts[1]), mirrored(parts[0], 100));
    // Up to the fillet, which isn't dashed
    verify(!parts[0].some(p => p[1] === 0), "no dash on the fillet");
    const fillets = subpaths(BarShapes.fillets(100, 30, "tab", "tab", false, 1, t));
    compare(fillets.length, 2);
    compare(fillets[0][0][1], 0, "a fillet starts on the outer edge");
    compare(rounded(fillets[1]), mirrored(fillets[0], 100));
    // Each fillet ends where the side's dashes stop
    compare(rounded([fillets[0][1]]), rounded([parts[0][parts[0].length - 1]]));
    // Square: the sides run to the edge, no fillets
    const square = subpaths(BarShapes.dashPath(100, 30, 6, "tab", "tab", false, 1, false, false, BarShapes.tab(6, 26, 0, true, [null, null])));
    compare(square[0][square[0].length - 1][1], 0);
    compare(BarShapes.fillets(100, 30, "tab", "tab", false, 1, BarShapes.tab(6, 26, 0, true, [null, null])), "");
    // An open end: the inner side to it alone, and no fillet
    const open = subpaths(BarShapes.dashPath(100, 30, 6, "tab", "flat", false, 1, false, false, t, false, true));
    compare(open[1], [[50.5, 29], [100, 29]]);
    compare(subpaths(BarShapes.fillets(100, 30, "tab", "flat", false, 1, t, false, true)).length, 1);
  }

  function test_marks_one_per_seam() {
    // A powerline segment's start at a seam is the one before's end mark
    const mid = BarShapes.marks(100, 30, 0, "arrowIn", "arrowOut", false, 1, true, true);
    compare(mid.split("M").length - 1, 1);
    // ...which lies on the seam
    verify(points(mid).some(p => p[0] === 100 && p[1] === 15));
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
      null], "an end as far from its bound as the curve reaches isn't held");
    compare(BarShapes.tabLimits(10, 95, bounds), [null,
      {
        "gap": 5,
        "radius": 8
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

  // Split's icon part on a tab: its divider end (a non-tab cap) keeps its
  // shape, the right way up on either side
  function test_tab_with_a_divider_end() {
    const d = 26 / 3;
    const top = points(BarShapes.path(100, 30, 0, "tab", "slant", false, 0, false, false, square(true)));
    verify(top.some(p => p[0] === 100 && p[1] === 0) && top.some(p => Math.abs(p[0] - (100 - d)) < 1e-9 && p[1] === 30), JSON.stringify(top));
    // A bottom bar's: the same slant as on a bar without tabs
    const bottom = points(BarShapes.path(100, 30, 0, "tab", "slant", false, 0, false, false, square(false)));
    verify(bottom.some(p => p[0] === 100 && p[1] === 0) && bottom.some(p => Math.abs(p[0] - (100 - d)) < 1e-9 && p[1] === 30), JSON.stringify(bottom));
    // A curve bulges out, as drawn without tabs, on both sides
    const plain = BarShapes.path(100, 30, 0, "flat", "curve", false, 0);
    verify(plain.includes(" 0 0 1 "), plain);
    for (const outerStart of [true, false]) {
      const curve = BarShapes.path(100, 30, 0, "tab", "curve", false, 0, false, false, square(outerStart));
      // Drawn up the end on a top tab (sweep flipped), down it on a bottom one
      verify(curve.includes(outerStart ? " 0 0 0 " : " 0 0 1 "), curve);
      // Its corners in by its depth (the arc reaches the end)
      compare(bounds(curve).maxX, 100 - 26 / 4);
    }
  }

  function sweeps(path) {
    return (path.match(/A \S+ \S+ 0 0 (\d)/g) ?? []).map(a => a.slice(-1));
  }

  // The end side mirrors the start side, drawn back out: each of its arcs
  // turns as the start's, in reverse order, on every side of the bar
  function test_tab_end_side_mirrors_the_start() {
    const t = outerStart => BarShapes.tab(6, 26, 6, outerStart, [null, null]);
    for (const outerStart of [true, false])
      for (const vertical of [false, true]) {
        const sw = sweeps(BarShapes.path(100, 30, 0, "tab", "tab", vertical, 1, false, false, t(outerStart), true));
        compare(sw.length, 4);
        compare(sw, sw.slice().reverse());
      }
  }

  // Outline strokes on a tab: open along the edge it hangs from
  function test_tab_double_lines_both_reach_the_edge() {
    const t = BarShapes.tab(6, 26, 6, true, [null, null]);
    const outer = BarShapes.offsetPath(100, 30, 6, "tab", "tab", false, 1, 1, 1, t);
    const inner = BarShapes.offsetPath(100, 30, 6, "tab", "tab", false, 5, 5, 5, t);
    for (const line of [outer, inner]) {
      verify(!line.includes("Z"), line);
      const pts = points(line);
      compare([pts[0][1], pts[pts.length - 1][1]], [0, 0]);
    }
    compare(bounds(outer).maxY, 29);
    compare(bounds(inner).maxY, 25);
    // The inner corners keep their centre: the radius less the inset
    verify(inner.includes("A 1 1 "), inner);
    verify(outer.includes("A 5 5 "), outer);
    // A fillet's circle widens by it, crossing the edge further in
    verify(inner.includes("A 11 11 0 0 1 5 6"), inner);
  }

  function test_tab_ends_marks_its_two_sides() {
    const t = BarShapes.tab(6, 26, 0, true, [null, null]);
    const marks = BarShapes.marks(100, 30, 6, "tab", "tab", false, 1, false, false, t);
    verify(!marks.includes("Z"), marks);
    const starts = marks.split("M ").filter(m => m.length > 0).map(m => points("M " + m));
    compare(starts.length, 2);
    // Each from the outer edge in, round its corner, an arm along
    compare(starts[0][0], [1, 0]);
    compare(starts[0][starts[0].length - 1], [7 + 26 / 4, 29]);
    compare(starts[1][0], [99, 0]);
    compare(starts[1][starts[1].length - 1], [93 - 26 / 4, 29]);
  }

  // Content and separator marks move half the reach toward the outer edge
  function test_tab_shift_centres_in_the_tab() {
    compare(BarShapes.tabShift(10, false), -5);
    compare(BarShapes.tabShift(10, true), 5);
    compare(BarShapes.tabShift(5, false), -3);
    compare(BarShapes.tabShift(0, true), 0);
  }

  function test_tab_hits_reach_its_outer_edge() {
    verify(BarShapes.contains(1, 1, 100, 30, "tab", "tab"));
    verify(BarShapes.contains(99, 29, 100, 30, "tab", "tab"));
  }

  // Cells laid out as segments of the bar's run (Workspaces with its
  // Background off): separate, each alone in the shape's ends
  function test_separate_cells_are_each_alone() {
    const s = BarShapes.cellSegment("arrow", "shaped", "separate", false, {
      "index": 1,
      "count": 3
    }, 1, 3, 30);
    compare([s.startCap, s.endCap, s.back, s.lead, s.trail], ["arrowIn", "arrowOut", 0, 15, 15]);
    const r = BarShapes.cellSegment("rounded", "shaped", "separate", false, null, 0, 2, 30);
    compare([r.startCap, r.endCap, r.lead, r.trail], ["round", "round", 0, 0]);
    compare(BarShapes.cellSegment("tab", "shaped", "separate", false, null, 0, 2, 30).startCap, "tab");
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
    const first = BarShapes.cellSegment("arrow", "shaped", "powerline", true, place, 0, 2, 30);
    const last = BarShapes.cellSegment("arrow", "shaped", "powerline", true, place, 1, 2, 30);
    compare([first.startCap, first.endCap, first.back, first.lead, first.trail, first.seamStart], ["arrowIn", "arrowOut", 15, 0, 15, true]);
    compare([last.startCap, last.endCap, last.back, last.lead, last.trail], ["arrowIn", "arrowOut", 15, 0, 15]);
    // Alone, the first cell takes the run's start and the last its end
    const a = BarShapes.cellSegment("slant", "shaped", "powerline", true, null, 0, 3, 30);
    const z = BarShapes.cellSegment("slant", "shaped", "powerline", true, null, 2, 3, 30);
    compare([a.startCap, a.back, a.lead], ["slant", 0, 5]);
    compare([z.endCap, z.back, z.trail], ["slant", 10, 5 + 5]);
    // The run's last widget: its last cell gives the run's end cap
    const end = BarShapes.cellSegment("arrow", "pointed", "powerline", false, {
      "index": 2,
      "count": 3
    }, 2, 3, 30);
    compare([end.endCap, end.seamEnd], ["arrowOut", false]);
    // Opaque cells: a later one starts square beneath the one before; the
    // widget's first still fits against the cap before it
    const opaque = cell => BarShapes.cellSegment("arrow", "shaped", "powerline", false, place, cell, 2, 30, true);
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
    const first = BarShapes.cellSegment("slant", "shaped", "merged", false, place, 0, 3, 30);
    const middle = BarShapes.cellSegment("slant", "shaped", "merged", false, place, 1, 3, 30);
    compare([first.lead, first.trail, first.back], [5, 0, 0]);
    compare([middle.lead, middle.trail], [0, 0]);
    compare([middle.startCap, middle.endCap], ["slant", "slant"], "a box of its own: the caps it has alone");
    compare(middle.shownStart, "slant", "shown from its own start");
    const boxed = BarShapes.cellSegment("slant", "shaped", "merged", true, place, 1, 3, 30);
    compare([boxed.lead, boxed.trail, boxed.seamStart, boxed.seamEnd], [5, 5, false, false]);
  }

  function test_cell_gap() {
    compare(BarShapes.cellGap("powerline", 4), 0);
    compare(BarShapes.cellGap("separate", 4), 4);
    compare(BarShapes.cellGap("merged", 4), 4);
  }

  // Tab cells: the bar's fillet at the widget's ends, between cells no
  // more than half the gap, and the widget's bounds at its two ends
  function test_cell_tab() {
    const first = BarShapes.cellTab(6, 30, 5, 4, true, [null, null], 0, 3);
    compare([first.start.flare, first.end.flare], [5, 2]);
    const middle = BarShapes.cellTab(6, 30, 5, 4, true, [null, null], 1, 3);
    compare([middle.start.flare, middle.end.flare], [2, 2]);
    const bound = BarShapes.cellTab(6, 30, 5, 20, true, [
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
    compare(BarShapes.cellTab(6, 30, 5, 0, true, null, 1, 2).start.flare, 0, "no gap: square");
  }

  // A cell's shape and room on a bar's look, from where its widget is
  // drawn and what it shows
  function test_cell_shape_and_room() {
    const look = {
      "widgetShape": "arrow",
      "widgetEnds": "shaped",
      "widgetGrouping": "powerline",
      "radius": 6,
      "thickness": 30,
      "tabFillet": 0,
      "right": false,
      "bottom": false
    };
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
    const shape = BarShapes.cellShape(look, run, false, false, 0, 0, 2);
    compare([shape.segment.startCap, shape.segment.back, shape.tab, shape.reachStart, shape.reachEnd], ["arrowIn", 15, null, 1, 2]);
    compare(BarShapes.cellRoom(look, run, false, 0, 2).lead, 15, "room from what's shown");
    const tab = BarShapes.cellShape(Object.assign({}, look, {
      "widgetShape": "tab",
      "widgetGrouping": "separate",
      "bottom": true
    }), null, false, false, 4, 0, 1);
    compare([tab.segment.startCap, tab.tab.outerStart, tab.reachStart], ["tab", false, 0]);
  }

  // What a cell draws past its own bounds along the bar: back under the
  // cell before, and a flared tab's fillets past its sides, which every
  // clip holding cells keeps (cellMargins), the widget's own while it
  // resizes too (runDraws)
  function test_cells_draw_past_their_bounds() {
    const look = {
      "widgetShape": "tab",
      "widgetEnds": "shaped",
      "widgetGrouping": "separate",
      "radius": 6,
      "thickness": 30,
      "tabFillet": 5,
      "right": false,
      "bottom": false,
      "vertical": false
    };
    const run = {
      "sized": null,
      "drawn": null,
      "reachStart": 4,
      "reachEnd": 0,
      "tabLimits": [null, null]
    };
    // The widget's ends take the bar's fillet, between cells half the gap
    const first = BarShapes.cellShape(look, run, false, false, 4, 0, 3);
    const last = BarShapes.cellShape(look, run, false, false, 4, 2, 3);
    compare([first.drawStart, first.drawEnd, last.drawStart, last.drawEnd], [5, 2, 2, 5]);
    compare(BarShapes.cellMargins(first, last, false), {
      "left": 5,
      "top": 4,
      "right": 5,
      "bottom": 0
    });
    compare(BarShapes.cellMargins(first, last, true), {
      "left": 4,
      "top": 5,
      "right": 0,
      "bottom": 5
    });
    compare(BarShapes.runDraws(look, run), {
      "start": 5,
      "end": 5
    });
    // A powerline cell reaches back under the one before, nothing past its end
    const chain = Object.assign({}, look, {
      "widgetShape": "arrow",
      "widgetGrouping": "powerline",
      "tabFillet": 0
    });
    const placed = Object.assign({}, run, {
      "drawn": {
        "index": 1,
        "count": 3
      },
      "reachStart": 0
    });
    compare(BarShapes.runDraws(chain, placed), {
      "start": 15,
      "end": 0
    });
    compare(BarShapes.cellMargins(null, null, false), {
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
    const look = {
      "widgetShape": "arrow",
      "widgetEnds": "shaped",
      "widgetGrouping": "powerline",
      "radius": 6,
      "thickness": 30,
      "tabFillet": 0,
      "right": false,
      "bottom": false
    };
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
    const a = BarShapes.cellShape(look, run, false, true, 0, 0, 2);
    const b = BarShapes.cellShape(look, run, false, true, 0, 1, 2);
    compare([b.segment.startCap, b.segment.shownStart], ["flat", "arrowIn"]);
    // Near the shared end's edge (a at 39, b at -1): the arrow's point is a's, its corners b's
    verify(BarShapes.cellContains(a, 39, 15, 40, 30, false), "the arrow's point");
    verify(!BarShapes.cellContains(a, 39, 1, 40, 30, false), "a corner beside it isn't a's");
    verify(BarShapes.cellContains(b, -1, 1, 40, 30, false), "it's the next cell's");
    verify(!BarShapes.cellContains(b, -1, 15, 40, 30, false), "the point isn't the next cell's");
    // The first cell, back under the widget before, beside its cap
    verify(BarShapes.cellContains(a, -14, 1, 40, 30, false));
    verify(!BarShapes.cellContains(a, -14, 15, 40, 30, false));
    verify(!BarShapes.cellContains(a, -16, 1, 40, 30, false), "no further back than it reaches");
    // Vertical: the same along y
    verify(BarShapes.cellContains(b, 1, -1, 30, 40, true));
    verify(!BarShapes.cellContains(a, 1, 39, 30, 40, true));
    // A tab cell reaches across out to its edge (4 before it), not along
    // into its fillets
    const tab = BarShapes.cellShape(Object.assign({}, look, {
      "widgetShape": "tab",
      "widgetGrouping": "separate",
      "tabFillet": 5
    }), Object.assign({}, run, {
      "reachStart": 4
    }), false, false, 4, 0, 2);
    verify(BarShapes.cellContains(tab, 1, -3, 40, 30, false));
    verify(!BarShapes.cellContains(tab, -1, -3, 40, 30, false));
    // No shape: its own box
    verify(BarShapes.cellContains(null, 0, 0, 40, 30, false));
    verify(!BarShapes.cellContains(null, 40, 0, 40, 30, false));
  }
}
