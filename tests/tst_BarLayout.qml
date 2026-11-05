import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "BarLayout"

  function m(pref, min = pref, priority = 0) {
    return {
      "pref": pref,
      "min": min,
      "priority": priority
    };
  }

  // A spacer keeping `minGap`
  function spacer(minGap = 0) {
    return {
      "pref": minGap,
      "min": minGap,
      "priority": 0,
      "divides": true,
      "fill": true
    };
  }

  function test_layoutSections_uneven_margins() {
    // A bar whose end makes way for another keeps more clear there
    const s = BarLayout.layoutSections([100, 200, 100], [50, 200, 50], 1000, [10, 60], 5, false);
    compare(s[0].offset, 10);
    compare(s[2].offset, 1000 - 60 - 100);
    compare(s[1].offset, 400, "the center stays centered on the bar");
    // Squeezed into what both margins leave
    const t = BarLayout.layoutSections([300, 0, 300], [100, 0, 100], 600, [10, 70], 0, false);
    compare(t[0].extent + t[2].extent, 520);
    compare(t[2].offset + t[2].extent, 530);
    // Overflow measures the same room
    compare(BarLayout.overflowHidden([[m(300)], [], [m(230)]], 600, [10, 70], 0, 0, false)[2].length, 1);
    compare(BarLayout.overflowHidden([[m(300)], [], [m(230)]], 600, 10, 0, 0, false)[2].length, 0);
  }

  function test_span() {
    compare(BarLayout.span([], 4), 0);
    compare(BarLayout.span([10], 4), 10);
    compare(BarLayout.span([10, 20, 30], 4), 68);
    // Zero sizes take no spacing
    compare(BarLayout.span([10, 0, 30, 0], 4), 44);
  }

  function test_span_spacers() {
    // A spacer lies in the gap between two widgets: collapsed, one gap
    compare(BarLayout.span([10, 0, 30], 4, [false, true, false]), 44);
    compare(BarLayout.span([10, 20, 30], 4, [false, true, false]), 64);
    // At an end it takes its own size, no gap
    compare(BarLayout.span([5, 10], 4, [true, false]), 15);
    compare(BarLayout.span([10, 0], 4, [false, true]), 10);
  }

  function test_dividerGap() {
    compare(BarLayout.dividerLength("line", 20), 10);
    compare(BarLayout.dividerLength("chevron", 20), 12);
    // The divider's room along the bar, the margin either side
    compare(BarLayout.dividerGap("line", 2, 20, 2), 6);
    compare(BarLayout.dividerGap("dot", 2, 20, 3), 10);
    compare(BarLayout.dividerGap("slash", 2, 20, 0), 6);
    compare(BarLayout.dividerGap("chevron", 2, 20, 1), 6);
    compare(BarLayout.dividerGap("none", 2, 20, 2), 4);
  }

  function test_layoutSections_fits() {
    // 1000 long, margin 10, gap 5: ends hug the margins, center centered
    const s = BarLayout.layoutSections([100, 200, 100], [100, 200, 100], 1000, 10, 5, false);
    compare(s[0].offset, 10);
    compare(s[0].extent, 100);
    compare(s[1].offset, 400);
    compare(s[1].extent, 200);
    compare(s[2].offset, 890);
    compare(s[2].extent, 100);
  }

  function test_layoutSections_center_slides() {
    // A long left side pushes the center right (not locked)
    const s = BarLayout.layoutSections([500, 200, 0], [500, 200, 0], 1000, 0, 10, false);
    compare(s[1].offset, 510);
  }

  function test_layoutSections_lockCenter() {
    // Locked, the center stays dead center and the left squeezes instead
    const s = BarLayout.layoutSections([500, 200, 0], [100, 200, 0], 1000, 0, 10, true);
    compare(s[1].offset, 400);
    compare(s[0].extent, 390);
  }

  function test_layoutSections_spacers_reach_the_center() {
    // A left side with a spacer stretches to a gap short of the center;
    // the right one without keeps its own length
    const s = BarLayout.layoutSections([100, 200, 100], [100, 200, 100], 1000, 10, 5, true, undefined, [1, 0, 0]);
    compare(s[0].offset, 10);
    compare(s[0].extent, 385);
    compare(s[1].offset, 400);
    compare(s[2].offset, 890);
    compare(s[2].extent, 100);
    // Both sides: each reaches the center
    const both = BarLayout.layoutSections([100, 200, 100], [100, 200, 100], 1000, 10, 5, true, undefined, [1, 0, 2]);
    compare(both[0].extent, 385);
    compare(both[2].offset, 605);
    compare(both[2].extent, 385);
  }

  // Unlocked, with spacers: nothing is centered; every spacer on the bar
  // takes an equal share of its free room, the sections packed end to end
  function test_layoutSections_unlocked_spacers_share_the_bar() {
    // 1000 - 2 × 10 margin - 400 - 2 × 5 gap = 570 free: 190 each
    const s = BarLayout.layoutSections([100, 200, 100], [100, 200, 100], 1000, 10, 5, false, undefined, [1, 1, 1]);
    compare(s[0].extent, 290);
    compare(s[1].offset, 305);
    compare(s[1].extent, 390);
    compare(s[2].offset, 700);
    compare(s[2].offset + s[2].extent, 990);
    // No spacers: the center is centered as ever
    compare(BarLayout.layoutSections([100, 200, 100], [100, 200, 100], 1000, 10, 5, false, undefined, [0, 0, 0])[1].offset, 400);
  }

  function test_layoutSections_spacers_never_move_the_center() {
    // Laid out at their minimum gaps first: the locked center stays put,
    // the side only reaching it
    const s = BarLayout.layoutSections([300, 200, 0], [300, 200, 0], 1000, 0, 10, true, undefined, [1, 0, 0]);
    compare(s[1].offset, 400);
    compare(s[0].extent, 390);
    // Unlocked, nothing is centered: the left spacer takes the room and
    // the center packs against the end
    const t = BarLayout.layoutSections([500, 200, 0], [500, 200, 0], 1000, 0, 10, false, undefined, [1, 0, 0]);
    compare(t[1].offset, 800);
    compare(t[0].extent, 790);
  }

  function test_layoutSections_spacers_share_with_no_center() {
    // 1000 - 2 × 10 margin - 100 - 100 - a 5 gap = 775 free: one spacer
    // left and three right share it 1:3
    const s = BarLayout.layoutSections([100, 0, 100], [100, 0, 100], 1000, 10, 5, false, undefined, [1, 0, 3]);
    compare(s[0].extent, 100 + 775 / 4);
    compare(s[2].offset, 10 + 100 + 775 / 4 + 5);
    compare(s[2].offset + s[2].extent, 990);
    // A spacer on one side only: that side takes it all
    const one = BarLayout.layoutSections([100, 0, 100], [100, 0, 100], 1000, 10, 5, false, undefined, [0, 0, 1]);
    compare(one[0].extent, 100);
    compare(one[2].offset, 115);
    compare(one[2].extent, 875);
  }

  function test_sectionRooms() {
    // Unlocked: what the others and the gaps leave, 1000 less 10 each end
    compare(BarLayout.sectionRooms([100, 200, 100], 1000, 10, 5, false), [980 - 300 - 10, 980 - 200 - 10, 980 - 300 - 10]);
    // An empty side takes no gap from the others
    compare(BarLayout.sectionRooms([100, 200, 0], 1000, 10, 5, false), [980 - 200 - 5, 980 - 100 - 5, 980 - 300 - 10]);
    // Locked: a side gets its half beside the centered center
    compare(BarLayout.sectionRooms([100, 200, 100], 1000, 10, 5, true), [400 - 10 - 5, 980, 1000 - 10 - 600 - 5]);
  }

  function test_edgeHang() {
    // Dividers at each end, with the spacing on their inner side
    compare(BarLayout.edgeHang([10, 50, 8, 12], [true, false, true, true], 4), {
      "lead": 14,
      "trail": 28
    });
    // Zero sizes are passed over; none at the ends
    compare(BarLayout.edgeHang([0, 50, 10, 50], [true, false, true, false], 4), {
      "lead": 0,
      "trail": 0
    });
    // Nothing but dividers: they're the content
    compare(BarLayout.edgeHang([10, 10], [true, true], 4), {
      "lead": 0,
      "trail": 0
    });
  }

  function test_layoutSections_center_hang() {
    // A 20 px divider (and 10 spacing) trailing the center: its 170 px of
    // content stays centered, the divider sitting in the gap after it
    const hang = {
      "lead": 0,
      "trail": 30
    };
    const s = BarLayout.layoutSections([0, 200, 100], [0, 200, 100], 1000, 0, 10, false, hang);
    compare(s[1].offset, 415);
    compare(s[2].offset, 900);
    // Locked: centered too, the right half losing the divider's room
    const locked = BarLayout.layoutSections([0, 200, 600], [0, 200, 0], 1000, 0, 10, true, hang);
    compare(locked[1].offset, 415);
    compare(locked[2].extent, 375);
  }

  function test_layoutSections_squeeze_and_scale() {
    // 300 of room: 400 preferred squeezed halfway to the 200 minimum
    const squeezed = BarLayout.layoutSections([200, 0, 200], [100, 0, 100], 300, 0, 0, false);
    compare(squeezed[0].extent, 150);
    compare(squeezed[2].extent, 150);
    // 100 of room: even the minimums don't fit, so they're scaled down
    const scaled = BarLayout.layoutSections([200, 0, 200], [100, 0, 100], 100, 0, 0, false);
    compare(scaled[0].extent, 50);
  }

  function test_overflowHidden_nothing_when_it_fits() {
    const hidden = BarLayout.overflowHidden([[m(100)], [m(100)], [m(100)]], 1000, 0, 10, 4, false);
    compare(hidden, [[], [], []]);
  }

  function test_overflowHidden_drops_lowest_priority() {
    // 250 of room for 300: the priority-0 widget goes, wherever it is
    const hidden = BarLayout.overflowHidden([[m(100, 100, 5)], [m(100, 100, 0)], [m(100, 100, 5)]], 250, 0, 0, 0, false);
    compare(hidden, [[], [0], []]);
  }

  function test_overflowHidden_ties_go_right_left_center() {
    // Equal priorities: the right section first, its last widget first
    const hidden = BarLayout.overflowHidden([[m(100)], [m(100)], [m(50), m(50)]], 250, 0, 0, 0, false);
    compare(hidden, [[], [], [1]]);
    // ...then the left, the center last
    const more = BarLayout.overflowHidden([[m(100)], [m(100)], [m(100)]], 150, 0, 0, 0, false);
    compare(more, [[0], [], [0]]);
  }

  function test_overflowHidden_restores_what_fits() {
    // Dropping the big priority-1 widget leaves room to bring back the
    // priority-0 one dropped before it
    const hidden = BarLayout.overflowHidden([[m(100, 100, 0), m(300, 300, 1)], [], [m(100, 100, 2)]], 350, 0, 0, 0, false);
    compare(hidden, [[1], [], []]);
  }

  function test_overflowHidden_never_drops_spacers() {
    // A spacer's minimum gap counts, but a widget goes instead of it
    const hidden = BarLayout.overflowHidden([[m(100), spacer(50), m(100, 100, 1)], [], []], 220, 0, 0, 10, false);
    compare(hidden, [[0], [], []]);
    // Collapsed spacers take no room: 100 + a gap + 100 fits 210
    compare(BarLayout.overflowHidden([[m(100), spacer(), m(100)], [], []], 210, 0, 0, 10, false), [[], [], []]);
  }

  function test_overflowHidden_lockCenter_only_the_overflowing_half() {
    // Center 200 in 1000 leaves 400 each side; only the left overflows
    const hidden = BarLayout.overflowHidden([[m(300), m(300)], [m(200)], [m(300)]], 1000, 0, 0, 0, true);
    compare(hidden, [[1], [], []]);
  }

  function test_overflowHidden_lockCenter_center_alone_overflows() {
    // The center can't fit the bar even alone: it loses its own widgets,
    // and the sides keep theirs
    const hidden = BarLayout.overflowHidden([[m(50)], [m(300), m(300), m(300)], [m(50)]], 800, 0, 0, 0, true);
    compare(hidden, [[], [2], []]);
    // A center that fits alone is never touched for a crowded side
    const side = BarLayout.overflowHidden([[m(500)], [m(600)], []], 800, 0, 0, 0, true);
    compare(side, [[0], [], []]);
  }

  function test_overflowHidden_lockCenter_center_hang() {
    // A 30 px divider trailing the 200 px center: centered on its 170 px of
    // content it starts at 415, leaving 415 on the left and 385 on the right
    const divider = Object.assign(m(30), {
      "divides": true
    });
    const hidden = BarLayout.overflowHidden([[m(410)], [m(170), divider], [m(390)]], 1000, 0, 0, 0, true);
    compare(hidden, [[], [], [0]]);
  }

  function test_allocate_fits() {
    const a = BarLayout.allocate([m(40), m(60)], [true, true], 200, 4);
    compare(a.sizes, [40, 60]);
    compare(a.offsets, [0, 44]);
    compare(a.visible, [true, true]);
  }

  function test_allocate_squeezes_elastic() {
    // 100 preferred + spacing 0 in 80: the elastic one gives 20 of its 50
    const a = BarLayout.allocate([m(50), m(50, 0)], [true, true], 80, 0);
    compare(a.sizes, [50, 30]);
  }

  function test_allocate_hides_lowest_priority() {
    const a = BarLayout.allocate([m(50, 50, 1), m(50, 50, 0)], [true, true], 60, 0);
    compare(a.visible, [true, false]);
    compare(a.sizes, [50, 0]);
  }

  function test_allocate_respects_shown() {
    const a = BarLayout.allocate([m(40), m(60), m(20)], [true, false, true], 200, 4);
    compare(a.sizes, [40, 0, 20]);
    compare(a.offsets, [0, 44, 44]);
  }

  function test_allocate_spacers_take_the_room() {
    // 200 for 40 + 60 and one gap: the spacer between takes the other 96,
    // in the gap after the first widget
    const a = BarLayout.allocate([m(40), spacer(), m(60)], [true, true, true], 200, 4);
    compare(a.sizes, [40, 96, 60]);
    compare(a.offsets, [0, 44, 140]);
    // Two share it, the remainder to the last
    const two = BarLayout.allocate([spacer(), m(40), spacer(), m(60)], [true, true, true, true], 200, 4);
    compare(two.sizes, [48, 40, 48, 60]);
    compare(two.offsets, [0, 48, 92, 140]);
    const odd = BarLayout.allocate([spacer(), m(40), spacer()], [true, true, true], 101, 4);
    compare(odd.sizes, [30, 40, 31]);
    compare(odd.offsets, [0, 30, 70]);
  }

  function test_allocate_collapsed_spacer_leaves_one_gap() {
    // Crowded: the spacer keeps its minimum gap (0), one gap between
    const a = BarLayout.allocate([m(40, 20), spacer(), m(60)], [true, true, true], 90, 4);
    compare(a.visible, [true, true, true]);
    compare(a.sizes[1], 0);
    compare(a.offsets[2], a.sizes[0] + 4);
    // A spacer is never the one hidden
    const b = BarLayout.allocate([m(40), spacer(10), m(60, 60, 1)], [true, true, true], 80, 4);
    compare(b.visible, [false, true, true]);
  }

  function test_runs() {
    compare(BarLayout.runs([]), []);
    compare(BarLayout.runs([false, false]), []);
    compare(BarLayout.runs([true, true, false, true]), [
      {
        "start": 0,
        "count": 2,
        "members": [0, 1]
      },
      {
        "start": 3,
        "count": 1,
        "members": [3]
      }
    ]);
  }

  // A widget showing nothing (null) leaves a run whole; one shown without
  // a background (false) still ends it
  function test_runs_pass_over_widgets_showing_nothing() {
    compare(BarLayout.runs([null, true, null, true, false, true, null]), [
      {
        "start": 1,
        "count": 2,
        "members": [1, 3]
      },
      {
        "start": 5,
        "count": 1,
        "members": [5]
      }
    ]);
    compare(BarLayout.runs([null, null]), []);
  }

  function test_runPlaces() {
    const places = BarLayout.runPlaces([true, false, true, true]);
    compare(places[1], null);
    compare(places[0], {
      "run": 0,
      "index": 0,
      "count": 1
    });
    compare(places[3], {
      "run": 1,
      "index": 1,
      "count": 2
    });
  }

  function test_runPlaces_skip_widgets_showing_nothing() {
    const places = BarLayout.runPlaces([true, null, true]);
    compare(places[1], null);
    compare(places[2], {
      "run": 0,
      "index": 1,
      "count": 2
    });
  }

  // A section end joining the next section's run: the run reaching it
  // counts one more member there, so its widget takes a middle place
  function test_runPlaces_joined_ends() {
    const places = BarLayout.runPlaces([null, true, true, false, true, null], true, true);
    compare(places[1], {
      "run": 0,
      "index": 1,
      "count": 3
    });
    compare(places[2].index, 2);
    compare(places[4], {
      "run": 1,
      "index": 0,
      "count": 2
    });
    // A run not reaching the joined end (a widget with no background
    // faces it) stays as it is
    const loose = BarLayout.runPlaces([false, true, true, false], true, true);
    compare(loose[1], {
      "run": 0,
      "index": 0,
      "count": 2
    });
  }

  function divider() {
    return {
      "pref": 4,
      "min": 4,
      "priority": 0,
      "divides": true
    };
  }

  // Joined where a side's spacer pushed a widget against the next section
  function test_sectionJoins() {
    // left [m m spacer m], center [m spacer m], right [m spacer m m]
    const example = [[m(40), m(40), spacer(), m(40)], [m(40), spacer(4), m(40)], [m(40), spacer(), m(40), m(40)]];
    compare(BarLayout.sectionJoins(example), {
      "leftCenter": true,
      "centerRight": true,
      "leftRight": false
    });
    // A spacer at the side's end facing the center: its widgets are away
    const away = [[m(40), spacer()], [m(40)], [spacer(), m(40)]];
    compare(BarLayout.sectionJoins(away), {
      "leftCenter": false,
      "centerRight": false,
      "leftRight": false
    });
    // No spacer: never joined, however close the side is crowded
    const crowded = [[m(400)], [m(200)], [m(400)]];
    compare(BarLayout.sectionJoins(crowded).leftCenter, false);
    // A Separator facing the boundary keeps it split
    const divided = [[spacer(), m(40), divider()], [m(40)], []];
    compare(BarLayout.sectionJoins(divided).leftCenter, false);
    // A widget showing nothing is passed over: the one before it faces
    compare(BarLayout.sectionJoins([[spacer(), m(40), m(0)], [m(40)], []]).leftCenter, true);
    compare(BarLayout.sectionJoins([[m(40), spacer(), m(0)], [m(40)], []]).leftCenter, false);
    // No center: the sides join where either has a spacer
    compare(BarLayout.sectionJoins([[m(40)], [], [spacer(), m(40)]]).leftRight, false);
    compare(BarLayout.sectionJoins([[m(40)], [], [m(40), spacer()]]).leftRight, true);
    compare(BarLayout.sectionJoins([[m(40)], [], [m(40)]]).leftRight, false);
  }

  // A joined boundary keeps its own gap; the locked center never moves
  function test_layoutSections_joined_gaps() {
    const gaps = BarLayout.boundaryGaps({
      "leftCenter": true,
      "centerRight": false,
      "leftRight": false
    }, 10, 0);
    compare(gaps, {
      "lc": 0,
      "cr": 10,
      "lr": 10
    });
    const s = BarLayout.layoutSections([300, 200, 100], [300, 200, 100], 1000, 0, gaps, true, undefined, [1, 0, 1]);
    compare(s[1].offset, 400);
    compare(s[0].extent, 400);
    compare(s[2].offset, 610);
    compare(BarLayout.sectionRooms([300, 200, 100], 1000, 0, gaps, true), [400, 1000, 390]);
    // A number is every boundary's gap, as before
    compare(BarLayout.layoutSections([300, 200, 100], [300, 200, 100], 1000, 0, 10, true, undefined, [1, 0, 1])[0].extent, 390);
  }

  // Which center group stays centered: between the outer spacers, else
  // the group with more widgets (the first on a tie)
  function test_centerSplit() {
    compare(BarLayout.centerSplit([m(10), m(10)]), {
      "start": 0,
      "end": 1,
      "leadFills": 0,
      "tailFills": 0
    });
    compare(BarLayout.centerSplit([m(10), m(10), m(10), spacer(), m(10)]), {
      "start": 0,
      "end": 2,
      "leadFills": 0,
      "tailFills": 1
    });
    compare(BarLayout.centerSplit([m(10), spacer(), m(10), m(10)]), {
      "start": 2,
      "end": 3,
      "leadFills": 1,
      "tailFills": 0
    });
    compare(BarLayout.centerSplit([m(10), spacer(), m(10)]).tailFills, 1);
    compare(BarLayout.centerSplit([m(10), spacer(), m(10), spacer(), m(10)]), {
      "start": 2,
      "end": 2,
      "leadFills": 1,
      "tailFills": 1
    });
  }

  function test_centerParts() {
    // [40 40 spacer(4) 40], spacing 5: the pair pinned, then the 5 gap and
    // the spacer's 4 before the last
    const measures = [m(40), m(40), spacer(4), m(40)];
    compare(BarLayout.centerParts(measures, [true, true, true, true], 5, "pref"), {
      "lead": 0,
      "core": 85,
      "tail": 49,
      "leadFills": 0,
      "tailFills": 1
    });
    // Its spacers' weights: the share after the pinned group to the spacer
    // after it
    compare(BarLayout.centerFillWeights(measures, 0, 300), [0, 0, 300, 0]);
  }

  // A center spacer pushes the center's outer group to the side; the
  // pinned group stays dead center
  function test_layoutSections_center_spacers() {
    const parts = {
      "lead": 0,
      "core": 120,
      "tail": 40,
      "leadFills": 0,
      "tailFills": 1
    };
    const s = BarLayout.layoutSections([100, 160, 100], [100, 160, 100], 1000, 0, 10, true, undefined, [0, 0, 0], parts);
    compare(s[0].extent, 100);
    compare(s[1].offset, 440);
    compare(s[1].tailShare, 290);
    compare(s[1].extent, 450);
    compare(s[2].offset, 900);
    // Unlocked: the center's spacer shares the bar's room with any others
    const u = BarLayout.layoutSections([100, 160, 100], [100, 160, 100], 1000, 0, 10, false, undefined, [0, 1, 0], parts);
    compare(u[1].offset, 110);
    compare(u[1].extent, 780);
    compare(u[1].leadShare, undefined);
    compare(u[2].offset, 900);
  }

  // A side's spacer and the center's beside it share the half equally
  function test_layoutSections_center_and_side_spacers_share() {
    const parts = {
      "lead": 0,
      "core": 100,
      "tail": 0,
      "leadFills": 1,
      "tailFills": 0
    };
    const s = BarLayout.layoutSections([100, 100, 0], [100, 100, 0], 1000, 0, 10, true, undefined, [1, 0, 0], parts);
    compare(s[0].extent, 270);
    compare(s[1].offset, 280);
    compare(s[1].leadShare, 170);
    compare(s[1].offset + s[1].leadShare, 450);
  }

  function test_allocate_weights() {
    const a = BarLayout.allocate([m(10), spacer(), m(10), spacer(), m(10)], [true, true, true, true, true], 130, 0, [0, 30, 0, 70, 0]);
    compare(a.sizes, [10, 30, 10, 70, 10]);
    // No weight: no room
    compare(BarLayout.allocate([m(10), spacer(), m(10)], [true, true, true], 100, 0, [0, 0, 0]).sizes, [10, 0, 10]);
  }

  // A center spacer pushing its outer group out joins it to the side
  function test_sectionJoins_center_spacers() {
    const joins = BarLayout.sectionJoins([[m(40)], [m(40), spacer(), m(40), spacer(), m(40)], [m(40)]]);
    compare(joins.leftCenter, true);
    compare(joins.centerRight, true);
    // The pinned group isn't pushed: no join on its side
    compare(BarLayout.sectionJoins([[m(40)], [m(40), m(40), spacer(), m(40)], [m(40)]]).leftCenter, false);
    // Unlocked, a spacer anywhere packs the sections: every boundary joins
    compare(BarLayout.sectionJoins([[m(40)], [m(40), m(40), spacer(), m(40)], [m(40)]], false).leftCenter, true);
    compare(BarLayout.sectionJoins([[m(40)], [m(40)], [m(40)]], false).leftCenter, false);
  }

  // A joined boundary's gap counts towards what fits
  function test_overflowHidden_joined_gap() {
    // 495 + 500 + a 10 gap overflows 1000; joined (gap 0) it fits
    const measures = [[m(495, 495, 0), spacer(0)], [], [m(500, 500, 1)]];
    compare(BarLayout.overflowHidden(measures, 1000, 0, 10, 0, false), [[0], [], []]);
    const joined = [[spacer(0), m(495, 495, 0)], [], [m(500, 500, 1)]];
    compare(BarLayout.overflowHidden(joined, 1000, 0, 10, 0, false, 0), [[], [], []]);
  }

  function test_joinGroups() {
    compare(BarLayout.joinGroups([], 4), []);
    // Out of order; 100..150 and 154..200 are 4 apart (joined), 260 is
    // 60 past: its own
    compare(BarLayout.joinGroups([
      {
        "start": 260,
        "end": 300
      },
      {
        "start": 100,
        "end": 150
      },
      {
        "start": 154,
        "end": 200
      }
    ], 4), [
      {
        "start": 100,
        "end": 200,
        "members": [1, 2]
      },
      {
        "start": 260,
        "end": 300,
        "members": [0]
      }
    ]);
    // 5 apart is past a joinGap of 4
    compare(BarLayout.joinGroups([
      {
        "start": 0,
        "end": 10
      },
      {
        "start": 15,
        "end": 20
      }
    ], 4).length, 2);
  }

  function test_pillRects_free_and_joined_ends() {
    const groups = [
      {
        "start": 5,
        "end": 100
      },
      {
        "start": 400,
        "end": 500
      },
      {
        "start": 900,
        "end": 995
      }
    ];
    // Grown by 5; the end ones reach within 1.5 of the ends and join them
    compare(BarLayout.pillRects(groups, 5, 20, 1.5, 1000, [true, true]).map(r => [r.start, r.length, r.joinStart, r.joinEnd]), [[0, 105, true, false], [395, 110, false, false], [895, 105, false, true]]);
    // An end held clear of another bar (not joinable): a free end there
    compare(BarLayout.pillRects(groups, 5, 20, 1.5, 1000, [false, true]).map(r => [r.start, r.length, r.joinStart, r.joinEnd]), [[0, 105, false, false], [395, 110, false, false], [895, 105, false, true]]);
    // Pills less than `apart` apart (no room for their fillets) are one
    const close = BarLayout.pillRects([
      {
        "start": 100,
        "end": 200
      },
      {
        "start": 215,
        "end": 300
      }
    ], 5, 10, 1.5, 1000, [true, true]);
    compare(close.map(r => [r.start, r.length]), [[95, 210]]);
    compare(BarLayout.pillRects([
      {
        "start": 100,
        "end": 200
      },
      {
        "start": 225,
        "end": 300
      }
    ], 5, 10, 1.5, 1000, [true, true]).length, 2);
  }

  function test_islandRects_whole_bar() {
    compare(BarLayout.islandRects([], 6, 10, 990, true), [
      {
        "start": 10,
        "length": 980,
        "joinStart": false,
        "joinEnd": false
      }
    ]);
  }

  function test_islandRects_grow_clamp_and_merge() {
    // Grown by 6 each side; kept inside 10..990; 8..50 and 60..75 then
    // overlap, so they're one island
    const rects = BarLayout.islandRects([
      {
        "start": 115,
        "end": 160
      },
      {
        "start": 8,
        "end": 50
      },
      {
        "start": 900,
        "end": 988
      },
      {
        "start": 60,
        "end": 75
      }
    ], 6, 10, 990, false);
    compare(rects.map(r => [r.start, r.start + r.length]), [[10, 81], [109, 166], [894, 990]]);
    // 81 to 109 is 28 apart: they stay apart (joining is joinGroups')
    verify(rects.every(r => !r.joinStart && !r.joinEnd));
  }

  function test_stretchIslands_stretched_back_over_others_joins_the_edge() {
    const rects = [
      {
        "start": 10,
        "length": 100
      },
      {
        "start": 400,
        "length": 100
      },
      {
        "start": 800,
        "length": 100
      }
    ];
    // The middle pill stretched over both others to the bar's ends, joining
    // the edges there: one pill, joined at both ends
    const shapes = BarLayout.stretchIslands(rects, [
      {
        "index": 1,
        "start": 0,
        "end": 1000,
        "joinStart": true,
        "joinEnd": true
      }
    ], 10);
    compare(shapes.map(r => [r.start, r.length, r.joinStart, r.joinEnd, r.squareStart, r.squareEnd]), [[0, 1000, true, true, false, false]]);
  }

  function test_stretchIslands_grows_squares_and_merges() {
    const rects = BarLayout.islandRects([
      {
        "start": 100,
        "end": 200
      },
      {
        "start": 300,
        "end": 400
      }
    ], 0, 0, 1000, false);
    compare(BarLayout.stretchIslands(rects, [], 10).map(r => [r.start, r.length]), [[100, 100], [300, 100]]);
    // Stretched to 80..250: still 50 short of the next
    const apart = BarLayout.stretchIslands(rects, [
      {
        "index": 0,
        "start": 80,
        "end": 250,
        "squareStart": true
      }
    ], 10);
    compare(apart.map(r => [r.start, r.length, r.squareStart, r.squareEnd]), [[80, 170, true, false], [300, 100, false, false]]);
    // Stretched to 295: within 10 of the next, so they draw as one
    const joined = BarLayout.stretchIslands(rects, [
      {
        "index": 0,
        "start": 100,
        "end": 295,
        "squareEnd": true
      }
    ], 10);
    compare(joined.map(r => [r.start, r.length, r.squareStart, r.squareEnd]), [[100, 300, false, false]]);
  }

  function test_stretchOf_combines_owners() {
    compare(BarLayout.stretchOf([], 0), null);
    compare(BarLayout.stretchOf([null], 0), null);
    // A popout flush into the start and a menu reaching past the end
    const both = BarLayout.stretchOf([
      {
        "index": 0,
        "start": 90,
        "end": 200,
        "squareStart": true,
        "squareEnd": false
      },
      {
        "index": 1,
        "start": 0,
        "end": 999
      },
      {
        "index": 0,
        "start": 120,
        "end": 260,
        "squareStart": false,
        "squareEnd": true
      }
    ], 0);
    compare([both.start, both.end, both.squareStart, both.squareEnd], [90, 260, true, true]);
  }
  function test_endReaches_nothing_asked() {
    const rects = [
      {
        "start": 0,
        "length": 50,
        "joinStart": true,
        "joinEnd": false
      }
    ];
    const r = BarLayout.endReaches(rects, [], 1000, 12, 20);
    compare(r.rects, rects);
    compare(r.stretches, []);
    verify(!r.straightStart && !r.straightEnd);
  }

  function test_endReaches_stretches_the_end_pill() {
    const rects = [
      {
        "start": 0,
        "length": 50,
        "joinStart": true,
        "joinEnd": false
      },
      {
        "start": 900,
        "length": 100,
        "joinStart": false,
        "joinEnd": true
      }
    ];
    const r = BarLayout.endReaches(rects, [
      {
        "atStart": true,
        "to": 80,
        "straight": true
      },
      {
        "atStart": false,
        "to": 950
      }
    ], 1000, 12, 20);
    compare(r.rects.length, 2, "no stub where an end pill joins");
    compare(r.stretches[0].index, 0);
    compare(r.stretches[0].start, 0);
    compare(r.stretches[0].end, 80, "on to where it's asked");
    verify(r.stretches[0].joinStart);
    compare(r.stretches[1].index, 1);
    compare(r.stretches[1].start, 900, "already past it");
    compare(r.stretches[1].end, 1000);
    verify(r.stretches[1].joinEnd);
    verify(r.straightStart && !r.straightEnd);
  }

  function test_endReaches_pulls_a_near_pill_back() {
    const rects = [
      {
        "start": 90,
        "length": 50,
        "joinStart": false,
        "joinEnd": false
      }
    ];
    const r = BarLayout.endReaches(rects, [
      {
        "atStart": true,
        "to": 80
      }
    ], 1000, 12, 20);
    compare(r.rects.length, 1, "within merge of the reach: no stub");
    compare(r.stretches[0].start, 0);
    compare(r.stretches[0].end, 140, "keeping its own end");
    verify(r.stretches[0].joinStart);
  }

  function test_endReaches_adds_stubs() {
    const rects = [
      {
        "start": 400,
        "length": 200,
        "joinStart": false,
        "joinEnd": false
      }
    ];
    const r = BarLayout.endReaches(rects, [
      {
        "atStart": true,
        "to": 80
      },
      {
        "atStart": false,
        "to": 900
      },
      {
        "atStart": false,
        "to": 850
      }
    ], 1000, 12, 20);
    compare(r.rects.length, 3);
    compare(r.rects[0].start, 0);
    compare(r.rects[0].length, 20);
    verify(r.rects[0].joinStart);
    compare(r.rects[1].start, 400, "the pill between keeps its place");
    compare(r.rects[2].start, 980);
    verify(r.rects[2].joinEnd);
    compare(r.stretches[0].end, 80);
    compare(r.stretches[1].index, 2);
    compare(r.stretches[1].start, 850, "as far as the furthest asks");
    compare(r.stretches[1].end, 1000);
    // Drawn: stretched, joined, and the pill between left alone
    const drawn = BarLayout.stretchIslands(r.rects, r.stretches, 12);
    compare(drawn.length, 3);
    compare(drawn[0].length, 80);
    verify(drawn[0].joinStart);
    compare(drawn[2].start, 850);
    verify(drawn[2].joinEnd);
  }

  function test_endReaches_stub_grows_with_the_request() {
    // A request following a surface still sliding out reaches less than
    // a stub: the stub is no longer than it, growing from the corner
    const rects = [
      {
        "start": 400,
        "length": 200,
        "joinStart": false,
        "joinEnd": false
      }
    ];
    const r = BarLayout.endReaches(rects, [
      {
        "atStart": true,
        "to": 6
      },
      {
        "atStart": false,
        "to": 990
      }
    ], 1000, 12, 20);
    compare(r.rects.length, 3);
    compare(r.rects[0].length, 6);
    compare(r.rects[2].start, 990);
    compare(r.rects[2].length, 10);
    // Reaching nowhere past the end, it asks nothing
    const none = BarLayout.endReaches(rects, [
      {
        "atStart": true,
        "to": 0
      },
      {
        "atStart": false,
        "to": 1000
      }
    ], 1000, 12, 20);
    compare(none.rects.length, 1);
    compare(none.stretches.length, 0);
  }

  function test_shownStretches() {
    const rects = [
      {
        "start": 0,
        "length": 100
      },
      {
        "start": 400,
        "length": 200
      }
    ];
    // Nothing past a pill's ends and nothing squared: nothing shown
    compare(BarLayout.shownStretches(rects, [
      {
        "index": 1,
        "start": 420,
        "end": 580
      }
    ], 1000).length, 0);
    const shown = BarLayout.shownStretches(rects, [
      {
        "index": 1,
        "start": 380,
        "end": 650,
        "squareEnd": true
      },
      {
        "index": 0,
        "start": 0,
        "end": 140,
        "joinStart": true
      }
    ], 1000);
    compare(shown.length, 2);
    compare(shown[0].index, 0);
    verify(shown[0].joinStart, "joined once it reaches the end");
    compare(shown[1].start, 380);
    compare(shown[1].end, 650);
    verify(shown[1].squareEnd);
    // Joining an end it hasn't reached yet: not joined
    verify(!BarLayout.shownStretches(rects, [
      {
        "index": 1,
        "start": 380,
        "end": 980,
        "joinEnd": true
      }
    ], 1000)[0].joinEnd);
  }

  function test_pillIndex() {
    const rects = [
      {
        "start": 0,
        "length": 20
      },
      {
        "start": 100,
        "length": 200
      }
    ];
    // Its pill where it says: its index
    compare(BarLayout.pillIndex(rects, {
      "index": 1,
      "pill": {
        "start": 100,
        "length": 200
      }
    }), 1);
    // No pill carried: its index as given
    compare(BarLayout.pillIndex(rects, {
      "index": 0
    }), 0);
    // A stub came at the start since it was sent: found where it was
    compare(BarLayout.pillIndex(rects, {
      "index": 0,
      "pill": {
        "start": 100,
        "length": 200
      }
    }), 1);
    // ...and a stub went: found again, or -1 where nothing's there
    compare(BarLayout.pillIndex([rects[1]], {
      "index": 1,
      "pill": {
        "start": 100,
        "length": 200
      }
    }), 0);
    compare(BarLayout.pillIndex([rects[1]], {
      "index": 1,
      "pill": {
        "start": 400,
        "length": 50
      }
    }), -1);
    compare(BarLayout.pillIndex([], {
      "index": 0
    }), -1);
  }

  function test_onPills() {
    const rects = [
      {
        "start": 0,
        "length": 20
      },
      {
        "start": 100,
        "length": 200
      }
    ];
    const moved = BarLayout.onPills(rects, [
      {
        "index": 0,
        "start": 80,
        "end": 300,
        "pill": {
          "start": 100,
          "length": 200
        }
      },
      {
        "index": 0,
        "start": 0,
        "end": 400,
        "pill": {
          "start": 500,
          "length": 50
        }
      }
    ]);
    compare(moved.length, 1, "its pill gone: left out");
    compare(moved[0].index, 1);
    compare(moved[0].start, 80);
  }

  function test_flushEnds() {
    const g = {
      "reach": 10,
      "across": 40,
      "inner": 30,
      "near": true
    };
    const shapes = [
      {
        "start": 100,
        "length": 200,
        "squareStart": true,
        "squareEnd": false
      }
    ];
    const st = {
      "index": 0,
      "start": 100,
      "end": 300,
      "squareStart": true
    };
    // No box: as far as the stretch reaches in, capped by the reach
    const wide = BarLayout.flushEnds([st], shapes, g);
    compare(wide.length, 1);
    compare(wide[0].source, {
      "along": 100,
      "length": 20,
      "from": 30,
      "deep": 10
    });
    compare(wide[0].holes[0], {
      "along": 90,
      "length": 10,
      "from": 30,
      "deep": 20
    }, "beside the wall, from the inner edge out past the far side");
    compare(wide[0].holes[1].along, 100);
    compare(wide[0].holes[1].length, 30, "under the surface, as far as the run-on's shadow spreads");
    // A narrow box: nothing past its far wall
    const narrow = BarLayout.flushEnds([Object.assign({}, st, {
        "box": {
          "start": 100,
          "end": 115
        }
      })], shapes, g);
    compare(narrow[0].source.length, 15);
    compare(narrow[0].holes[1].length, 15);
    // Not while its surface is all behind its edge, nor where it isn't
    // drawn squared there
    compare(BarLayout.flushEnds([Object.assign({}, st, {
        "covered": false
      })], shapes, g).length, 0);
    compare(BarLayout.flushEnds([st], [Object.assign({}, shapes[0], {
        "squareStart": false
      })], g).length, 0);
    // An end, on a bar on the far side (right or bottom): mirrored
    const far = BarLayout.flushEnds([
      {
        "index": 0,
        "start": 100,
        "end": 300,
        "squareEnd": true
      }
    ], [
      {
        "start": 100,
        "length": 200,
        "squareEnd": true
      }
    ], {
      "reach": 10,
      "across": 40,
      "inner": 10,
      "near": false
    });
    compare(far[0].source, {
      "along": 280,
      "length": 20,
      "from": 0,
      "deep": 10
    });
    compare(far[0].holes[0], {
      "along": 300,
      "length": 10,
      "from": -10,
      "deep": 20
    });
    compare(far[0].holes[1].along, 270);
  }

  function test_endReaches_on_a_bar_with_no_pills() {
    const r = BarLayout.endReaches([], [
      {
        "atStart": false,
        "to": 900
      }
    ], 1000, 12, 20);
    compare(r.rects.length, 1);
    compare(r.stretches[0].index, 0);
    compare(r.stretches[0].start, 900);
  }

  function test_endReaches_squares_where_asked() {
    const rects = [
      {
        "start": 900,
        "length": 100,
        "joinStart": false,
        "joinEnd": true
      }
    ];
    const r = BarLayout.endReaches(rects, [
      {
        "atStart": false,
        "to": 700,
        "square": true
      }
    ], 1000, 12, 20);
    verify(r.stretches[0].squareStart, "a wall runs straight into it");
    const past = BarLayout.endReaches(rects, [
      {
        "atStart": false,
        "to": 950,
        "square": true
      }
    ], 1000, 12, 20);
    verify(!past.stretches[0].squareStart, "not where the pill already reaches past it");
  }

  function test_dropOrder() {
    // Lowest priority first; ties right, left, center, the last listed
    // first; a spacer (null) never goes
    compare(BarLayout.dropOrder([[0, 0], [5, null], [0, -1]]), [[4, 3], [5, 0], [2, 1]]);
    compare(BarLayout.dropOrder([[1], [1], [1]], [0, 1, 2]), [[1], [2], [3]]);
  }
}
