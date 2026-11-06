import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "WallpaperFill"

  function near(actual, expected, message) {
    for (const key of Object.keys(expected)) {
      if (typeof expected[key] === "boolean")
        compare(actual[key], expected[key], message + " " + key);
      else
        fuzzyCompare(actual[key], expected[key], 1e-9, message + " " + key);
    }
  }

  function test_crop() {
    // A square image on a 2:1 screen: as wide as it, twice its height
    near(WallpaperFill.rect("crop", 1000, 1000, 2000, 1000, 0, 0, 0), {
      "x": 0,
      "y": -0.5,
      "width": 1,
      "height": 2
    }, "crop");
  }

  function test_fit() {
    near(WallpaperFill.rect("fit", 1000, 1000, 2000, 1000, 0, 0, 0), {
      "x": 0.25,
      "y": 0,
      "width": 0.5,
      "height": 1
    }, "fit");
  }

  function test_stretchAndCenter() {
    near(WallpaperFill.rect("stretch", 10, 500, 2000, 1000, 0, 0, 0), {
      "x": 0,
      "y": 0,
      "width": 1,
      "height": 1
    }, "stretch");
    near(WallpaperFill.rect("center", 500, 500, 2000, 1000, 0, 0, 0), {
      "x": 0.375,
      "y": 0.25,
      "width": 0.25,
      "height": 0.5
    }, "center keeps its own size");
  }

  // The px a rect slides end to end on each axis, and whether it still
  // covers the screen at both ends (where it covered at rest)
  function slide(fill, iw, ih, sw, sh, travel) {
    const first = WallpaperFill.rect(fill, iw, ih, sw, sh, travel, -1, -1);
    const last = WallpaperFill.rect(fill, iw, ih, sw, sh, travel, 1, 1);
    const covers = r => r.x <= 1e-9 && r.y <= 1e-9 && r.x + r.width >= 1 - 1e-9 && r.y + r.height >= 1 - 1e-9;
    return {
      "x": (first.x - last.x) * sw,
      "y": (first.y - last.y) * sh,
      "covers": covers(first) && covers(last)
    };
  }

  function test_parallax() {
    // 10% of a 2000x1000 screen's mean side: 150 px both ways, grown by
    // the tighter axis (its height: 1150 px), centred on what overflows
    near(WallpaperFill.rect("crop", 2000, 1000, 2000, 1000, 0.1, -1, 0), {
      "x": -0.0375,
      "y": -0.075,
      "width": 1.15,
      "height": 1.15
    }, "first workspace: its left end");
    near(WallpaperFill.rect("crop", 2000, 1000, 2000, 1000, 0.1, 1, 0), {
      "x": -0.1125
    }, "last workspace: its right end");
    near(WallpaperFill.rect("crop", 2000, 1000, 2000, 1000, 0.1, 5, 0), {
      "x": -0.1125
    }, "the shift is clamped");
  }

  function test_parallaxSamePx() {
    // A 16:10 image on a 16:9 screen: its crop overflow is no travel
    near(slide("crop", 1600, 1000, 1920, 1080, 0.04), {
      "x": 60,
      "y": 60,
      "covers": true
    }, "16:10 on 16:9");
    near(WallpaperFill.rect("crop", 1600, 1000, 1920, 1080, 0.04, 0, 0), {
      "width": 1.03125
    }, "grown only by what the tighter axis needs");
    near(slide("crop", 1920, 1080, 2560, 1080, 0.1), {
      "x": 182,
      "y": 182,
      "covers": true
    }, "16:9 on 21:9");
    near(slide("stretch", 10, 500, 2560, 1080, 0.1), {
      "x": 182,
      "y": 182,
      "covers": true
    }, "stretch");
    near(slide("fit", 1000, 1000, 2000, 1000, 0.1), {
      "x": 150,
      "y": 150
    }, "fit");
  }

  function test_parallaxFitKeepsWhatItCovered() {
    // An image a pixel off the screen's shape: no more than its half pixel
    // of letterbox at either end of a vertical slide (it was 13.6 px)
    const first = WallpaperFill.rect("fit", 1920, 1079, 1920, 1080, 0.04, 0, -1);
    const last = WallpaperFill.rect("fit", 1920, 1079, 1920, 1080, 0.04, 0, 1);
    verify(first.y * 1080 <= 0.5 + 1e-6, "first: no band at the top past the rest's");
    verify((1 - last.y - last.height) * 1080 <= 0.5 + 1e-6, "last: no band at the bottom past the rest's");
    // A clearly letterboxed side keeps its share: 21:9 on 16:9 grows by
    // its height's travel over the share it covers
    near(WallpaperFill.rect("fit", 2520, 1080, 1920, 1080, 0.04, 0, 0), {
      "width": 1 + 60 / 1080 / (1920 / 2520),
      "height": 1920 / 2520 + 60 / 1080
    }, "21:9 on 16:9");
    // "center" keeps a small image at its own size
    near(WallpaperFill.rect("center", 200, 100, 1920, 1080, 0.04, 0, 0), {
      "width": 200 / 1920,
      "height": 100 / 1080
    }, "small centred");
  }

  function test_notLoaded() {
    compare(WallpaperFill.rect("crop", 0, 0, 2000, 1000, 0, 0, 0), {
      "x": 0,
      "y": 0,
      "width": 0,
      "height": 0
    });
  }

  function test_decodeSize() {
    compare(WallpaperFill.decodeSize("crop", 1920, 1080, 0), {
      "width": 1920,
      "height": 1080
    });
    compare(WallpaperFill.decodeSize("crop", 1920, 1080, 0.05), {
      "width": 1995,
      "height": 1155
    }, "grown by the travel, the same px both ways");
    compare(WallpaperFill.decodeSize("fit", 1920, 1080, 0.05), {
      "width": 2054,
      "height": 1155
    }, "fit: grown by the shorter side's share");
    // An image a little narrower than the screen's shape, fitted: drawn
    // 1155 px tall (grown by the travel), so decoded at least that
    const r = WallpaperFill.rect("fit", 3800, 2160, 1920, 1080, 0.05, 0, 0);
    const size = WallpaperFill.decodeSize("fit", 1920, 1080, 0.05);
    const decoded = Math.min(size.width / 3800, size.height / 2160) * 2160;
    verify(decoded >= r.height * 1080 - 1e-6, "decoded " + decoded + " for " + r.height * 1080 + " drawn");
    compare(WallpaperFill.decodeSize("center", 1920, 1080, 0), null);
    compare(WallpaperFill.decodeSize("crop", 0, 0, 0), null, "no screen yet");
  }

  function test_fillMode() {
    compare(WallpaperFill.fillMode("crop"), Image.PreserveAspectCrop);
    compare(WallpaperFill.fillMode("fit"), Image.PreserveAspectFit);
    compare(WallpaperFill.fillMode("stretch"), Image.Stretch);
    compare(WallpaperFill.fillMode("center"), Image.Pad);
  }

  function test_parallaxShift() {
    compare(WallpaperFill.parallaxShift(0, 1), 0);
    compare(WallpaperFill.parallaxShift(0, 5), -1);
    compare(WallpaperFill.parallaxShift(2, 5), 0);
    compare(WallpaperFill.parallaxShift(4, 5), 1);
    compare(WallpaperFill.parallaxShift(-1, 5), 0, "unknown");
  }

  function test_parallaxGrid() {
    const grid = {
      "grid": true,
      "columns": 3,
      "rows": 2,
      "base": 11
    };
    // The same step both ways: two rows span half the travel, centred
    compare(WallpaperFill.parallax(11, grid), {
      "x": -1,
      "y": -0.5
    }, "top left");
    compare(WallpaperFill.parallax(15, grid), {
      "x": 0,
      "y": 0.5
    }, "bottom middle");
    compare(WallpaperFill.parallax(3, grid), {
      "x": 0,
      "y": 0
    }, "another output's");
  }

  function test_parallaxGridEqualSteps() {
    // 5x3: four steps across span the travel; the rows take the same step
    const grid = {
      "grid": true,
      "columns": 5,
      "rows": 3,
      "base": 1
    };
    compare(WallpaperFill.parallax(1, grid), {
      "x": -1,
      "y": -0.5
    }, "top left");
    compare(WallpaperFill.parallax(2, grid), {
      "x": -0.5,
      "y": -0.5
    }, "a step right");
    compare(WallpaperFill.parallax(6, grid), {
      "x": -1,
      "y": 0
    }, "a step down: the same");
    compare(WallpaperFill.parallax(15, grid), {
      "x": 1,
      "y": 0.5
    }, "bottom right");
  }

  function test_parallaxRow() {
    const row = {
      "base": 1,
      "size": 5
    };
    compare(WallpaperFill.parallax(1, row), {
      "x": -1,
      "y": 0
    });
    compare(WallpaperFill.parallax(9, row), {
      "x": 1,
      "y": 0
    }, "past the last: clamped");
  }

  function test_parallaxDynamic() {
    const column = {
      "dynamic": true,
      "vertical": true,
      "ids": [7, 3, 9],
      "steps": 3
    };
    compare(WallpaperFill.parallax(3, column), {
      "x": 0,
      "y": 0
    }, "the middle of three, in the compositor's order");
    compare(WallpaperFill.parallax(9, column), {
      "x": 0,
      "y": 1
    });
    compare(WallpaperFill.parallax(4, column), {
      "x": 0,
      "y": 0
    }, "not listed");
    // A fixed step each: a workspace added at the end (niri's empty one
    // taken) moves none of the others; past `steps`, it stays at the end
    const five = Object.assign({}, column, {
      "steps": 5
    });
    compare(WallpaperFill.parallax(3, five), {
      "x": 0,
      "y": -0.5
    }, "the second of five steps");
    compare(WallpaperFill.parallax(3, Object.assign({}, five, {
      "ids": [7, 3, 9, 12]
    })), {
      "x": 0,
      "y": -0.5
    }, "unmoved by another workspace");
    compare(WallpaperFill.parallax(6, Object.assign({}, five, {
      "ids": [7, 3, 9, 12, 2, 4, 6]
    })), {
      "x": 0,
      "y": 1
    }, "past the last step: at the end");
    // A grid layout left in the config doesn't lay out a dynamic list:
    // the fourth row is three steps down, not the grid's second row
    compare(WallpaperFill.parallax(4, Object.assign({}, five, {
      "grid": true,
      "columns": 3,
      "rows": 3,
      "base": 1,
      "ids": [1, 2, 3, 4, 5]
    })), {
      "x": 0,
      "y": 0.5
    }, "dynamic over a grid");
    compare(WallpaperFill.parallax(-1, null), {
      "x": 0,
      "y": 0
    });
  }
  // Three columns 1000 wide, 20 apart, on a 1920 wide output
  function strip(focused) {
    return [0, 1, 2].map(i => ({
          "x": 20 + i * 1020,
          "y": 0,
          "w": 1000,
          "h": 1080,
          "focusRank": i === focused ? 0 : 1 + i
        }));
  }

  function test_stripShift() {
    compare(WallpaperFill.stripShift(strip(0), false, 1920), -1, "the first column");
    compare(WallpaperFill.stripShift(strip(2), false, 1920), 1, "the last");
    fuzzyCompare(WallpaperFill.stripShift(strip(1), false, 1920), 0, 1e-9, "the middle");
    compare(WallpaperFill.stripShift(strip(0).slice(0, 1), false, 1920), 0, "fits: nothing scrolls");
    compare(WallpaperFill.stripShift([], false, 1920), 0, "no windows");
    const moved = strip(2).map(w => Object.assign({}, w, {
        "x": w.x - 1500
      }));
    compare(WallpaperFill.stripShift(moved, false, 1920), 1, "reported where it shows: the same");
    const column = strip(2).map(w => ({
          "x": 0,
          "y": w.x,
          "w": 1920,
          "h": w.w,
          "focusRank": w.focusRank
        }));
    compare(WallpaperFill.stripShift(column, true, 1080), 1, "a vertical strip");
  }

  function test_parallaxStrip() {
    // niri: workspaces stacked, every output a horizontal strip
    const niri = {
      "dynamic": true,
      "vertical": true,
      "ids": [7, 3, 9],
      "steps": 3,
      "strip": "horizontal",
      "windows": strip(2),
      "width": 1920,
      "height": 1080
    };
    compare(WallpaperFill.parallax(9, niri), {
      "x": 1,
      "y": 1
    }, "the strip across, the workspaces down");
    compare(WallpaperFill.parallax(9, Object.assign({}, niri, {
      "still": false
    })), {
      "x": 1,
      "y": 0
    }, "a wallpaper sliding with its workspace: the strip alone");
    // Hyprland's scrolling layout: workspaces in a row, a horizontal strip
    const row = {
      "base": 1,
      "size": 5,
      "strip": "horizontal",
      "windows": strip(0),
      "width": 1920,
      "height": 1080
    };
    compare(WallpaperFill.parallax(5, row), {
      "x": -1,
      "y": 1
    }, "the strip takes x; the workspaces move to y");
    compare(WallpaperFill.parallax(5, Object.assign({}, row, {
      "strip": "vertical",
      "windows": []
    })), {
      "x": 1,
      "y": 0
    }, "a vertical strip leaves x to the workspaces");
    compare(WallpaperFill.parallax(1, Object.assign({}, row, {
      "strip": ""
    })), {
      "x": -1,
      "y": 0
    }, "no strip: as before");
    // A grid with a strip: the strip takes its axis, the grid keeps the
    // other, also in its middle row (a shift of 0)
    const grid = {
      "grid": true,
      "columns": 3,
      "rows": 3,
      "base": 1,
      "strip": "horizontal",
      "windows": [],
      "width": 1920,
      "height": 1080
    };
    compare(WallpaperFill.parallax(4, grid), {
      "x": 0,
      "y": 0
    }, "a grid's middle row, first column: the row's shift, not the column's");
    compare(WallpaperFill.parallax(1, grid), {
      "x": 0,
      "y": -1
    }, "a grid's first row");
  }
}
