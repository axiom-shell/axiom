import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "ToastMotion"

  // A 1920x1080 screen with a 360x100 stack at (x, y)
  function edgeFor(edge, x, y, attached, override) {
    return ToastMotion.slideEdge({
      "attached": !!attached,
      "edge": edge,
      "rect": {
        "x": x,
        "y": y,
        "width": 360,
        "height": 100
      },
      "screenWidth": 1920,
      "screenHeight": 1080,
      "override": override ?? "auto"
    });
  }

  function test_slideEdge_detached_nearest() {
    compare(edgeFor(ScreenEdge.Top, 1548, 50), ScreenEdge.Right, "top right, under a bar: the right edge is nearer (12 px) than the top (50)");
    compare(edgeFor(ScreenEdge.Top, 12, 50), ScreenEdge.Left);
    compare(edgeFor(ScreenEdge.Top, 780, 50), ScreenEdge.Top, "centred on the top edge");
    compare(edgeFor(ScreenEdge.Bottom, 780, 930), ScreenEdge.Bottom);
    compare(edgeFor(ScreenEdge.Right, 1548, 490), ScreenEdge.Right);
    compare(edgeFor(ScreenEdge.Top, 1548, 12), ScreenEdge.Top, "a tie goes to its own edge");
    compare(edgeFor(ScreenEdge.Bottom, 1548, 968), ScreenEdge.Bottom);
  }

  function test_slideEdge_attached_and_override() {
    compare(edgeFor(ScreenEdge.Top, 1548, 12, true), ScreenEdge.Top, "attached: out of its own edge");
    compare(edgeFor(ScreenEdge.Right, 1548, 0, true), ScreenEdge.Right);
    compare(edgeFor(ScreenEdge.Top, 1548, 50, false, "top"), ScreenEdge.Top, "an override wins");
    compare(edgeFor(ScreenEdge.Top, 780, 50, true, "left"), ScreenEdge.Left);
  }

  function test_growth() {
    compare(ToastMotion.growth(ScreenEdge.Top, 1), {
      "sign": 1
    });
    compare(ToastMotion.growth(ScreenEdge.Bottom, 0).sign, -1, "bottom stacks grow up");
    compare(ToastMotion.growth(ScreenEdge.Left, 0), {
      "sign": 1
    });
    compare(ToastMotion.growth(ScreenEdge.Right, 0.5).sign, 1, "from the middle, down");
    compare(ToastMotion.growth(ScreenEdge.Right, 1).sign, -1, "from the bottom end, up");
  }

  function test_rows() {
    compare(ToastMotion.rows([80, 100, 60], 8), {
      "offsets": [0, 88, 196],
      "length": 256
    });
    compare(ToastMotion.rows([], 8), {
      "offsets": [],
      "length": 0
    });
  }

  function test_leave() {
    compare(ToastMotion.leave(0, ScreenEdge.Top, 80, 300), {
      "shift": {
        "x": 0,
        "y": -300
      },
      "tuck": false
    }, "the edge toast slides all the way out");
    compare(ToastMotion.leave(2, ScreenEdge.Top, 80, 300), {
      "shift": {
        "x": 0,
        "y": -40
      },
      "tuck": true
    }, "a lower one tucks behind those nearer the edge");
    compare(ToastMotion.leave(2, ScreenEdge.Right, 80, 400), {
      "shift": {
        "x": 400,
        "y": 0
      },
      "tuck": false
    }, "sliding sideways passes no other toast");
  }
}
