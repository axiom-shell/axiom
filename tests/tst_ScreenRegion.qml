import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "ScreenRegion"

  readonly property var dp1: ({
      "name": "DP-1",
      "x": 0,
      "y": 0,
      "width": 1920,
      "height": 1080
    })
  readonly property var dp2: ({
      "name": "DP-2",
      "x": 1920,
      "y": -200,
      "width": 1280,
      "height": 1440
    })

  function r(x, y, width, height) {
    return {
      "x": x,
      "y": y,
      "width": width,
      "height": height
    };
  }

  function test_between() {
    compare(ScreenRegion.between({
      "x": 50,
      "y": 80
    }, {
      "x": 10,
      "y": 20
    }), r(10, 20, 40, 60), "dragged up and left");
  }

  function test_intersect() {
    compare(ScreenRegion.intersect(r(1800, 100, 300, 50), dp1), r(1800, 100, 120, 50));
    compare(ScreenRegion.intersect(r(1800, 100, 300, 50), dp2), r(1920, 100, 180, 50));
    verify(ScreenRegion.isEmpty(ScreenRegion.intersect(r(0, 0, 10, 10), r(10, 0, 10, 10))), "touching edges don't overlap");
  }

  function test_local() {
    compare(ScreenRegion.local(r(1800, -100, 300, 400), dp1), r(1800, 0, 120, 300), "clipped to the screen");
    compare(ScreenRegion.local(r(1800, -100, 300, 400), dp2), r(0, 100, 180, 400), "from the screen's top left");
    verify(ScreenRegion.isEmpty(ScreenRegion.local(r(0, 0, 100, 100), dp2)), "not on it");
  }

  function test_toGlobal() {
    compare(ScreenRegion.toGlobal(r(0, 100, 180, 400), dp2), r(1920, -100, 180, 400));
  }

  function test_covered() {
    compare(ScreenRegion.covered(r(1800, 0, 300, 10), [dp1, dp2]).map(s => s.name), ["DP-1", "DP-2"]);
    compare(ScreenRegion.covered(r(10, 10, 300, 10), [dp1, dp2]).map(s => s.name), ["DP-1"]);
    compare(ScreenRegion.covered(r(10, 2000, 300, 10), [dp1, dp2]).length, 0, "a gap below both");
  }

  function test_boxAt() {
    const spill = {
      "output": "DP-1",
      "x": 1500,
      "y": 0,
      "width": 800,
      "height": 600
    };
    const own = {
      "output": "DP-2",
      "x": 2000,
      "y": 0,
      "width": 400,
      "height": 400
    };
    compare(ScreenRegion.boxAt([spill, own], 2100, 100, "DP-2"), own, "the screen's own window first");
    compare(ScreenRegion.boxAt([spill, own], 2100, 500, "DP-2"), spill, "a window spilling over from the next screen");
    compare(ScreenRegion.boxAt([spill, own], 100, 100, "DP-1"), null);
  }
}
