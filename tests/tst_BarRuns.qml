import QtQuick
import QtTest
import qs.components.methods

// Where a bar section's backgrounds and marks go, and the room its widgets
// keep (BarRuns)
TestCase {
  name: "BarRuns"

  // A bar's context: its look's shape, grouping and opaque trait, its
  // sizes, the loose gap of a powerline
  function ctx(name, grouping, opaque) {
    return BarRuns.context({
      "thickness": 30,
      "fontSize": 14,
      "widgetGap": 6,
      "look": {
        "shape": {
          "name": name,
          "ends": "shaped",
          "radius": 8,
          "outline": null
        },
        "grouping": grouping,
        "traits": {
          "opaque": opaque ?? false
        }
      }
    });
  }

  function test_context() {
    const c = ctx("slant", "powerline", true);
    compare([c.grouping, c.opaque, c.across, c.content, c.looseGap], ["powerline", true, 30, 14, 6]);
    compare(ctx("slant", "merged").looseGap, 0, "no loose gap off a powerline");
  }

  function test_segment_at_is_the_shapes() {
    const c = ctx("arrow", "powerline");
    const place = {
      "index": 1,
      "count": 3
    };
    compare(BarRuns.segmentAt(c, place), BarShapes.segment(c.shape, "powerline", false, 1, 3, 30, 14));
    compare(BarRuns.segmentAt(c, null), BarShapes.segment(c.shape, "powerline", false, 0, 1, 30, 14), "alone");
  }

  function test_flags_key_round_trips() {
    const flags = [true, false, null, true];
    compare(BarRuns.flagsKey(flags), "10-1");
    compare(BarRuns.flagsOf("10-1"), flags);
    compare(BarRuns.flagsOf(""), []);
  }

  // A run's last widget carries on past it only where the run goes on into
  // the next section (a middle place) and that end joins
  function test_reach_on() {
    compare(BarRuns.reachOn({
      "index": 1,
      "count": 3
    }, true, 12), 12);
    compare(BarRuns.reachOn({
      "index": 2,
      "count": 3
    }, true, 12), 0, "its last place: the run ends");
    compare(BarRuns.reachOn({
      "index": 1,
      "count": 3
    }, false, 12), 0, "not joined");
    compare(BarRuns.reachOn(null, true, 12), 0, "no place");
  }

  function test_run_background() {
    const c = ctx("slant", "merged");
    // Widgets 0..2 in one run, carried on from the section before and into
    // the next (places 1..3 of 5)
    const run = {
      "start": 0,
      "count": 3,
      "members": [0, 1, 2]
    };
    const places = [1, 2, 3].map(i => ({
          "index": i,
          "count": 5
        }));
    const b = BarRuns.runBackground(c, run, places, [0, 40, 90], [36, 46, 30], true, 8);
    compare([b.first, b.last, b.startCap, b.endCap, b.openStart, b.openEnd, b.reach, b.from, b.to], [0, 2, "flat", "flat", true, true, 8, 0, 128]);
    // A run alone in its section: its own caps, closed, no reach
    const alone = [0, 1, 2].map(i => ({
          "index": i,
          "count": 3
        }));
    const a = BarRuns.runBackground(c, run, alone, [0, 40, 90], [36, 46, 30], true, 8);
    compare([a.startCap, a.endCap, a.openStart, a.openEnd, a.reach, a.to], ["slant", "slant", false, false, 0, 120]);
  }

  // A mark in each gap between shown widgets, and after the last where the
  // section joins the next; never beside a divider, never after a spacer
  function test_marks() {
    const m = BarRuns.marks([20, 0, 30, 10, 40], [false, false, false, true, false], [false, false, false, false, false], false);
    compare(m.map(s => s.shown), [true, false, false, false, false]);
    compare(m.map(s => s.next), [2, 2, 3, 4, -1]);
    const joined = BarRuns.marks([20, 30], [false, false], [false, false], true);
    compare(joined.map(s => [s.shown, s.joined]), [[true, false], [true, true]]);
    // A spacer last: the mark goes after the widget before it, not the spacer
    const spaced = BarRuns.marks([20, 50], [false, false], [false, true], true);
    compare(spaced.map(s => [s.shown, s.joined]), [[true, false], [false, false]]);
    compare(BarRuns.marks([], [], [], true), []);
  }

  function test_insets() {
    const c = ctx("slant", "powerline");
    const section = {
      "first": 0,
      "last": 2,
      "joinStart": false,
      "joinEnd": false
    };
    const place = {
      "index": 0,
      "count": 2
    };
    const s = BarShapes.segment(c.shape, "powerline", false, 0, 2, 30, 14);
    compare(BarRuns.insets(c, place, {
      "background": true,
      "segments": false,
      "fills": false
    }, 0, section), {
      "lead": s.lead,
      "trail": s.trail
    }, "a background: its caps' room");
    compare(BarRuns.insets(c, place, {
      "background": true,
      "segments": true,
      "fills": false
    }, 0, section), {
      "lead": 0,
      "trail": 0
    }, "its parts as segments keep their own");
    // A widget whose icon is drawn larger (Battery's 1.1) keeps its caps'
    // room at the icon's height: a capsule's curve is further in there
    const capsule = ctx("capsule", "separate");
    const tall = {
      "background": true,
      "segments": false,
      "fills": false,
      "contentScale": 1.1
    };
    compare(BarRuns.insets(capsule, null, tall, 0, section), {
      "lead": 3,
      "trail": 3
    }, "a larger icon: its caps' room at its height");
    compare(BarRuns.insets(capsule, null, Object.assign({}, tall, {
      "contentScale": 1
    }), 0, section), {
      "lead": 2,
      "trail": 2
    }, "at the bar's font size");
    const loose = {
      "background": false,
      "segments": false,
      "fills": false
    };
    compare(BarRuns.insets(c, null, loose, 1, section), {
      "lead": 6,
      "trail": 6
    }, "no background in a powerline: the loose gap");
    compare(BarRuns.insets(c, null, loose, 0, section), {
      "lead": 0,
      "trail": 6
    }, "none at the section's start");
    compare(BarRuns.insets(c, null, loose, 0, Object.assign({}, section, {
      "joinStart": true
    })), {
      "lead": 6,
      "trail": 6
    }, "unless it joins there");
    compare(BarRuns.insets(c, null, Object.assign({}, loose, {
      "fills": true
    }), 1, section), {
      "lead": 0,
      "trail": 0
    }, "a spacer keeps none");
    compare(BarRuns.insets(ctx("slant", "merged"), null, loose, 1, section), {
      "lead": 0,
      "trail": 0
    }, "no loose gap off a powerline");
  }
}
