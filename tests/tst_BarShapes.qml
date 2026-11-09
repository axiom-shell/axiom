import QtQuick
import QtTest
import qs.components.methods

// Caps, segments, hit tests, outline specs and box rects (BarShapes)
TestCase {
  name: "BarShapes"

  function test_separate_widgets_have_both_ends() {
    const s = BarShapes.segment({
      "name": "arrow",
      "ends": "shaped"
    }, "separate", true, 1, 3, 30);
    compare([s.startCap, s.endCap, s.back, s.lead, s.trail], ["arrowIn", "arrowOut", 0, 15, 10]);
    const r = BarShapes.segment({
      "name": "rounded",
      "ends": "shaped"
    }, "separate", true, 0, 1, 30);
    compare([r.startCap, r.endCap, r.lead, r.trail], ["round", "round", 0, 0]);
  }

  function test_merged_runs_cap_only_their_ends() {
    const first = BarShapes.segment({
      "name": "slant",
      "ends": "shaped"
    }, "merged", true, 0, 3, 30);
    const middle = BarShapes.segment({
      "name": "slant",
      "ends": "shaped"
    }, "merged", true, 1, 3, 30);
    const last = BarShapes.segment({
      "name": "slant",
      "ends": "shaped"
    }, "merged", true, 2, 3, 30);
    compare([first.startCap, first.lead, first.trail], ["slant", 9, 0]);
    compare([middle.startCap, middle.endCap, middle.lead, middle.trail, middle.back], ["flat", "flat", 0, 0, 0]);
    compare([last.endCap, last.trail], ["slant", 9]);
  }

  function test_levels_keep_their_own_caps() {
    const middle = BarShapes.segment({
      "name": "capsule",
      "ends": "shaped"
    }, "merged", true, 1, 3, 30);
    compare([middle.levelStartCap, middle.levelEndCap], ["capsule", "capsule"]);
    const first = BarShapes.segment({
      "name": "rounded",
      "ends": "shaped"
    }, "merged", true, 0, 2, 30);
    compare([first.levelStartCap, first.levelEndCap], ["round", "round"]);
    const lone = BarShapes.segment({
      "name": "arrow",
      "ends": "shaped"
    }, "separate", true, 0, 1, 30);
    compare([lone.levelStartCap, lone.levelEndCap], ["arrowIn", "arrowOut"]);
    const segment = BarShapes.segment({
      "name": "arrow",
      "ends": "shaped"
    }, "powerline", false, 1, 3, 30);
    compare([segment.levelStartCap, segment.levelEndCap], ["arrowIn", "arrowOut"]);
  }

  function test_powerline_segments_overlap() {
    const first = BarShapes.segment({
      "name": "arrow",
      "ends": "shaped"
    }, "powerline", true, 0, 2, 30);
    const second = BarShapes.segment({
      "name": "arrow",
      "ends": "shaped"
    }, "powerline", true, 1, 2, 30);
    compare([first.startCap, first.endCap, first.back, first.lead], ["arrowIn", "arrowOut", 0, 15]);
    // Opaque: square, beneath the arrow before it
    compare([second.startCap, second.back, second.lead], ["flat", 15, 0]);
    compare(second.endCap, "arrowOut");
    // See-through: fitted against it instead
    compare(BarShapes.segment({
      "name": "arrow",
      "ends": "shaped"
    }, "powerline", false, 1, 2, 30).startCap, "arrowIn");
    compare(BarShapes.segment({
      "name": "rounded",
      "ends": "shaped"
    }, "powerline", false, 1, 2, 30).startCap, "roundIn");
    compare(BarShapes.segment({
      "name": "slant",
      "ends": "shaped"
    }, "powerline", false, 1, 2, 30).startCap, "slant");
  }

  // Content sits centred on what shows of a segment: from half a join
  // before its box (the cap before reaching in) to half a join before its
  // end (its own cap tapering)
  function test_powerline_content_is_centred_on_what_shows() {
    const join = 15;
    const at = index => BarShapes.segment({
        "name": "arrow",
        "ends": "shaped"
      }, "powerline", true, index, 3, 30);
    const first = at(0), middle = at(1), last = at(2);
    compare([first.lead, first.trail], [15, join / 2]);
    compare([middle.lead, middle.trail], [0, join]);
    compare([last.lead, last.trail], [0, join / 2 + 10]);
  }

  // widgetEnds: a run's own ends notched and pointed (shaped), pointed at
  // both (an arrow's alone: a slant keeps its slant), or rounded
  function test_run_ends() {
    const caps = (shape, ends, grouping) => {
      const first = BarShapes.segment({
        "name": shape,
        "ends": ends
      }, grouping, true, 0, 2, 30);
      const last = BarShapes.segment({
        "name": shape,
        "ends": ends
      }, grouping, true, 1, 2, 30);
      return [first.startCap, last.endCap, first.lead];
    };
    ["separate", "merged", "powerline"].forEach(grouping => {
      compare(caps("arrow", "shaped", grouping), ["arrowIn", "arrowOut", 15]);
      compare(caps("arrow", "pointed", grouping), ["arrowOut", "arrowOut", 10]);
      compare(caps("arrow", "rounded", grouping), ["round", "round", 0]);
      compare(caps("slant", "pointed", grouping), ["slant", "slant", 9]);
      compare(caps("slant", "rounded", grouping), ["round", "round", 0]);
      compare(caps("capsule", "rounded", grouping), ["capsule", "capsule", 4]);
    });
    // Rounded ends keep a powerline's joins, and its content centred
    const last = BarShapes.segment({
      "name": "arrow",
      "ends": "rounded"
    }, "powerline", true, 1, 2, 30);
    compare([last.back, last.trail], [15, 7.5]);
  }

  function test_powerline_seams() {
    const opaque = BarShapes.segment({
      "name": "rounded",
      "ends": "shaped"
    }, "powerline", true, 1, 3, 30);
    const clear = BarShapes.segment({
      "name": "rounded",
      "ends": "shaped"
    }, "powerline", false, 1, 3, 30);
    compare([opaque.seamStart, opaque.seamEnd], [false, false]);
    compare([clear.seamStart, clear.seamEnd], [true, true]);
    const alone = BarShapes.segment({
      "name": "rounded",
      "ends": "shaped"
    }, "separate", false, 0, 1, 30);
    compare([alone.seamStart, alone.seamEnd], [false, false]);
  }

  function test_shown_start_follows_the_cap_before() {
    compare(BarShapes.segment({
      "name": "slant",
      "ends": "shaped"
    }, "powerline", true, 1, 2, 30).shownStart, "slant");
    compare(BarShapes.segment({
      "name": "arrow",
      "ends": "shaped"
    }, "powerline", true, 1, 2, 30).shownStart, "arrowIn");
    compare(BarShapes.segment({
      "name": "slant",
      "ends": "shaped"
    }, "merged", true, 1, 3, 30).shownStart, "flat");
    compare(BarShapes.segment({
      "name": "slant",
      "ends": "shaped"
    }, "separate", true, 0, 1, 30).shownStart, "slant");
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

  function test_tab_caps_keep_no_room() {
    const lone = BarShapes.segment({
      "name": "tab",
      "ends": "shaped"
    }, "separate", true, 0, 1, 30);
    compare([lone.startCap, lone.endCap, lone.lead, lone.trail, lone.back], ["tab", "tab", 0, 0, 0]);
    const middle = BarShapes.segment({
      "name": "tab",
      "ends": "shaped"
    }, "merged", true, 1, 3, 30);
    compare([middle.startCap, middle.endCap, middle.levelStartCap], ["flat", "flat", "tab"]);
  }

  function test_tab_hits_reach_its_outer_edge() {
    verify(BarShapes.contains(1, 1, 100, 30, "tab", "tab"));
    verify(BarShapes.contains(99, 29, 100, 30, "tab", "tab"));
  }

  // An outline spec: what it leaves out is 0, false or null
  function test_outline_spec_fills_its_defaults() {
    compare(BarShapes.outline({
      "length": 80,
      "across": 26,
      "startCap": "slant"
    }), {
      "length": 80,
      "across": 26,
      "radius": 0,
      "startCap": "slant",
      "endCap": "flat",
      "vertical": false,
      "seamStart": false,
      "seamEnd": false,
      "tab": null,
      "openStart": false,
      "openEnd": false
    });
    const t = BarTabs.tab(6, 26, 0, true, [null, null]);
    const o = BarShapes.outline({
      "length": 80,
      "across": 26,
      "radius": 6,
      "startCap": "tab",
      "endCap": "tab",
      "vertical": true,
      "seamStart": true,
      "seamEnd": true,
      "tab": t,
      "openStart": true,
      "openEnd": true
    });
    compare([o.radius, o.vertical, o.seamStart, o.seamEnd, o.openStart, o.openEnd], [6, true, true, true, true, true]);
    compare(o.tab, t);
  }

  // A box past its item: back along the bar, out across to a tab's edge,
  // and on past its end
  function test_box_rect() {
    const host = {
      "x": 10,
      "y": 2,
      "width": 40,
      "height": 26
    };
    compare(BarShapes.boxRect(host, 0, 0, 0, false), host, "nothing past it");
    compare(BarShapes.boxRect(host, 5, 0, 0, false), {
      "x": 5,
      "y": 2,
      "width": 45,
      "height": 26
    }, "back under the one before");
    compare(BarShapes.boxRect(host, 5, 4, 0, false), {
      "x": 5,
      "y": -2,
      "width": 45,
      "height": 30
    }, "a tab from a top bar: out before its near side");
    compare(BarShapes.boxRect(host, 0, 0, 4, false, 7), {
      "x": 10,
      "y": 2,
      "width": 47,
      "height": 30
    }, "a tab from a bottom bar, on past its end");
    compare(BarShapes.boxRect({
      "x": 2,
      "y": 10,
      "width": 26,
      "height": 40
    }, 5, 4, 0, true, 7), {
      "x": -2,
      "y": 5,
      "width": 30,
      "height": 52
    }, "vertical: along runs down");
  }

  // An outline's band: one line, a double's three, an Ends only mark's
  // end line
  function test_stroke_band() {
    compare(BarShapes.strokeBand(null), 0);
    compare(BarShapes.strokeBand({
      "width": 2,
      "stroke": "solid"
    }), 2);
    compare(BarShapes.strokeBand({
      "width": 2,
      "stroke": "double"
    }), 6);
    compare(BarShapes.strokeBand({
      "width": 3,
      "stroke": "ends"
    }), 3);
  }

  // A run's ends keep their content (the middle two thirds across) clear
  // of the cap's curve where it reaches into the content's rows and of
  // the stroke inset round it, in whole pixels; a run's middle keeps none
  function test_run_ends_keep_clear_of_the_curve_and_the_stroke() {
    const room = (name, outline, radius, grouping, index, count) => {
      const s = BarShapes.segment({
        "name": name,
        "ends": "shaped",
        "radius": radius,
        "outline": outline
      }, grouping ?? "separate", false, index ?? 0, count ?? 1, 30);
      return [s.lead, s.trail];
    };
    const solid = {
      "width": 2,
      "stroke": "solid"
    };
    const double = {
      "width": 2,
      "stroke": "double"
    };
    // Rounded, radius 8 at 30: the content's edge 5 in, 3 past the
    // corner's centre: 8 - sqrt(8² - 3²) = 0.58
    compare(room("rounded", null, 8), [1, 1]);
    // A 2 px stroke: its inner edge 6 round the same centre
    compare(room("rounded", solid, 8), [3, 3]);
    compare(room("rounded", {
      "width": 2,
      "stroke": "ends"
    }, 8), [3, 3], "ends only: the end's line");
    // A radius the content's rows don't reach: just the stroke
    compare(room("rounded", solid, 4), [2, 2]);
    compare(room("rounded", null, 4), [0, 0]);
    // Capsule: 15 - sqrt(13² - 10²) = 6.69 with the stroke
    compare(room("capsule", null, 8), [4, 4]);
    compare(room("capsule", solid, 8), [7, 7]);
    // Double: three widths, past the content's edge row: the corner's
    // centre, as far as a curve reaches
    compare(room("rounded", double, 8), [8, 8]);
    compare(room("rounded", double, 0), [6, 6]);
    // Slant: its side at the content's edge (5/6 of its depth), the
    // stroke square to it (2 * sqrt(30² + 10²) / 30)
    compare(room("slant", null, 8), [9, 9]);
    compare(room("slant", solid, 8), [11, 11]);
    // Arrow: the notch's middle, the point's sides at the content's edges
    compare(room("arrow", null, 8), [15, 10]);
    compare(room("arrow", solid, 8), [18, 13]);
    // Tab: its inner corners, as a rounded end's
    compare(room("tab", solid, 8), [3, 3]);
    // A merged run: its ends only
    compare(room("rounded", solid, 8, "merged", 0, 3), [3, 0]);
    compare(room("rounded", solid, 8, "merged", 1, 3), [0, 0]);
    compare(room("rounded", solid, 8, "merged", 2, 3), [0, 3]);
    // A powerline's joins keep their own room (half a join), not the stroke's
    compare(room("rounded", solid, 8, "powerline", 1, 3), [0, 15]);
  }

  // No box drawn at its ends (an unboxed style, a separate badge): its
  // content keeps no room there
  function test_uncapped_ends_keep_no_room() {
    const s = BarShapes.segment({
      "name": "slant",
      "ends": "shaped",
      "radius": 8,
      "outline": null,
      "capped": false
    }, "separate", false, 0, 1, 30);
    compare([s.startCap, s.lead, s.trail], ["slant", 0, 0]);
  }
}
