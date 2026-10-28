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

  readonly property var profiles: [
    {
      "name": "Desk",
      "outputs": [
        {
          "output": "desc:AOC CU34G4Z XJ9R7HA000231"
        },
        {
          "output": "HDMI-A-1",
          "disabled": true
        }
      ]
    },
    {
      "name": "TV",
      "outputs": [
        {
          "output": "desc:AOC CU34G4Z XJ9R7HA000231"
        },
        {
          "output": "desc:LG TV"
        }
      ]
    }
  ]

  function test_matchProfile() {
    compare(MonitorLayout.matchProfile(profiles, [aoc]), 0, "a disabled output may be missing");
    compare(MonitorLayout.matchProfile(profiles, [aoc, tv]), 1, "exact match wins");
    compare(MonitorLayout.matchProfile(profiles, [tv]), 1, "most covered");
    compare(MonitorLayout.matchProfile(profiles, [
      {
        "name": "DP-3",
        "description": "Other"
      }
    ]), -1);
    compare(MonitorLayout.matchProfile([], [aoc]), -1);
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
}
