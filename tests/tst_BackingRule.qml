import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "BackingRule"

  function test_backingOn_truth_table() {
    for (let i = 0; i < 8; i++) {
      const o = {
        "translucent": (i & 1) !== 0,
        "opaque": (i & 2) !== 0,
        "ready": (i & 4) !== 0
      };
      compare(BackingRule.backingOn(o), o.translucent && !o.opaque && o.ready, JSON.stringify(o));
    }
  }

  function test_backingOn_blur_off_is_backed() {
    verify(BackingRule.backingOn({
      "translucent": true,
      "opaque": false,
      "ready": true
    }), "see-through chrome is backed whatever the blur does");
  }

  function test_backsOn_truth_table() {
    for (let i = 0; i < 8; i++) {
      const o = {
        "backing": (i & 1) !== 0,
        "fullscreen": (i & 2) !== 0,
        "onOverlay": (i & 4) !== 0
      };
      compare(BackingRule.backsOn(o), o.backing && (o.onOverlay || !o.fullscreen), JSON.stringify(o));
    }
  }
}
