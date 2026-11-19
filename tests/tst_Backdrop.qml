import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "Backdrop"

  // A 4x2 grid of a 4000x2000 image, row by row: the left half dark, the
  // right bright; the top right cell has a dark corner (low 10, high 250)
  readonly property var grid: ({
      "cols": 4,
      "rows": 2,
      "width": 4000,
      "height": 2000,
      "mean": [20, 20, 200, 200, 30, 30, 220, 220],
      "low": [10, 10, 100, 100, 10, 10, 120, 120],
      "high": [30, 30, 250, 250, 50, 50, 255, 255]
    })
  // The image fills the screen
  readonly property var full: ({
      "x": 0,
      "y": 0,
      "width": 1,
      "height": 1
    })
  readonly property var none: ({
      "x": 0,
      "y": 0
    })

  function enc(bytes) {
    return String(Qt.btoa(new Uint8Array(bytes).buffer));
  }

  function test_decode() {
    const g = Backdrop.decode({
      "cols": 2,
      "rows": 1,
      "width": 10,
      "height": 5,
      "mean": enc([1, 255]),
      "low": enc([0, 200]),
      "high": enc([2, 255])
    });
    compare(g.cols, 2);
    compare(g.width, 10);
    compare(g.mean, [1, 255]);
    compare(g.low, [0, 200]);
    compare(g.high, [2, 255]);
    // A short byte string is no grid
    compare(Backdrop.decode({
      "cols": 2,
      "rows": 1,
      "width": 10,
      "height": 5,
      "mean": enc([1]),
      "low": enc([1]),
      "high": enc([1])
    }), null);
  }

  function test_insideOneCell() {
    // The first cell: x 0-0.25, y 0-0.5
    const r = Backdrop.region(grid, full, {
      "x": 0.05,
      "y": 0.05,
      "width": 0.1,
      "height": 0.1
    }, none, false, 0);
    compare(r.mean, 20);
    compare(r.low, 10);
    compare(r.high, 30);
  }

  function test_acrossCells() {
    // The top row: dark, dark, bright, bright. The mean is of the luminances
    const r = Backdrop.region(grid, full, {
      "x": 0,
      "y": 0,
      "width": 1,
      "height": 0.5
    }, none, false, 0);
    verify(r.mean > 20 && r.mean < 200);
    // The 10th percentile of the lows is the darkest, the 90th of the highs the brightest
    compare(r.low, 10);
    compare(r.high, 250);
  }

  function test_percentilesSkipASmallPatch() {
    // 20 equal cells of 10 and one bright of 255: p90 of the highs stays low
    const cells = 21;
    const big = {
      "cols": cells,
      "rows": 1,
      "width": 21,
      "height": 1,
      "mean": new Array(cells).fill(10),
      "low": new Array(cells).fill(10),
      "high": new Array(cells).fill(10)
    };
    big.high[20] = 255;
    const r = Backdrop.region(big, full, full, none, false, 0);
    compare(r.high, 10);
  }

  function test_blurred() {
    const r = Backdrop.region(grid, full, {
      "x": 0,
      "y": 0,
      "width": 1,
      "height": 0.5
    }, none, true, 0);
    compare(r.low, 20);
    compare(r.high, 200);
  }

  function test_partialBlur() {
    // One cell (mean 200, low 100, high 250)
    const cell = {
      "x": 0.5,
      "y": 0,
      "width": 0.25,
      "height": 0.5
    };
    const raw = Backdrop.region(grid, full, cell, none, false, 0);
    const full1 = Backdrop.region(grid, full, cell, none, 1, 0);
    const half = Backdrop.region(grid, full, cell, none, 0.5, 0);
    compare(Backdrop.region(grid, full, cell, none, 0, 0).low, raw.low);
    compare(raw.low, 100);
    compare(raw.high, 250);
    compare(full1.low, 200);
    compare(full1.high, 200);
    compare(half.low, 150);
    compare(half.high, 225);
    compare(Backdrop.region(grid, full, cell, none, true, 0).low, full1.low);
    compare(Backdrop.region(grid, full, cell, none, undefined, 0).high, raw.high);
  }

  function test_shade() {
    compare(Backdrop.shade("off").shown, false);
    compare(Backdrop.shade("off").maxAlpha, 0);
    compare(Backdrop.shade("light").minContrast, 3.0);
    compare(Backdrop.shade("light").maxAlpha, 0.5);
    compare(Backdrop.shade("medium").minContrast, Tone.textContrast);
    compare(Backdrop.shade("medium").maxAlpha, 0.8);
    compare(Backdrop.shade("strong").maxAlpha, 1);
    compare(Backdrop.shade(undefined).maxAlpha, 1);
    compare(Backdrop.shade(undefined).shown, true);
    compare(Backdrop.shade("bogus").minContrast, Tone.textContrast);
  }

  function test_shadeAlpha() {
    compare(Backdrop.shadeAlpha(Backdrop.shade("medium"), 1), 0.8);
    compare(Backdrop.shadeAlpha(Backdrop.shade("medium"), 0.3), 0.3);
    compare(Backdrop.shadeAlpha(Backdrop.shade("strong"), 1), 1);
    compare(Backdrop.shadeAlpha(Backdrop.shade("light"), 0.9), 0.5);
    compare(Backdrop.shadeAlpha(Backdrop.shade("off"), 1), 0);
    const backs = Backdrop.backs(Backdrop.flat(255), "#000000", 0);
    // Gruvbox dark's text over the white pole needs 0.74, under Medium's cap
    const floor = Tone.alphaFloor("#282828", "#ebdbb2", backs, 4.55);
    verify(floor > 0.7 && floor < 0.8);
    compare(Backdrop.shadeAlpha(Backdrop.shade("medium"), floor), floor);
  }

  function test_letterbox() {
    // A fitted image (wide): bars above and below; a rect in the top bar is the
    // letterbox grey wholly, one across its edge counts both
    const fit = {
      "x": 0,
      "y": 0.25,
      "width": 1,
      "height": 0.5
    };
    const bar = Backdrop.region(grid, fit, {
      "x": 0,
      "y": 0,
      "width": 1,
      "height": 0.1
    }, none, false, 77);
    compare(bar.mean, 77);
    compare(bar.low, 77);
    compare(bar.high, 77);
    const edge = Backdrop.region(grid, fit, {
      "x": 0,
      "y": 0.2,
      "width": 0.1,
      "height": 0.1
    }, none, false, 255);
    compare(edge.high, 255);
    verify(edge.low < 255);
  }

  function test_travelWidens() {
    // A rect on the dark half; the wallpaper may move 0.5 toward the bright half
    const rect = {
      "x": 0.1,
      "y": 0,
      "width": 0.1,
      "height": 0.5
    };
    const still = Backdrop.region(grid, full, rect, none, false, 0);
    const moving = Backdrop.region(grid, full, rect, {
      "x": 0.5,
      "y": 0
    }, false, 0);
    compare(still.high, 30);
    verify(moving.high > 30);
  }

  function test_noGridIsTheLetterbox() {
    compare(Backdrop.region(null, full, full, none, false, 9).mean, 9);
  }

  function test_flat() {
    const r = Backdrop.flat("#ffffff");
    compare(r.mean, 255);
    compare(r.low, 255);
    compare(r.high, 255);
    compare(Backdrop.flat("#000000").mean, 0);
    // Mid grey #808080 has the grey level it was made from
    compare(Backdrop.flat("#808080").mean, 128);
  }

  function test_backs() {
    const r = {
      "mean": 100,
      "low": 0,
      "high": 255
    };
    const bare = Backdrop.backs(r, "#102030", 0);
    compare(bare.length, 3);
    fuzzyCompare(bare[1].r, 0, 1e-9);
    fuzzyCompare(bare[2].g, 1, 1e-9);
    fuzzyCompare(bare[0].r, 100 / 255, 1e-9);
    const full = Backdrop.backs(r, "#102030", 1);
    for (const b of full) {
      fuzzyCompare(b.r, 0x10 / 255, 1e-9);
      fuzzyCompare(b.b, 0x30 / 255, 1e-9);
    }
    // Opaque whatever the alpha
    compare(Backdrop.backs(r, "#102030", 0.5)[0].a, 1);
  }

  function test_band() {
    const screen = {
      "width": 2000,
      "height": 1000
    };
    compare(Backdrop.band("top", 30, 10, screen), {
      "x": 0,
      "y": 0,
      "width": 1,
      "height": 0.04
    });
    const bottom = Backdrop.band("bottom", 30, 10, screen);
    fuzzyCompare(bottom.y, 0.96, 1e-9);
    fuzzyCompare(bottom.height, 0.04, 1e-9);
    const left = Backdrop.band("left", 30, 10, screen);
    compare(left.x, 0);
    fuzzyCompare(left.width, 0.02, 1e-9);
    compare(left.height, 1);
    const right = Backdrop.band("right", 30, 10, screen);
    fuzzyCompare(right.x, 0.98, 1e-9);
    // Never deeper than the screen
    compare(Backdrop.band("top", 5000, 0, screen).height, 1);
  }
}
