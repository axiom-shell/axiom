import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "BackingRule"

  function test_backsOn_truth_table() {
    for (let i = 0; i < 16; i++) {
      const o = {
        "backing": (i & 1) !== 0,
        "fullscreen": (i & 2) !== 0,
        "onOverlay": (i & 4) !== 0,
        "backingOnOverlay": (i & 8) !== 0
      };
      compare(BackingRule.backsOn(o), o.backing && (!o.fullscreen || (o.onOverlay && o.backingOnOverlay)), JSON.stringify(o));
    }
  }

  // Over a fullscreen window a surface on Overlay is backed only where the
  // backing window rose too (sway's stays on Top: the surface fills itself)
  function test_backing_on_overlay() {
    compare(BackingRule.backsOn({
      "backing": true,
      "fullscreen": true,
      "onOverlay": true,
      "backingOnOverlay": true
    }), true);
    compare(BackingRule.backsOn({
      "backing": true,
      "fullscreen": true,
      "onOverlay": true,
      "backingOnOverlay": false
    }), false);
    compare(BackingRule.backsOn({
      "backing": true,
      "fullscreen": false,
      "onOverlay": false,
      "backingOnOverlay": false
    }), true);
    compare(BackingRule.backsOn({
      "backing": false,
      "fullscreen": false,
      "onOverlay": true,
      "backingOnOverlay": true
    }), false);
  }
}
