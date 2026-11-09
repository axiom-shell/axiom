import QtQuick
import QtTest
import qs.components.methods

// Tabs: their fillet, shape, limits and shift (BarTabs)
TestCase {
  name: "BarTabs"

  function test_tab_radius_and_flare() {
    const t = BarTabs.tab(20, 26, 5, true, [null, null]);
    compare([t.radius, t.start.flare, t.end.flare], [13, 5, 5]);
    const s = BarTabs.tab(6, 26, 0, false, [null, null]);
    compare([s.radius, s.start.flare, s.outerStart], [6, 0, false]);
  }

  // One fillet for every tab on a bar: the corner radius, within half the
  // widget gap and the room at the bar's ends; none when square
  function test_tab_fillet() {
    compare(BarTabs.tabFillet(6, 26, "flared", 20, 8), 6);
    compare(BarTabs.tabFillet(6, 26, "flared", 4, 8), 2);
    compare(BarTabs.tabFillet(20, 26, "flared", 40, Infinity), 13);
    compare(BarTabs.tabFillet(6, 26, "flared", 20, 5), 5);
    compare(BarTabs.tabFillet(6, 26, "flared", 0, 8), 0);
    compare(BarTabs.tabFillet(6, 26, "square", 20, 8), 0);
  }

  // An end nearer a bound than its curve takes the curve, else the
  // bar's fillet like every other tab
  function test_tab_limits() {
    const near = BarTabs.tab(6, 26, 4, true, [
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
    compare(BarTabs.tabLimits(155, 200, bounds), [
      {
        "gap": 5,
        "radius": 8
      },
      null], "an end as far from its bound as the curve reaches isn't held");
    compare(BarTabs.tabLimits(10, 95, bounds), [null,
      {
        "gap": 5,
        "radius": 8
      }
    ]);
    compare(BarTabs.tabLimits(110, 140, bounds), [null, null]);
    compare(BarTabs.tabLimits(10, 20, []), [null, null]);
  }

  // Content and separator marks move half the reach toward the outer edge
  function test_tab_shift_centres_in_the_tab() {
    compare(BarTabs.tabShift(10, false), -5);
    compare(BarTabs.tabShift(10, true), 5);
    compare(BarTabs.tabShift(5, false), -3);
    compare(BarTabs.tabShift(0, true), 0);
  }

  // A box's tab on a bar: the bar's own tab where its shape is one, from
  // its outer edge; none on any other shape
  function test_bar_tab() {
    const bar = (name, over) => Object.assign({
        "radius": 6,
        "thickness": 26,
        "right": false,
        "bottom": false,
        "look": {
          "shape": {
            "name": name,
            "tabFillet": 3
          }
        }
      }, over);
    compare(BarTabs.barTab(bar("rounded"), [null, null]), null);
    compare(BarTabs.barTab(bar("tab"), [null, null]), BarTabs.tab(6, 26, 3, true, [null, null]));
    compare(BarTabs.barTab(bar("tab", {
      "bottom": true
    }), [null, null]).outerStart, false, "a bottom bar's outer edge is past its far side");
  }

  // A tab's reach across: before the near side from a top or left bar,
  // past the far side from a bottom or right one
  function test_reach_across() {
    compare(BarTabs.reachAcross(6, false), {
      "near": 6,
      "far": 0
    });
    compare(BarTabs.reachAcross(6, true), {
      "near": 0,
      "far": 6
    });
  }
}
