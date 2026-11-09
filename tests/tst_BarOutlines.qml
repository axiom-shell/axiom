import QtQuick
import QtTest
import qs.components.methods

// Outlines as SVG paths from one outline spec (BarOutlines)
TestCase {
  name: "BarOutlines"

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
    compare(BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 6,
      "startCap": "flat",
      "endCap": "flat"
    }), 0), "M 0 0 L 100 0 L 100 30 L 0 30 Z");
  }

  function test_zero_radius_round_is_square() {
    compare(BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "round",
      "endCap": "round"
    }), 0), "M 0 0 L 100 0 L 100 30 L 0 30 Z");
  }

  function test_every_cap_stays_in_its_box_data() {
    return ["flat", "round", "capsule", "arrowOut", "arrowIn", "slant", "roundOut", "roundIn", "curve"].map(cap => ({
          "tag": cap,
          "cap": cap
        }));
  }

  function test_every_cap_stays_in_its_box(data) {
    for (const vertical of [false, true]) {
      const b = bounds(BarOutlines.path(BarShapes.outline({
        "length": 120,
        "across": 30,
        "radius": 6,
        "startCap": data.cap,
        "endCap": data.cap,
        "vertical": vertical
      }), 0));
      const w = vertical ? 30 : 120, h = vertical ? 120 : 30;
      verify(b.minX >= 0 && b.maxX <= w && b.minY >= 0 && b.maxY <= h, JSON.stringify(b));
    }
  }

  function test_vertical_swaps_the_axes_and_flips_arcs() {
    const across = BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 6,
      "startCap": "round",
      "endCap": "round"
    }), 0);
    const down = BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 6,
      "startCap": "round",
      "endCap": "round",
      "vertical": true
    }), 0);
    compare(points(down), points(across).map(p => [p[1], p[0]]));
    verify(across.includes("A 6 6 0 0 1"));
    verify(down.includes("A 6 6 0 0 0") && !down.includes("A 6 6 0 0 1"));
  }

  function test_inset_shrinks_all_round() {
    const b = bounds(BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 6,
      "startCap": "round",
      "endCap": "round"
    }), 1));
    compare([b.minX, b.maxX, b.minY, b.maxY], [1, 99, 1, 29]);
  }

  function test_arrow_points_at_the_end() {
    const pts = points(BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": "arrowOut"
    }), 0));
    verify(pts.some(p => p[0] === 100 && p[1] === 15), "tip mid-way across");
    verify(pts.some(p => p[0] === 85 && p[1] === 0), "shoulder a depth back");
  }

  function test_slant_is_a_parallelogram() {
    // Both sides lean the same way: top inset at the start, bottom at the end
    const pts = points(BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "slant",
      "endCap": "slant"
    }), 0));
    compare(pts.slice(0, 4), [[10, 0], [100, 0], [90, 30], [0, 30]]);
  }

  function test_seam_keeps_the_inset_off_that_end() {
    const b = bounds(BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": "flat",
      "seamStart": true
    }), 1));
    compare([b.minX, b.maxX, b.minY, b.maxY], [0, 99, 1, 29]);
  }

  function test_offset_path_shrinks_square_to_each_edge() {
    // Flat ends: the inset all round, or at a seam the end's own
    const b = bounds(BarOutlines.offsetPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": "flat"
    }), 3, 3, 3));
    compare([b.minX, b.maxX, b.minY, b.maxY], [3, 97, 3, 27]);
    const seam = bounds(BarOutlines.offsetPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": "flat"
    }), 3, 3, 0));
    compare([seam.minX, seam.maxX], [3, 100]);
    // A round corner keeps its centre: its radius less the inset
    verify(BarOutlines.offsetPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 8,
      "startCap": "round",
      "endCap": "round"
    }), 3, 3, 3).includes("A 5 5 0 0 1"));
    compare(BarOutlines.offsetPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 2,
      "startCap": "round",
      "endCap": "round"
    }), 3, 3, 3), BarOutlines.offsetPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": "flat"
    }), 3, 3, 3));
    // A capsule's half circle shrinks about its centre
    verify(BarOutlines.offsetPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "capsule",
      "endCap": "capsule"
    }), 3, 3, 3).includes("A 12 12 0 0 1"));
    compare(BarOutlines.offsetPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": "flat"
    }), 15, 15, 15), "", "no room");
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
    const outer = points(BarOutlines.offsetPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": data.cap
    }), 0, 0, 0)).filter(p => p[0] > 50);
    const inner = points(BarOutlines.offsetPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": data.cap
    }), 4, 0, 4)).filter(p => p[0] > 50);
    compare(outer.length, inner.length);
    for (let k = 0; k + 1 < outer.length; k++)
      fuzzyCompare(distance(inner[k], outer[k], outer[k + 1]), 4, 0.001, data.cap + " point " + k);
  }

  function test_offset_path_bows_round_joins_about_their_centre() {
    // A powerline's half circles: out shrinks, in grows, both about the
    // circle the seam lies on
    verify(BarOutlines.offsetPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": "roundOut"
    }), 3, 0, 3).includes("A 12 12 0 0 1"));
    verify(BarOutlines.offsetPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "roundIn",
      "endCap": "flat"
    }), 3, 3, 0).includes("A 18 18"));
  }

  function test_marks_are_the_ends_alone() {
    // Two open paths: no close, one move per end
    const both = BarOutlines.marks(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "round",
      "endCap": "round"
    }), 1);
    verify(!both.includes("Z"));
    compare(both.split("M").length - 1, 2);
    // A square end's mark is a bracket: arms a quarter of the thickness
    const pts = points(both);
    compare(pts.slice(0, 4), [[8.5, 1], [1, 1], [1, 29], [8.5, 29]]);
    compare(pts.slice(4), [[91.5, 1], [99, 1], [99, 29], [91.5, 29]]);
    // A slant's or an arrow's line, with arms from its corners: a bracket
    compare(points(BarOutlines.marks(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": "arrowOut"
    }), 0)).slice(4), [[77.5, 0], [85, 0], [100, 15], [85, 30], [77.5, 30]]);
    compare(points(BarOutlines.marks(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "slant",
      "endCap": "flat"
    }), 0)).slice(0, 4), [[17.5, 0], [10, 0], [0, 30], [7.5, 30]]);
    // A capsule's half circle alone
    verify(BarOutlines.marks(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "capsule",
      "endCap": "capsule"
    }), 1).includes("A 14 14"));
  }

  // A merged run carried on into the next section's, drawn apart: no line
  // across the join (a divider there), its long sides running to it
  function test_open_ends_leave_the_join_unlined() {
    const closed = BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": "flat"
    }), 1, true);
    verify(closed.endsWith("Z"));
    const end = BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 6,
      "startCap": "round",
      "endCap": "flat",
      "openEnd": true
    }), 1, true);
    verify(!end.includes("Z"), end);
    const ep = points(end);
    // From the end's bottom corner round the start to its top corner, at
    // the very end (no inset there)
    compare(ep[0], [100, 29]);
    compare(ep[ep.length - 1], [100, 1]);
    verify(!ep.slice(1, -1).some(p => p[0] === 100), "nothing across the end: " + end);
    const start = points(BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 6,
      "startCap": "flat",
      "endCap": "round",
      "openStart": true
    }), 1, true));
    compare(start[0], [0, 1]);
    compare(start[start.length - 1], [0, 29]);
    verify(!start.slice(1, -1).some(p => p[0] === 0), "nothing across the start");
    // Both: the two long sides alone
    compare(points(BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": "flat",
      "openStart": true,
      "openEnd": true
    }), 1, true)), [[0, 1], [100, 1], [100, 29], [0, 29]]);
    // The fill stays closed, reaching the open end
    const fill = BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": "flat",
      "openEnd": true
    }), 1, false);
    verify(fill.endsWith("Z"));
    compare(bounds(fill).maxX, 100);
    // Every other stroke: a double's lines run to it, a mark is left out
    const double = BarOutlines.offsetPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": "flat",
      "openEnd": true
    }), 3, 3, 3);
    verify(!double.includes("Z"));
    compare(bounds(double).maxX, 100);
    compare(BarOutlines.marks(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "round",
      "endCap": "flat",
      "openEnd": true
    }), 1).split("M").length - 1, 1);
    compare(BarOutlines.marks(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": "flat",
      "openStart": true,
      "openEnd": true
    }), 1), "");
    // Slanted runs meet flat at a join too
    verify(!BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "slant",
      "endCap": "flat",
      "openEnd": true
    }), 1, true).includes("Z"));
  }

  function test_tab_open_ends_leave_the_join_unlined() {
    const t = square(true);
    // The start side drawn, the inner side running on to the end, no side there
    const end = points(BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "tab",
      "endCap": "flat",
      "tab": t,
      "openEnd": true
    }), 1, true));
    compare(end[end.length - 1][0], 100);
    compare(end[end.length - 1][1], 29);
    compare(end.filter(p => p[0] === 100).length, 1);
    const start = points(BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": "tab",
      "tab": t,
      "openStart": true
    }), 1, true));
    compare(start[0], [0, 29]);
    // Both: the inner side alone
    compare(points(BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": "flat",
      "tab": t,
      "openStart": true,
      "openEnd": true
    }), 1, true)), [[0, 29], [100, 29]]);
    // Marks: none at an open end
    compare(BarOutlines.marks(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": "flat",
      "tab": t,
      "openStart": true,
      "openEnd": true
    }), 1), "");
    // A double's lines too
    const double = points(BarOutlines.offsetPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": "flat",
      "tab": t,
      "openStart": true,
      "openEnd": true
    }), 3, 3, 3));
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
    const parts = subpaths(BarOutlines.dashPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 6,
      "startCap": data.cap,
      "endCap": data.cap
    }), 1));
    compare(parts.length, 2);
    compare(parts[0][0], [50, 1], "starts at the middle");
    compare(parts[1][0], [50, 1]);
    compare(rounded(parts[1]), mirrored(parts[0], 100), "the end's half mirrors the start's");
    compare(parts[0][parts[0].length - 1], [50, 29], "and ends at the other side's middle");
  }

  function test_dash_path_open_ends_run_out_from_the_middle() {
    const parts = subpaths(BarOutlines.dashPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "round",
      "endCap": "flat",
      "openEnd": true
    }), 1));
    compare(parts.length, 3);
    // (the middle between the start's inset and the open end)
    compare(parts[1], [[50.5, 1], [100, 1]]);
    compare(parts[2], [[50.5, 29], [100, 29]]);
  }

  function test_dashed_tab_sides_mirror_its_fillets_apart() {
    const t = BarTabs.tab(6, 26, 6, true, [null, null]);
    const parts = subpaths(BarOutlines.dashPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 6,
      "startCap": "tab",
      "endCap": "tab",
      "tab": t
    }), 1));
    compare(parts.length, 2);
    // From the inner side's middle out round each inner corner
    compare(parts[0][0], [50, 29]);
    compare(rounded(parts[1]), mirrored(parts[0], 100));
    // Up to the fillet, which isn't dashed
    verify(!parts[0].some(p => p[1] === 0), "no dash on the fillet");
    const fillets = subpaths(BarOutlines.fillets(BarShapes.outline({
      "length": 100,
      "across": 30,
      "startCap": "tab",
      "endCap": "tab",
      "tab": t
    }), 1));
    compare(fillets.length, 2);
    compare(fillets[0][0][1], 0, "a fillet starts on the outer edge");
    compare(rounded(fillets[1]), mirrored(fillets[0], 100));
    // Each fillet ends where the side's dashes stop
    compare(rounded([fillets[0][1]]), rounded([parts[0][parts[0].length - 1]]));
    // Square: the sides run to the edge, no fillets
    const square = subpaths(BarOutlines.dashPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 6,
      "startCap": "tab",
      "endCap": "tab",
      "tab": BarTabs.tab(6, 26, 0, true, [null, null])
    }), 1));
    compare(square[0][square[0].length - 1][1], 0);
    compare(BarOutlines.fillets(BarShapes.outline({
      "length": 100,
      "across": 30,
      "startCap": "tab",
      "endCap": "tab",
      "tab": BarTabs.tab(6, 26, 0, true, [null, null])
    }), 1), "");
    // An open end: the inner side to it alone, and no fillet
    const open = subpaths(BarOutlines.dashPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 6,
      "startCap": "tab",
      "endCap": "flat",
      "tab": t,
      "openEnd": true
    }), 1));
    compare(open[1], [[50.5, 29], [100, 29]]);
    compare(subpaths(BarOutlines.fillets(BarShapes.outline({
      "length": 100,
      "across": 30,
      "startCap": "tab",
      "endCap": "flat",
      "tab": t,
      "openEnd": true
    }), 1)).length, 1);
  }

  function test_marks_one_per_seam() {
    // A powerline segment's start at a seam is the one before's end mark
    const mid = BarOutlines.marks(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "arrowIn",
      "endCap": "arrowOut",
      "seamStart": true,
      "seamEnd": true
    }), 1);
    compare(mid.split("M").length - 1, 1);
    // ...which lies on the seam
    verify(points(mid).some(p => p[0] === 100 && p[1] === 15));
  }

  function test_curve_is_a_shallow_arc_to_the_end() {
    // Bulging a quarter of the thickness: its middle reaches the end, its
    // corners stop that far in
    const d = BarShapes.depth("curve", 40);
    compare(d, 10);
    verify(BarShapes.contains(99.5, 20, 100, 40, "flat", "curve"));
    verify(!BarShapes.contains(95, 0.5, 100, 40, "flat", "curve"));
    verify(BarShapes.contains(89, 0.5, 100, 40, "flat", "curve"));
    const b = bounds(BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 40,
      "radius": 0,
      "startCap": "flat",
      "endCap": "curve"
    }), 0));
    compare(b.maxX, 90);
  }

  // Tabs (widgetShape tab): a widget's background out to the edge it
  // hangs from
  function square(outerStart) {
    return BarTabs.tab(6, 26, 0, outerStart, [null, null]);
  }

  function test_square_tab_reaches_its_outer_edge() {
    // Outer edge on top: square corners there, rounded below
    const top = BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "tab",
      "endCap": "tab",
      "tab": square(true)
    }), 0);
    const pts = points(top);
    verify(pts.some(p => p[0] === 0 && p[1] === 0) && pts.some(p => p[0] === 100 && p[1] === 0), top);
    verify(!pts.some(p => p[0] === 0 && p[1] === 30), "inner corners rounded: " + top);
    verify(top.endsWith("Z"));
    // On the far side, flipped
    const bottom = points(BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "tab",
      "endCap": "tab",
      "tab": square(false)
    }), 0));
    compare(bottom, pts.map(p => [p[0], 30 - p[1]]));
  }

  function test_tab_outline_is_open_along_its_outer_edge() {
    const open = BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "tab",
      "endCap": "tab",
      "tab": square(true)
    }), 1, true);
    verify(!open.includes("Z"));
    const pts = points(open);
    // From the outer edge down, round and back up to it, inset but on
    // the outer side
    compare(pts[0], [1, 0]);
    compare(pts[pts.length - 1], [99, 0]);
    compare(bounds(open).maxY, 29);
  }

  function test_flared_tab_curves_out_into_the_edge() {
    const t = BarTabs.tab(6, 26, 6, true, [null, null]);
    const path = BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "tab",
      "endCap": "tab",
      "tab": t
    }), 0);
    const b = bounds(path);
    compare([b.minX, b.maxX, b.minY, b.maxY], [-6, 106, 0, 30]);
    // Concave: swept the other way from the inner corners
    verify(path.includes("A 6 6 0 0 1 0 6") && path.includes("A 6 6 0 0 0 6 30"), path);
  }

  function test_tab_vertical_swaps_the_axes_and_flips_arcs() {
    const t = BarTabs.tab(6, 26, 6, true, [null, null]);
    const across = BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "tab",
      "endCap": "tab",
      "tab": t
    }), 0);
    const down = BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "tab",
      "endCap": "tab",
      "vertical": true,
      "tab": t
    }), 0);
    compare(points(down), points(across).map(p => [p[1], p[0]]));
    verify(down.includes("A 6 6 0 0 0 6 0") && down.includes("A 6 6 0 0 1 30 6"), down);
  }

  // At an island's end the tab's outer corner follows the island's curve:
  // from the outer edge at radius − gap in, round to its side
  function test_tab_takes_a_bounds_corner_curve() {
    const t = BarTabs.tab(6, 26, "square", true, [
      {
        "gap": 4,
        "radius": 10
      },
      null]);
    const path = BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "tab",
      "endCap": "tab",
      "tab": t
    }), 0);
    compare(points(path)[0], [6, 0]);
    // 10 − √(10² − 6²) = 2 down the side
    verify(path.includes("A 10 10 0 0 0 0 2"), path);
  }

  // Split's icon part on a tab: its divider end (a non-tab cap) keeps its
  // shape, the right way up on either side
  function test_tab_with_a_divider_end() {
    const d = 26 / 3;
    const top = points(BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "tab",
      "endCap": "slant",
      "tab": square(true)
    }), 0));
    verify(top.some(p => p[0] === 100 && p[1] === 0) && top.some(p => Math.abs(p[0] - (100 - d)) < 1e-9 && p[1] === 30), JSON.stringify(top));
    // A bottom bar's: the same slant as on a bar without tabs
    const bottom = points(BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "tab",
      "endCap": "slant",
      "tab": square(false)
    }), 0));
    verify(bottom.some(p => p[0] === 100 && p[1] === 0) && bottom.some(p => Math.abs(p[0] - (100 - d)) < 1e-9 && p[1] === 30), JSON.stringify(bottom));
    // A curve bulges out, as drawn without tabs, on both sides
    const plain = BarOutlines.path(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 0,
      "startCap": "flat",
      "endCap": "curve"
    }), 0);
    verify(plain.includes(" 0 0 1 "), plain);
    for (const outerStart of [true, false]) {
      const curve = BarOutlines.path(BarShapes.outline({
        "length": 100,
        "across": 30,
        "radius": 0,
        "startCap": "tab",
        "endCap": "curve",
        "tab": square(outerStart)
      }), 0);
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
    const t = outerStart => BarTabs.tab(6, 26, 6, outerStart, [null, null]);
    for (const outerStart of [true, false])
      for (const vertical of [false, true]) {
        const sw = sweeps(BarOutlines.path(BarShapes.outline({
          "length": 100,
          "across": 30,
          "radius": 0,
          "startCap": "tab",
          "endCap": "tab",
          "vertical": vertical,
          "tab": t(outerStart)
        }), 1, true));
        compare(sw.length, 4);
        compare(sw, sw.slice().reverse());
      }
  }

  // Outline strokes on a tab: open along the edge it hangs from
  function test_tab_double_lines_both_reach_the_edge() {
    const t = BarTabs.tab(6, 26, 6, true, [null, null]);
    const outer = BarOutlines.offsetPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 6,
      "startCap": "tab",
      "endCap": "tab",
      "tab": t
    }), 1, 1, 1);
    const inner = BarOutlines.offsetPath(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 6,
      "startCap": "tab",
      "endCap": "tab",
      "tab": t
    }), 5, 5, 5);
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
    const t = BarTabs.tab(6, 26, 0, true, [null, null]);
    const marks = BarOutlines.marks(BarShapes.outline({
      "length": 100,
      "across": 30,
      "radius": 6,
      "startCap": "tab",
      "endCap": "tab",
      "tab": t
    }), 1);
    verify(!marks.includes("Z"), marks);
    const starts = marks.split("M ").filter(m => m.length > 0).map(m => points("M " + m));
    compare(starts.length, 2);
    // Each from the outer edge in, round its corner, an arm along
    compare(starts[0][0], [1, 0]);
    compare(starts[0][starts[0].length - 1], [7 + 26 / 4, 29]);
    compare(starts[1][0], [99, 0]);
    compare(starts[1][starts[1].length - 1], [93 - 26 / 4, 29]);
  }
}
