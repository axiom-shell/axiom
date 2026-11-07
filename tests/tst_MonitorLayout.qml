import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "MonitorLayout"

  function test_parseMode() {
    compare(MonitorLayout.parseMode("3440x1440@240.00Hz"), {
      "width": 3440,
      "height": 1440,
      "rate": 240
    });
    compare(MonitorLayout.parseMode("1920x1080@59.94").rate, 59.94);
    compare(MonitorLayout.parseMode("1920x1080").rate, 0);
    compare(MonitorLayout.parseMode("preferred"), null);
  }

  function test_formatMode() {
    compare(MonitorLayout.formatMode(3440, 1440, 240.00101), "3440x1440@240");
    compare(MonitorLayout.formatMode(1920, 1080, 59.9400), "1920x1080@59.94");
    compare(MonitorLayout.formatMode(1920, 1080, 0), "1920x1080");
  }

  function test_availableMode_and_describe() {
    compare(MonitorLayout.availableMode(3440, 1440, 239991), "3440x1440@239.99Hz", "a rate in mHz, two decimals");
    compare(MonitorLayout.availableMode(1920, 1080, 60000), "1920x1080@60.00Hz");
    compare(MonitorLayout.hz(59940), 59.94);
    compare(MonitorLayout.hz(undefined), 0);
    compare(MonitorLayout.parseMode(MonitorLayout.availableMode(2560, 1440, 143912)), {
      "width": 2560,
      "height": 1440,
      "rate": 143.91
    }, "parseMode reads it back");
    compare(MonitorLayout.describe({
      "make": "Dell Inc.",
      "model": "U2720Q",
      "serial": "Unknown"
    }), "Dell Inc. U2720Q", "an Unknown part is left out");
    compare(MonitorLayout.describe(null), "");
  }

  function test_parseModes_groups_and_sorts() {
    const modes = MonitorLayout.parseModes(["1920x1080@60.00Hz", "3440x1440@60.00Hz", "3440x1440@240.00Hz", "1920x1080@60.00Hz", "1920x1080@119.88Hz", "junk"]);
    compare(modes.length, 2);
    compare(modes[0].width, 3440);
    compare(modes[0].rates, [240, 60]);
    compare(modes[1].rates, [119.88, 60], "duplicates dropped, highest first");
  }

  function test_validScales() {
    const scales = MonitorLayout.validScales(3440, 1440);
    verify(scales.includes(1));
    verify(scales.includes(1.25));
    verify(scales.includes(2));
    verify(!scales.includes(1.5), "3440 / 1.5 isn't whole");
    const kept = MonitorLayout.validScales(3440, 1440, 1.5);
    verify(kept.includes(1.5), "the current scale stays offered");
    compare(kept, kept.slice().sort((a, b) => a - b));
  }

  function test_logicalSize_turns_and_scales() {
    compare(MonitorLayout.logicalSize(3840, 2160, 2, 0), {
      "width": 1920,
      "height": 1080
    });
    compare(MonitorLayout.logicalSize(3440, 1440, 1, 3), {
      "width": 1440,
      "height": 3440
    });
    compare(MonitorLayout.logicalSize(3440, 1440, 1, 4).width, 3440, "flipped only");
  }

  readonly property var main: ({
      "x": 0,
      "y": 0,
      "width": 3440,
      "height": 1440
    })

  function test_snap_edge_to_edge() {
    const result = MonitorLayout.snap({
      "x": 3450,
      "y": 5,
      "width": 1920,
      "height": 1080
    }, [main], 20);
    compare(result.x, 3440, "right of the main monitor");
    compare(result.y, 0, "tops aligned");
    compare(result.guides.length, 2);
    compare(result.guides[0], {
      "axis": "x",
      "at": 3440
    });
  }

  function test_snap_centre_and_left_of() {
    const result = MonitorLayout.snap({
      "x": -1925,
      "y": 175,
      "width": 1920,
      "height": 1080
    }, [main], 20);
    compare(result.x, -1920, "left of the main monitor");
    compare(result.y, 180, "centred on it");
  }

  function test_snap_leaves_a_free_offset() {
    const result = MonitorLayout.snap({
      "x": 3440,
      "y": 400,
      "width": 1920,
      "height": 1080
    }, [main], 20);
    compare(result.y, 400, "nothing within reach on y");
    compare(result.guides.length, 1);
  }

  function test_bounds() {
    compare(MonitorLayout.bounds([]), {
      "x": 0,
      "y": 0,
      "width": 1920,
      "height": 1080
    });
    compare(MonitorLayout.bounds([
      {
        "x": 0,
        "y": 200,
        "width": 3440,
        "height": 1440
      },
      {
        "x": 3440,
        "y": 0,
        "width": 1080,
        "height": 1920
      }
    ]), {
      "x": 0,
      "y": 0,
      "width": 4520,
      "height": 1920
    });
    compare(MonitorLayout.bounds([
      {
        "x": -1920,
        "y": -1080,
        "width": 1920,
        "height": 1080
      }
    ]), {
      "x": -1920,
      "y": -1080,
      "width": 1920,
      "height": 1080
    });
  }

  function test_fit_centres_and_places() {
    const rects = [
      {
        "x": 0,
        "y": 0,
        "width": 1920,
        "height": 1080
      },
      {
        "x": 1920,
        "y": 0,
        "width": 1920,
        "height": 1080
      }
    ];
    // 3840×1080 in 400×400 less 20 a side: the width decides
    const view = MonitorLayout.fit(rects, 400, 400, 20);
    fuzzyCompare(view.scale, 360 / 3840, 1e-9);
    const second = MonitorLayout.place(rects[1], view);
    fuzzyCompare(second.x, 200, 1e-6, "the second starts at the middle");
    fuzzyCompare(second.width, 180, 1e-6);
    fuzzyCompare(second.y, (400 - 1080 * view.scale) / 2, 1e-6, "centred down");
    fuzzyCompare(MonitorLayout.place(rects[0], view).x, 20, 1e-6, "the margin on the left");
    // A layout away from the origin lands the same
    const moved = rects.map(r => Object.assign({}, r, {
        "x": r.x - 5000,
        "y": r.y + 300
      }));
    fuzzyCompare(MonitorLayout.place(moved[1], MonitorLayout.fit(moved, 400, 400, 20)).x, 200, 1e-6);
    verify(MonitorLayout.fit(rects, 0, 0, 20).scale > 0, "never a zero or negative scale");
  }

  function test_fitSize() {
    const tall = [
      {
        "x": 0,
        "y": 0,
        "width": 1080,
        "height": 1920
      }
    ];
    compare(MonitorLayout.fitSize(tall, 1000, 480), {
      "width": 270,
      "height": 480
    });
    compare(MonitorLayout.fitSize([], 960, 1000), {
      "width": 960,
      "height": 540
    }, "no rects: a 16:9 box");
  }

  function test_fillMissing() {
    const known = {
      "x": 100,
      "y": 50,
      "width": 2560,
      "height": 1440
    };
    compare(MonitorLayout.fillMissing([null, known, null]), [
      {
        "x": 2660,
        "y": 50,
        "width": 2560,
        "height": 1440
      },
      known,
      {
        "x": 5220,
        "y": 50,
        "width": 2560,
        "height": 1440
      }
    ]);
    compare(MonitorLayout.fillMissing([null]), [
      {
        "x": 0,
        "y": 0,
        "width": 1920,
        "height": 1080
      }
    ], "none known: one 1080p stand-in at the origin");
    compare(MonitorLayout.fillMissing([known]), [known]);
  }

  function test_overlaps() {
    const beside = {
      "x": 3440,
      "y": 0,
      "width": 1920,
      "height": 1080
    };
    const onTop = {
      "x": 3000,
      "y": 100,
      "width": 1920,
      "height": 1080
    };
    compare(MonitorLayout.overlaps([main, beside]), []);
    compare(MonitorLayout.overlaps([main, beside, onTop]), [[0, 2], [1, 2]]);
  }

  function test_islands() {
    const beside = {
      "x": 3440,
      "y": 1000,
      "width": 1920,
      "height": 1080
    };
    const cornerOnly = {
      "x": 3440,
      "y": 1440,
      "width": 100,
      "height": 100
    };
    const far = {
      "x": 9000,
      "y": 0,
      "width": 100,
      "height": 100
    };
    compare(MonitorLayout.islands([main]), []);
    compare(MonitorLayout.islands([main, beside]), []);
    compare(MonitorLayout.islands([main, cornerOnly]), [1], "a shared corner isn't a way across");
    compare(MonitorLayout.islands([main, beside, far]), [2]);
  }

  readonly property var aoc: ({
      "name": "DP-1",
      "description": "AOC CU34G4Z XJ9R7HA000231"
    })
  readonly property var tv: ({
      "name": "HDMI-A-1",
      "description": "LG TV"
    })

  function test_outputId() {
    compare(MonitorLayout.outputId(aoc, [aoc, tv]), "desc:AOC CU34G4Z XJ9R7HA000231");
    const twin = {
      "name": "DP-2",
      "description": aoc.description
    };
    compare(MonitorLayout.outputId(aoc, [aoc, twin]), "DP-1", "twins fall back to the connector");
    compare(MonitorLayout.outputId({
      "name": "eDP-1",
      "description": ""
    }, []), "eDP-1");
  }

  function test_matches_across_compositors() {
    const niri = {
      "name": "DP-1",
      "description": "PNP(AOC) CU34G4Z XJ9R7HA000231"
    };
    verify(MonitorLayout.matches("desc:AOC CU34G4Z XJ9R7HA000231", niri), "niri's PNP(XXX) make matches the bare code");
    verify(MonitorLayout.matches("desc:PNP(AOC) CU34G4Z XJ9R7HA000231 ", aoc), "and the other way");
    verify(!MonitorLayout.matches("desc:AOC CU34G4Z", niri));
  }

  function test_ruleFromMonitor() {
    const monitor = {
      "name": "DP-1",
      "description": aoc.description,
      "width": 3440,
      "height": 1440,
      "refreshRate": 240.00101,
      "x": 0,
      "y": 0,
      "scale": 1,
      "transform": 0,
      "disabled": false,
      "mirrorOf": "none",
      "vrr": false,
      "currentFormat": "XRGB8888",
      "colorManagementPreset": "srgb",
      "sdrBrightness": 1,
      "sdrSaturation": 1
    };
    const rule = MonitorLayout.ruleFromMonitor(monitor, [monitor]);
    compare(rule.output, "desc:" + aoc.description);
    compare(rule.label, "DP-1");
    compare(rule.mode, "3440x1440@240");
    compare(rule.bitdepth, 8);
    compare(rule.cm, "srgb");
    compare(rule.mirror, "");
    compare(MonitorLayout.ruleRect(rule, monitor), main);
  }

  function test_wholeScaleRules() {
    const laptop = {
      "name": "eDP-1",
      "description": "BOE laptop",
      "width": 2880,
      "height": 1800,
      "refreshRate": 120,
      "x": 1280,
      "y": 0,
      "scale": 2,
      "transform": 0
    };
    const side = {
      "name": "DP-2",
      "description": "Dell side",
      "width": 2560,
      "height": 1440,
      "refreshRate": 60,
      "x": 0,
      "y": 200,
      "scale": 1.25,
      "transform": 1
    };
    const rules = MonitorLayout.wholeScaleRules([laptop, side]);
    compare(rules.map(rule => rule.label), ["DP-2", "eDP-1"]);
    // 1.25 rounds down; the laptop's whole 2 stays
    compare(rules.map(rule => rule.scale), [1, 2]);
    // DP-2 stands sideways: 1440 wide at 100%
    compare(rules.map(rule => [rule.x, rule.y]), [[0, 0], [1440, 0]]);
    const fractional = Object.assign({}, laptop, {
      "scale": 2.5
    });
    compare(MonitorLayout.wholeScaleRules([fractional])[0].scale, 2);
  }

  // Two monitors as Hyprland's `monitors all` has them, the TV mirroring
  // the main one (mirrorOf is the mirrored one's id)
  function _mirrored() {
    const main = {
      "id": 1,
      "name": "DP-1",
      "description": "Main",
      "width": 2560,
      "height": 1440,
      "refreshRate": 144,
      "x": 0,
      "y": 0,
      "scale": 1,
      "transform": 0,
      "disabled": false,
      "mirrorOf": "none"
    };
    const tv = {
      "id": 2,
      "name": "HDMI-A-1",
      "description": "TV",
      "width": 1920,
      "height": 1080,
      "refreshRate": 60,
      "x": 598,
      "y": 0,
      "scale": 1,
      "transform": 0,
      "disabled": false,
      "mirrorOf": "1"
    };
    return [main, tv];
  }

  function test_ruleFromMonitor_reads_a_mirror_by_id() {
    const live = _mirrored();
    compare(MonitorLayout.ruleFromMonitor(live[1], live).mirror, "desc:Main");
    compare(MonitorLayout.ruleFromMonitor(live[0], live).mirror, "");
  }

  function test_differsFromLive() {
    const live = _mirrored();
    const now = live.map(monitor => MonitorLayout.ruleFromMonitor(monitor, live));
    verify(!MonitorLayout.differsFromLive(now, live), "the monitors as they are");
    // the saved layout says no mirror while the TV still mirrors: Apply
    // must show
    const apart = now.map(rule => Object.assign({}, rule));
    apart[1].mirror = "";
    apart[1].x = 2560;
    verify(MonitorLayout.differsFromLive(apart, live), "a mirror the rules end");
    const flat = live.map(monitor => Object.assign({}, monitor, {
        "mirrorOf": "none"
      }));
    flat[1].x = 2560;
    verify(!MonitorLayout.differsFromLive(apart, flat), "once it's ended");
    verify(MonitorLayout.differsFromLive(now, flat), "and back");
    const turned = apart.map(rule => Object.assign({}, rule));
    turned[0].transform = 1;
    verify(MonitorLayout.differsFromLive(turned, flat), "a rotation");
    const off = apart.map(rule => Object.assign({}, rule));
    off[1].disabled = true;
    verify(MonitorLayout.differsFromLive(off, flat), "turned off");
    const moved = apart.map(rule => Object.assign({}, rule));
    moved[1].y = 10;
    verify(MonitorLayout.differsFromLive(moved, flat), "moved");
    const rate = apart.map(rule => Object.assign({}, rule));
    rate[0].mode = "2560x1440@60";
    verify(MonitorLayout.differsFromLive(rate, flat), "another rate");
    // what isn't compared: a mirror's position, a preferred mode, a rule
    // for a monitor not connected, vrr and the colour
    const loose = now.map(rule => Object.assign({}, rule));
    loose[1].x = 9999;
    loose[0].mode = "preferred";
    loose[0].vrr = 2;
    loose[0].cm = "auto";
    loose.push({
      "output": "desc:Gone",
      "x": 5000,
      "y": 0
    });
    verify(!MonitorLayout.differsFromLive(loose, live));
    // a scale giving no whole logical size: Hyprland rounds it to a valid
    // one near it, which isn't a difference; a valid one is compared
    const odd = flat.map(monitor => Object.assign({}, monitor, {
        "width": 1366,
        "height": 768
      }));
    const asked = apart.map(rule => Object.assign({}, rule, {
        "mode": "1366x768"
      }));
    asked[0].scale = 1.25;
    verify(!MonitorLayout.differsFromLive(asked, odd.map((monitor, i) => i === 0 ? Object.assign({}, monitor, {
        "scale": MonitorLayout.validScales(1366, 768).find(scale => scale > 1.25)
      }) : monitor)), "a scale Hyprland rounded");
    verify(MonitorLayout.differsFromLive(asked, odd.map((monitor, i) => i === 0 ? Object.assign({}, monitor, {
        "scale": 3
      }) : monitor)), "a scale far from it");
    const whole = apart.map(rule => Object.assign({}, rule));
    whole[0].scale = 2;
    verify(MonitorLayout.differsFromLive(whole, flat), "a valid scale not shown");
    // where the compositor can't mirror (niri, sway), a saved mirror is
    // placed by its position: only that is compared
    const mirrorOnNiri = now.map(rule => Object.assign({}, rule));
    mirrorOnNiri[1].x = 2560;
    verify(!MonitorLayout.differsFromLive(mirrorOnNiri, flat, false), "a mirror niri can't do");
    verify(MonitorLayout.differsFromLive(mirrorOnNiri, flat), "one Hyprland can");
    mirrorOnNiri[1].x = 0;
    verify(MonitorLayout.differsFromLive(mirrorOnNiri, flat, false), "placed elsewhere");
  }

  function test_snapshot() {
    const live = _mirrored();
    const before = live.map(monitor => MonitorLayout.ruleFromMonitor(monitor, live));
    compare(MonitorLayout.snapshot(live), before, "how the monitors are");
    // vrr 2 reads off outside fullscreen: the saved rule's, where the
    // monitors show it
    const shown = Object.assign({}, before[0], {
      "vrr": 2
    });
    compare(MonitorLayout.snapshot(live, [shown])[0].vrr, 2);
    const fullscreen = live.map(monitor => Object.assign({}, monitor, {
        "vrr": true
      }));
    compare(MonitorLayout.snapshot(fullscreen, [shown])[0].vrr, 2, "active in fullscreen");
    const moved = Object.assign({}, shown, {
      "x": before[0].x + 100
    });
    compare(MonitorLayout.snapshot(live, [moved])[0].vrr, 0, "not a rule the monitors show");
  }

  function test_restored() {
    const live = _mirrored();
    const before = live.map(monitor => MonitorLayout.ruleFromMonitor(monitor, live));
    const tried = [
      {
        "output": "DP-1",
        "x": 0,
        "y": 0,
        "transform": 1
      },
      {
        "output": "desc:TV",
        "x": 2560,
        "mirror": ""
      },
      {
        "output": "desc:Gone",
        "x": 5000
      }
    ];
    const back = MonitorLayout.restored(tried, before, live);
    compare(back.map(rule => rule.output), ["DP-1", "desc:TV", "desc:Gone"], "each rule keeps its own output");
    compare(back[0].transform, 0);
    compare(back[1].mirror, "desc:Main", "the mirror comes back");
    compare(back[2].x, 5000, "a monitor not connected keeps its rule");
    verify(!MonitorLayout.differsFromLive(back, live));
    // the saved rule where the monitors showed it: what Hyprland reads
    // back differently stays as saved
    const saved = [Object.assign({}, before[0], {
        "output": "DP-1",
        "mode": "preferred",
        "vrr": 2,
        "cm": "auto"
      }), Object.assign({}, before[1], {
        "mirror": ""
      })];
    const kept = MonitorLayout.restored(tried, before, live, saved);
    compare(kept[0].mode, "preferred", "the saved rule, which the monitor showed");
    compare(kept[0].vrr, 2);
    compare(kept[1].mirror, "desc:Main", "not one the monitors didn't show");
    verify(!MonitorLayout.differsFromLive(kept, live));
  }
}
