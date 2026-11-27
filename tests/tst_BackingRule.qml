import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "BackingRule"

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
