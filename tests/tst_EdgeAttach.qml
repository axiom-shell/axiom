import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "EdgeAttach"

  // Radius 28, stroke 2, connector gap 56: a fillet takes 27 along the
  // edge (its arc's run), and on an island 55 (the island's corner too)
  function spec(extra) {
    return Object.assign({
      "pills": [],
      "island": false,
      "merge": 0,
      "centre": 0,
      "aligned": 0,
      "length": 100,
      "joinStart": false,
      "joinEnd": false,
      "joinFrom": -2,
      "joinTo": 1002,
      "lo": 54,
      "hi": 946,
      "islandFrom": 0,
      "islandTo": 1000,
      "straight": false,
      "straightMerged": false,
      "gap": 56,
      "stroke": 2,
      "radius": 28
    }, extra);
  }

  function pill(start, length, joinStart, joinEnd) {
    return {
      "start": start,
      "length": length,
      "joinStart": joinStart ?? false,
      "joinEnd": joinEnd ?? false
    };
  }

  function test_filletMargin() {
    compare(EdgeAttach.filletMargin(2, 28), 27);
    // Too tight a radius for a fillet
    compare(EdgeAttach.filletMargin(2, 0), 0);
  }

  function grow(extra) {
    return EdgeAttach.growth(Object.assign({
      "vertical": true,
      "bottom": false,
      "anchorStart": 100,
      "anchorLength": 40,
      "openLength": 200,
      "maxLength": 400,
      "lo": 54,
      "hi": 946
    }, extra));
  }

  function test_growth_data() {
    return [
      // Away from a horizontal bar, centred along it
      {
        "tag": "top bar",
        "extra": {
          "vertical": false
        },
        "direction": "down",
        "pinned": NaN
      },
      {
        "tag": "bottom bar",
        "extra": {
          "vertical": false,
          "bottom": true
        },
        "direction": "up",
        "pinned": NaN
      },
      // Centred on the anchor (from 20), kept within lo: down from 54
      {
        "tag": "side bar, high",
        "extra": {},
        "direction": "down",
        "pinned": 54
      },
      {
        "tag": "side bar, middle",
        "extra": {
          "anchorStart": 400
        },
        "direction": "down",
        "pinned": 320
      },
      // 720 + 400 passes hi: up from its end, 920
      {
        "tag": "side bar, low",
        "extra": {
          "anchorStart": 800
        },
        "direction": "up",
        "pinned": 920
      },
      // Kept within hi as it opens: up from hi
      {
        "tag": "side bar, at the end",
        "extra": {
          "anchorStart": 900
        },
        "direction": "up",
        "pinned": 946
      },
      // Content that doesn't grow stays where it opened
      {
        "tag": "side bar, no growth",
        "extra": {
          "anchorStart": 800,
          "maxLength": 0
        },
        "direction": "down",
        "pinned": 720
      },
      // Room neither way: the way with more (below 520, above 380)
      {
        "tag": "side bar, too long",
        "extra": {
          "anchorStart": 400,
          "maxLength": 1000
        },
        "direction": "down",
        "pinned": 320
      },
      {
        "tag": "side bar, too long, low",
        "extra": {
          "anchorStart": 600,
          "maxLength": 1000
        },
        "direction": "up",
        "pinned": 720
      }
    ];
  }

  function test_growth(data) {
    const g = grow(data.extra);
    compare(g.direction, data.direction);
    if (isNaN(data.pinned))
      verify(isNaN(g.pinned));
    else
      compare(g.pinned, data.pinned);
  }

  function test_joins() {
    // Pushed back from the start, or within a connector gap of it
    compare(EdgeAttach.joins(60, 100, 54, 946, 56, true, true), {
      "joinStart": true,
      "joinEnd": false
    });
    compare(EdgeAttach.joins(200, 100, 54, 946, 56, true, true), {
      "joinStart": false,
      "joinEnd": false
    });
    compare(EdgeAttach.joins(850, 100, 54, 946, 56, true, true), {
      "joinStart": false,
      "joinEnd": true
    });
    // Nothing to join there
    compare(EdgeAttach.joins(60, 100, 54, 946, 56, false, true).joinStart, false);
    // Content that fills any room joins both
    compare(EdgeAttach.joins(0, Infinity, 54, 946, 56, true, true), {
      "joinStart": true,
      "joinEnd": true
    });
  }

  function test_pillAt() {
    const pills = [pill(100, 100), pill(400, 100)];
    compare(EdgeAttach.pillAt(pills, 150, false).index, 0);
    // Between pills: none, but an island takes the nearest
    compare(EdgeAttach.pillAt(pills, 320, false), null);
    compare(EdgeAttach.pillAt(pills, 320, true).index, 1);
    compare(EdgeAttach.pillAt([], 320, true), null);
  }

  function test_plain_keeps_content_in_place() {
    const p = EdgeAttach.place(spec({
      "aligned": 300.4
    }));
    compare(p.mode, "plain");
    compare([p.start, p.end, p.grow, p.contentOffset], [300, 400, 0, 0]);
    compare([p.startMargin, p.endMargin, p.surfaceStart, p.surfaceLength], [27, 27, 273, 154]);
    compare(p.stretch, null);
    // Past its range it's pulled back in
    compare(EdgeAttach.place(spec({
      "aligned": 900
    })).start, 846);
    // A bare screen edge has no fillets
    const bare = EdgeAttach.place(spec({
      "aligned": 300,
      "straight": true
    }));
    compare([bare.startMargin, bare.endMargin], [0, 0]);
  }

  function test_plain_stops_at_a_wall() {
    // Nothing to join at the end: the surface, its fillet included, goes
    // up to where windows start, keeping their gap from what's past it
    const p = EdgeAttach.place(spec({
      "aligned": 900,
      "wallTo": 800
    }));
    compare([p.start, p.end, p.endMargin, p.joinEnd], [673, 773, 27, false]);
    compare(p.surfaceStart + p.surfaceLength, 800);
    const q = EdgeAttach.place(spec({
      "aligned": 0,
      "wallFrom": 200
    }));
    compare([q.start, q.startMargin, q.joinStart, q.surfaceStart], [227, 27, false, 200]);
  }

  function test_pill_stops_at_a_wall() {
    // The end pill joins the edge past the wall: the box doesn't follow it
    const pills = [pill(300, 702, false, true)];
    const p = EdgeAttach.place(spec({
      "pills": pills,
      "pillBar": true,
      "centre": 900,
      "aligned": 900,
      "pillGrows": true,
      "wallTo": 800
    }));
    compare([p.start, p.end, p.joinEnd, p.flushEnd, p.endMargin], [673, 773, false, false, 27]);
    compare(p.stretch, null);
    // Without one it joins the edge
    compare(EdgeAttach.place(spec({
      "pills": pills,
      "pillBar": true,
      "centre": 900,
      "aligned": 900,
      "pillGrows": true
    })).joinEnd, true);
    // A wall near what pills reach: the full fillet and the pill's full
    // corner still fit inside both, the content moving in for them
    for (const wall of [950, 990]) {
      const q = EdgeAttach.place(spec({
        "pills": pills,
        "pillBar": true,
        "centre": 900,
        "aligned": 900,
        "pillGrows": true,
        "wallTo": wall
      }));
      compare(q.endMargin, 27, `wall ${wall}`);
      verify(q.surfaceStart + q.surfaceLength <= wall, `wall ${wall}: surface past it`);
      compare(q.stretch?.cornerEnd, undefined);
    }
  }

  function test_island_wall_pushes_the_box() {
    // A floating bar owning the corner: its island reaches past the wall
    // over the bar it pushes aside. Short of room for a full fillet inside
    // the wall and the island's corner, the box moves in; nothing rounds
    // less
    const at = wall => EdgeAttach.place(spec({
        "island": true,
        "pills": [pill(10, 980)],
        "islandFrom": 10,
        "centre": 50,
        "aligned": 0,
        "wallFrom": wall
      }));
    for (const wall of [30, 50, 70, 100]) {
      const p = at(wall);
      compare(p.startMargin, 27, `wall ${wall}`);
      verify(p.surfaceStart >= wall, `wall ${wall}: fillet past it`);
      verify(p.start - 10 >= 27 + 28, `wall ${wall}: no room for the island's corner`);
      compare(p.stretch?.cornerStart, undefined);
    }
    compare(at(70).start, 97);
    compare(at(30).start, 65);
  }

  function test_pill_grows_past_a_wall_for_the_fillet() {
    const p = EdgeAttach.place(spec({
      "pills": [pill(300, 520)],
      "pillBar": true,
      "centre": 600,
      "aligned": 900,
      "pillGrows": true,
      "wallTo": 800
    }));
    compare([p.end, p.flushEnd, p.endMargin], [773, false, 27]);
    compare([p.stretch.end, p.stretch.squareEnd], [828, false]);
  }

  function test_island_stops_at_a_wall() {
    const p = EdgeAttach.place(spec({
      "island": true,
      "pills": [pill(100, 890)],
      "centre": 900,
      "aligned": 900,
      "wallTo": 800
    }));
    compare([p.mode, p.end, p.flushEnd, p.endMargin], ["island", 773, false, 27]);
  }

  function test_joined_box_reaches_the_stroke() {
    const p = EdgeAttach.place(spec({
      "aligned": 60,
      "joinStart": true
    }));
    compare([p.start, p.end, p.contentStart, p.contentOffset, p.grow], [-2, 160, 60, 62, 62]);
    compare([p.startMargin, p.endMargin], [0, 27]);
    // Both joined: stroke to stroke
    const both = EdgeAttach.place(spec({
      "aligned": 400,
      "joinStart": true,
      "joinEnd": true
    }));
    compare([both.start, both.end, both.contentStart], [-2, 1002, 400]);
  }

  function test_stands_on_its_pill() {
    const p = EdgeAttach.place(spec({
      "pills": [pill(100, 400)],
      "centre": 200,
      "aligned": 150,
      "length": 100
    }));
    compare(p.mode, "pill");
    compare(p.pill.index, 0);
    // Its fillet won't fit before the pill's start: it runs flush into it,
    // the content staying put
    compare([p.start, p.end, p.contentStart, p.flushStart, p.flushEnd], [100, 250, 150, true, false]);
    compare([p.stretch.start, p.stretch.end, p.stretch.squareStart], [100, 500, true]);
    // Well inside, no stretch
    compare(EdgeAttach.place(spec({
      "pills": [pill(0, 1000)],
      "centre": 500,
      "aligned": 450
    })).stretch, null);
  }

  function test_extends_its_pill_like_an_island() {
    const p = EdgeAttach.place(spec({
      "pills": [pill(100, 200), pill(600, 300)],
      "pillBar": true,
      "centre": 250,
      "aligned": 200,
      "length": 200
    }));
    compare(p.mode, "pill");
    compare([p.start, p.end, p.flushStart, p.flushEnd], [200, 400, false, true]);
    // Stretched out to the box's end, squared there
    compare([p.stretch.index, p.stretch.start, p.stretch.end, p.stretch.squareEnd], [0, 100, 400, true]);
    // A pill bar showing none grows from its outer edge
    compare(EdgeAttach.place(spec({
      "pillBar": true,
      "aligned": 300
    })).mode, "merged");
  }

  function test_joins_where_its_pill_joins_the_edge() {
    const p = EdgeAttach.place(spec({
      "pills": [pill(-2, 300, true, false)],
      "pillBar": true,
      "centre": 100,
      "aligned": 50,
      "length": 200
    }));
    compare([p.start, p.joinStart, p.flushStart, p.startMargin, p.contentStart], [-2, true, false, 0, 50]);
    compare([p.end, p.flushEnd], [298, true]);
  }

  function test_pill_joins_the_edge_it_comes_within_a_gap_of() {
    // Its fillet fits before the pill's end, but the box is within a
    // connector gap of the edge (joins): it joins, from its pill
    const p = EdgeAttach.place(spec({
      "pills": [pill(-2, 300, true, false)],
      "pillBar": true,
      "centre": 100,
      "aligned": 80,
      "length": 100,
      "joinStart": true,
      "pillJoins": true,
      "pillFrom": -2,
      "pillTo": 1002,
      "pillGrows": true
    }));
    compare([p.mode, p.start, p.joinStart, p.startMargin, p.contentStart], ["pill", -2, true, 0, 80]);
  }

  function test_pill_joins_the_stroke_it_runs_on_past() {
    // A pill joining the edge runs on past its stroke (under a bar making
    // way for this one at that corner): a side whose fillet would pass the
    // stroke joins it there
    const p = EdgeAttach.place(spec({
      "pills": [pill(700, 360, false, true)],
      "pillBar": true,
      "centre": 850,
      "aligned": 900,
      "length": 100,
      "joinTo": 1002,
      "pillGrows": true
    }));
    compare([p.mode, p.end, p.joinEnd, p.flushEnd, p.endMargin], ["pill", 1002, true, false, 0]);
    compare(p.stretch, null, "the pill already reaches past it");
  }

  function test_pill_past_the_unjoined_reach_joins() {
    // Its pill runs on past where an unjoined box may reach (past a
    // perpendicular bar's far stroke, at a corner its bar owns): a side
    // running flush to it joins that edge rather than running on behind
    // what's there
    const s = {
      "pills": [pill(700, 290)],
      "pillBar": true,
      "centre": 850,
      "aligned": 800,
      "length": 150,
      "joinTo": 960,
      "pillJoins": true,
      "pillTo": 1000,
      "pillGrows": true
    };
    const p = EdgeAttach.place(spec(Object.assign({}, s, {
      "joinableEnd": true
    })));
    compare([p.end, p.joinEnd, p.flushEnd, p.endMargin], [960, true, false, 0]);
    compare([p.stretch.end, p.stretch.joinEnd], [1000, true]);
    // An end that can't join still runs flush
    const q = EdgeAttach.place(spec(s));
    compare([q.end, q.joinEnd, q.flushEnd], [990, false, true]);
    // A box keeping its fillet short of the limit is left alone
    const r = EdgeAttach.place(spec(Object.assign({}, s, {
      "joinableEnd": true,
      "aligned": 720,
      "length": 100
    })));
    compare([r.end, r.joinEnd, r.flushEnd, r.endMargin], [820, false, false, 27]);
  }

  function test_pill_joins_the_edges_with_the_box() {
    // A box filling the edge on a pill bar joins both ends from the pill
    // under its centre, which stretches to the bar's ends and joins them
    const p = EdgeAttach.place(spec({
      "pills": [pill(20, 100), pill(450, 100), pill(880, 100)],
      "pillBar": true,
      "centre": 500,
      "aligned": -2,
      "length": 1004,
      "joinStart": true,
      "joinEnd": true,
      "pillJoins": true,
      "pillFrom": -3,
      "pillTo": 1003,
      "pillGrows": true
    }));
    compare([p.mode, p.start, p.end, p.joinStart, p.joinEnd, p.flushStart, p.flushEnd], ["pill", -2, 1002, true, true, false, false]);
    compare([p.stretch.index, p.stretch.start, p.stretch.end, p.stretch.joinStart, p.stretch.joinEnd, p.stretch.squareStart, p.stretch.squareEnd], [1, -3, 1003, true, true, false, false]);
    // Not joining the edges, it runs flush into its pill's stretch
    const q = EdgeAttach.place(spec({
      "pills": [pill(20, 100), pill(450, 100), pill(880, 100)],
      "pillBar": true,
      "centre": 500,
      "aligned": -2,
      "length": 1004,
      "pillJoins": true,
      "pillGrows": true
    }));
    compare([q.joinStart, q.flushStart, q.stretch.joinStart], [false, true, false]);
  }

  function test_island_fits() {
    const p = EdgeAttach.place(spec({
      "island": true,
      "pills": [pill(100, 800)],
      "centre": 400,
      "aligned": 300,
      "length": 200
    }));
    compare(p.mode, "island");
    compare([p.start, p.end, p.flushStart, p.flushEnd, p.contentOffset], [300, 500, false, false, 0]);
    compare(p.stretch, null);
  }

  function test_island_short_side_reaches_its_end() {
    const p = EdgeAttach.place(spec({
      "island": true,
      "pills": [pill(100, 800)],
      "centre": 220,
      "aligned": 120,
      "length": 200
    }));
    // The content stays put; the box reaches back to the island's start
    compare([p.start, p.end, p.contentStart, p.contentOffset], [100, 320, 120, 20]);
    compare([p.flushStart, p.flushEnd, p.startMargin, p.endMargin], [true, false, 0, 27]);
    compare([p.stretch.start, p.stretch.end, p.stretch.squareStart, p.stretch.squareEnd], [100, 900, true, false]);
  }

  function test_island_shorter_than_the_box_stretches() {
    // A centred launcher over a narrower island: neither moves the content
    const p = EdgeAttach.place(spec({
      "island": true,
      "pills": [pill(400, 200)],
      "centre": 500,
      "aligned": 300,
      "length": 400
    }));
    compare([p.start, p.end, p.contentOffset, p.flushStart, p.flushEnd], [300, 700, 0, true, true]);
    compare([p.stretch.start, p.stretch.end, p.stretch.squareStart, p.stretch.squareEnd], [300, 700, true, true]);
  }

  function test_island_reaches_neighbours_within_merge() {
    // The next island is near enough to join, so the end keeps its fillet
    const p = EdgeAttach.place(spec({
      "island": true,
      "merge": 30,
      "pills": [pill(100, 200), pill(320, 180)],
      "centre": 200,
      "aligned": 150,
      "length": 200
    }));
    compare([p.flushStart, p.flushEnd], [true, false]);
    compare([p.stretch.index, p.stretch.start, p.stretch.end], [0, 100, 405]);
  }

  function test_island_nearest_when_centred_between() {
    const p = EdgeAttach.place(spec({
      "island": true,
      "pills": [pill(100, 100), pill(700, 100)],
      "centre": 500,
      "aligned": 400,
      "length": 200
    }));
    compare(p.pill.index, 1);
    // The island stretches back under the box: its start runs flush into
    // the stretched end, its end keeps a fillet on the island
    compare([p.start, p.end, p.contentStart, p.flushStart, p.flushEnd], [400, 600, 400, true, false]);
    compare([p.stretch.start, p.stretch.end], [400, 800]);
  }

  // With `between`, a box centred between pills (or islands) and clear of
  // them grows from the bar's outer edge, a fillet each side
  function test_between_pills() {
    const apart = [pill(100, 100), pill(700, 100)];
    const p = EdgeAttach.place(spec({
      "pills": apart,
      "between": true,
      "centre": 450,
      "aligned": 400
    }));
    compare([p.mode, p.pill, p.stretch], ["between", null, null]);
    compare([p.start, p.end, p.surfaceStart, p.surfaceLength], [400, 500, 373, 154]);
    // Islands alike
    compare(EdgeAttach.place(spec({
      "pills": apart,
      "island": true,
      "between": true,
      "centre": 450,
      "aligned": 400
    })).mode, "between");
    // Without `between` (submenus): out of the nearest, as ever
    compare(EdgeAttach.place(spec({
      "pills": apart,
      "centre": 450,
      "aligned": 400
    })).mode, "pill");
    // Centred on a pill: out of it
    compare(EdgeAttach.place(spec({
      "pills": apart,
      "between": true,
      "centre": 150,
      "aligned": 100
    })).mode, "pill");
  }

  function test_between_needs_room() {
    const at = (merge, aligned) => EdgeAttach.place(spec({
        "pills": [pill(100, 100), pill(700, 100)],
        "merge": merge,
        "between": true,
        "centre": aligned + 50,
        "aligned": aligned
      }));
    // Two fillets' room (54) from the pill, and no less
    compare(at(0, 254).mode, "between");
    compare(at(0, 253).mode, "pill");
    // More than the merge distance, where that's further
    compare(at(80, 281).mode, "between");
    compare(at(80, 280).mode, "pill");
  }

  // With no room taken by a fillet or corner (radius 0), a side reaching
  // the pill's end exactly runs flush into it, as a nearer one would
  function test_sharp_side_at_the_end_is_flush() {
    const at = (aligned, grows) => EdgeAttach.place(spec({
        "pills": [pill(100, 400)],
        "radius": 0,
        "centre": aligned + 50,
        "aligned": aligned,
        "pillGrows": grows
      }));
    for (const grows of [false, true]) {
      compare([at(100, grows).flushStart, at(100, grows).flushEnd], [true, false], "start, pillGrows " + grows);
      compare([at(400, grows).flushStart, at(400, grows).flushEnd], [false, true], "end, pillGrows " + grows);
      compare([at(200, grows).flushStart, at(200, grows).flushEnd], [false, false], "inside, pillGrows " + grows);
    }
    // A radius keeps the side at the end standing on it, its fillet room
    // taken from the pill grown past it
    compare(EdgeAttach.place(spec({
      "pills": [pill(100, 400)],
      "centre": 150,
      "aligned": 100,
      "pillGrows": true
    })).flushStart, false);
  }

  function test_nudge_up_to_the_pill_end() {
    // 20 short of room for its fillet before the pill's start: up to it,
    // flush and no empty box, rather than 62 back
    const p = EdgeAttach.place(spec({
      "pills": [pill(100, 400)],
      "centre": 170,
      "aligned": 120,
      "nudge": true
    }));
    compare([p.start, p.end, p.contentStart, p.grow, p.flushStart, p.flushEnd], [100, 200, 100, 0, true, false]);
    // The same at the end
    const q = EdgeAttach.place(spec({
      "pills": [pill(100, 400)],
      "centre": 430,
      "aligned": 380,
      "nudge": true
    }));
    compare([q.start, q.end, q.contentStart, q.grow, q.flushStart, q.flushEnd], [400, 500, 400, 0, false, true]);
  }

  function test_nudge_back_for_the_fillet() {
    // 50 in from the pill's start: 5 back gives it its fillet instead
    const p = EdgeAttach.place(spec({
      "pills": [pill(100, 400)],
      "centre": 200,
      "aligned": 150,
      "nudge": true
    }));
    compare([p.start, p.end, p.contentStart, p.grow, p.flushStart, p.startMargin], [155, 255, 155, 0, false, 27]);
    compare(p.stretch, null);
  }

  function test_nudge_leaves_both_short_sides() {
    // Too narrow a pill for either fillet: nothing to gain by moving
    const p = EdgeAttach.place(spec({
      "island": true,
      "pills": [pill(400, 200)],
      "centre": 500,
      "aligned": 300,
      "length": 400,
      "nudge": true
    }));
    compare([p.start, p.end, p.contentStart, p.flushStart, p.flushEnd], [300, 700, 300, true, true]);
  }

  function test_pill_grows_for_a_fillet_short_of_its_start() {
    // 50 in from the pill's start, 5 short of a fillet's room: the pill
    // grows back under it, the box keeping to its content
    const p = EdgeAttach.place(spec({
      "pills": [pill(100, 400)],
      "pillBar": true,
      "centre": 200,
      "aligned": 150,
      "pillGrows": true
    }));
    compare([p.start, p.end, p.contentStart, p.grow, p.flushStart, p.startMargin], [150, 250, 150, 0, false, 27]);
    compare([p.stretch.start, p.stretch.end, p.stretch.squareStart], [95, 500, false]);
  }

  function test_pill_grows_for_a_fillet_short_of_its_end() {
    const p = EdgeAttach.place(spec({
      "pills": [pill(100, 400)],
      "pillBar": true,
      "centre": 430,
      "aligned": 380,
      "pillGrows": true
    }));
    compare([p.start, p.end, p.grow, p.flushEnd, p.endMargin], [380, 480, 0, false, 27]);
    compare([p.stretch.start, p.stretch.end, p.stretch.squareEnd], [100, 535, false]);
  }

  function test_island_grows_towards_a_neighbour_within_merge() {
    // Its fillet room reaches within merge of the next island: the two
    // draw as one, and the box keeps to its content at both ends
    const p = EdgeAttach.place(spec({
      "island": true,
      "merge": 30,
      "pills": [pill(100, 200), pill(320, 180)],
      "centre": 200,
      "aligned": 150,
      "length": 200,
      "pillGrows": true
    }));
    compare([p.start, p.end, p.grow, p.flushStart, p.flushEnd], [150, 350, 0, false, false]);
    compare([p.stretch.index, p.stretch.start, p.stretch.end], [0, 95, 405]);
  }

  function test_pill_grows_not_past_where_islands_reach() {
    // No room past the island's start for the fillet: flush, as without
    const p = EdgeAttach.place(spec({
      "island": true,
      "pills": [pill(20, 800)],
      "centre": 100,
      "aligned": 50,
      "pillGrows": true
    }));
    compare([p.start, p.contentStart, p.flushStart, p.startMargin], [20, 50, true, 0]);
  }

  function test_pill_grows_still_joins_the_edge() {
    const p = EdgeAttach.place(spec({
      "pills": [pill(-2, 300, true, false)],
      "pillBar": true,
      "centre": 100,
      "aligned": 50,
      "length": 200,
      "pillGrows": true
    }));
    compare([p.start, p.joinStart, p.flushStart, p.contentStart], [-2, true, false, 50]);
  }

  function test_joinOpening() {
    // A top bar's surface joined at its start covers the left edge's
    // stroke from the screen's top down to its join
    compare(EdgeAttach.joinOpening("top", true, 10, 100, 60, 1440), {
      "edge": "left",
      "start": 0,
      "end": 70
    });
    // A left edge's joined at its end: the bottom edge's, from the left
    compare(EdgeAttach.joinOpening("left", false, 12, 500, 40, 3440), {
      "edge": "bottom",
      "start": 0,
      "end": 52
    });
    // From the far side: a right edge's, up to the screen's width
    compare(EdgeAttach.joinOpening("right", true, 3000, 400, 50, 3440), {
      "edge": "top",
      "start": 3350,
      "end": 3440
    });
    // With its fillet: at the far end of its cover, which is the
    // stretch's end from the near side and its start from the far one
    compare(EdgeAttach.joinOpening("top", true, 10, 100, 60, 1440, 24), {
      "edge": "left",
      "start": 0,
      "end": 70,
      "endFillet": 24
    });
    compare(EdgeAttach.joinOpening("right", true, 3000, 400, 50, 3440, 24), {
      "edge": "top",
      "start": 3350,
      "end": 3440,
      "startFillet": 24
    });
    // None, or a straight join's 0, adds nothing
    compare(EdgeAttach.joinOpening("top", true, 10, 100, 60, 1440, 0), {
      "edge": "left",
      "start": 0,
      "end": 70
    });
  }

  function test_pillJoinFilleted() {
    // A bar 1000 long, the surface at its end, its wall at 800; radius
    // 24 (a fillet and a corner need 48), no merge, stroke 3
    const at = (pills, merge) => EdgeAttach.pillJoinFilleted(pills, 800, false, 24, merge ?? 0, 3);
    // A pill running on well past the wall: filleted
    verify(at([
      {
        "start": 600,
        "length": 400
      }
    ]));
    // One showing past it by less than a fillet and a corner (the
    // bottom-left OSD on two pill bars): filleted too, stretched to carry
    // it, as it can't square at the wall
    verify(at([
      {
        "start": 770,
        "length": 230
      }
    ]));
    // At the wall's outer edge (half a stroke out), where a straight
    // join squares it: straight
    verify(!at([
      {
        "start": 798,
        "length": 202
      }
    ]));
    // Showing past that edge at all, however little: filleted, the pill
    // stretched out to carry it rather than squared out of the wall's line
    verify(at([
      {
        "start": 797,
        "length": 203
      }
    ]));
    // All under the box: straight, into a stub
    verify(!at([
      {
        "start": 850,
        "length": 150
      }
    ]));
    // Ending short of the fillet's corner: straight, unless within merge
    verify(!at([
      {
        "start": 500,
        "length": 240
      }
    ]));
    verify(at([
      {
        "start": 500,
        "length": 240
      }
    ], 20));
    // The same from the start: the surface at the top, its wall at 200
    const st = pills => EdgeAttach.pillJoinFilleted(pills, 200, true, 24, 0, 3);
    verify(st([
      {
        "start": 0,
        "length": 230
      }
    ]));
    verify(!st([
      {
        "start": 0,
        "length": 202
      }
    ]));
    verify(st([
      {
        "start": 240,
        "length": 100
      }
    ]));
    verify(!st([
      {
        "start": 260,
        "length": 100
      }
    ]));
    verify(!EdgeAttach.pillJoinFilleted(null, 200, true, 24, 0, 3));
  }

  function test_pill_grows_runs_flush_past_its_end() {
    // Content past the island's ends: flush, the island stretched to it
    const p = EdgeAttach.place(spec({
      "island": true,
      "pills": [pill(400, 200)],
      "centre": 500,
      "aligned": 300,
      "length": 400,
      "pillGrows": true
    }));
    compare([p.start, p.end, p.grow, p.flushStart, p.flushEnd], [300, 700, 0, true, true]);
  }

  function test_progressStretch() {
    const rest = {
      "start": 400,
      "length": 200
    };
    const target = {
      "index": 2,
      "start": 300,
      "end": 700,
      "squareEnd": true
    };
    compare(EdgeAttach.progressStretch(rest, target, 0), null);
    compare(EdgeAttach.progressStretch(rest, null, 1), null);
    const half = EdgeAttach.progressStretch(rest, target, 0.5);
    compare(half.start, 350);
    compare(half.end, 650);
    compare(half.index, 2);
    verify(half.squareEnd, "its flags kept");
    const full = EdgeAttach.progressStretch(rest, target, 1);
    compare(full.start, 300);
    compare(full.end, 700);
    // Inside the pill's own span: never drawn back past it
    const inside = EdgeAttach.progressStretch(rest, {
      "index": 2,
      "start": 450,
      "end": 550
    }, 1);
    compare(inside.start, 400);
    compare(inside.end, 600);
  }
}
