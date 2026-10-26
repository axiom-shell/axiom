import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "ScreenEdge"

  function test_order() {
    compare([ScreenEdge.Top, ScreenEdge.Bottom, ScreenEdge.Left, ScreenEdge.Right], [0, 1, 2, 3], "code indexes arrays by this order");
  }

  function test_name_round_trip() {
    compare(ScreenEdge.name(ScreenEdge.Top), "top");
    compare(ScreenEdge.name(ScreenEdge.Right), "right");
    for (const edge of [ScreenEdge.Top, ScreenEdge.Bottom, ScreenEdge.Left, ScreenEdge.Right])
      compare(ScreenEdge.fromName(ScreenEdge.name(edge)), edge);
    compare(ScreenEdge.fromName("middle"), -1, "an unknown name has no edge");
    compare(ScreenEdge.fromName(undefined), -1);
  }

  function test_opposite() {
    compare(ScreenEdge.opposite(ScreenEdge.Top), ScreenEdge.Bottom);
    compare(ScreenEdge.opposite(ScreenEdge.Bottom), ScreenEdge.Top);
    compare(ScreenEdge.opposite(ScreenEdge.Left), ScreenEdge.Right);
    compare(ScreenEdge.opposite(ScreenEdge.Right), ScreenEdge.Left);
  }

  function test_fromConfig() {
    compare(ScreenEdge.fromConfig("left"), ScreenEdge.Left);
    compare(ScreenEdge.fromConfig("bottom"), ScreenEdge.Bottom);
    compare(ScreenEdge.fromConfig("middle"), ScreenEdge.Top, "anything else is Top");
    compare(ScreenEdge.fromConfig(""), ScreenEdge.Top);
    compare(ScreenEdge.fromConfig(undefined), ScreenEdge.Top);
  }
}
