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

  function test_edgeSpot() {
    compare(ScreenEdge.edgeSpot("top", 0.25, 0.1), Qt.point(0.25, 0.1));
    compare(ScreenEdge.edgeSpot("bottom", 0.25, 0.1), Qt.point(0.25, 0.9));
    compare(ScreenEdge.edgeSpot("left", 0.25, 0.1), Qt.point(0.1, 0.25));
    compare(ScreenEdge.edgeSpot("right", 0.25, 0.1), Qt.point(0.9, 0.25));
    compare(ScreenEdge.edgeSpot("", 0.5, 0), Qt.point(0.5, 1), "anything else is the bottom edge");
  }

  function test_spotPlace_nearest() {
    compare(ScreenEdge.spotPlace(0.3, 0.1, "bottom"), {
      "edge": "top",
      "along": 0.3,
      "across": 0.1
    });
    const right = ScreenEdge.spotPlace(0.95, 0.4, "top");
    compare(right.edge, "right");
    compare(right.along, 0.4);
    fuzzyCompare(right.across, 0.05, 1e-9);
    compare(ScreenEdge.spotPlace(0.2, 0.6, "top").edge, "left");
    compare(ScreenEdge.spotPlace(0.5, 0.75, "top").edge, "bottom");
  }

  function test_spotPlace_round_trip() {
    // Spots nearer their own edge than the ends (further in, another
    // edge is nearer)
    for (const edge of ["top", "bottom", "left", "right"])
      for (const [along, across] of [[0.2, 0], [0.5, 0.3], [0.5, 0.45], [0.8, 0.15]]) {
        const spot = ScreenEdge.edgeSpot(edge, along, across);
        const place = ScreenEdge.spotPlace(spot.x, spot.y, edge);
        compare(place.edge, edge, `${edge} ${along} ${across}`);
        fuzzyCompare(place.along, along, 1e-9);
        fuzzyCompare(place.across, across, 1e-9);
      }
  }

  function test_spotPlace_ties_keep_preferred() {
    compare(ScreenEdge.spotPlace(0.5, 0.5, "right").edge, "right", "the middle keeps the current edge");
    compare(ScreenEdge.spotPlace(0.5, 0.5, "left").across, 0.5);
    compare(ScreenEdge.spotPlace(0, 0, "left").edge, "left", "a corner keeps either edge it's on");
    compare(ScreenEdge.spotPlace(0, 0, "bottom").edge, "top", "else the first in order");
    compare(ScreenEdge.spotPlace(0.5, 0.5, undefined).edge, "top");
  }

  function test_spotPlace_clamps() {
    compare(ScreenEdge.spotPlace(-0.5, 1.4, "bottom"), {
      "edge": "bottom",
      "along": 0,
      "across": 0
    });
  }
}
