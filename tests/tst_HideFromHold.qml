import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "HideFromHold"

  readonly property var windows: [
    {
      "id": "a"
    },
    {
      "id": "b"
    },
    {
      "id": "c"
    }
  ]

  function test_shown() {
    compare(HideFromHold.shown(windows, null) === windows, true, "null ids");
    compare(HideFromHold.shown(windows, []) === windows, true, "empty ids");
    compare(HideFromHold.shown(windows, ["x"]) === windows, true, "ids naming no window");
    compare(HideFromHold.shown(windows, ["b"]).map(w => w.id), ["a", "c"], "one hidden, order kept");
    compare(HideFromHold.shown(windows, ["a", "b", "c"]), [], "all hidden");
    compare(HideFromHold.shown([], ["a"]), [], "no windows");
  }
}
