import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "BarGradient"

  function same(actual, expected, message) {
    verify(Qt.colorEqual(actual, expected), `${message}: ${actual} != ${expected}`);
  }

  // Where a part's middle sits along the bar: a widget's (its own start
  // on the bar, its length), a point in it (no length), a run's middle
  function test_spot() {
    compare(BarGradient.spot(0, 100, 200, 1000), 0.25, "a widget's middle");
    compare(BarGradient.spot(30, 0, 200, 1000), 0.23, "a point in it");
    compare(BarGradient.spot(0, 0, 0, 1000), 0, "the bar's start");
    compare(BarGradient.spot(0, 100, 200, 0), -1, "no bar to measure against");
  }

  function test_gradient_at_spreads_the_stops_evenly() {
    same(BarGradient.gradientAt(["#000000", "#ffffff"], 0), "#000000", "start");
    same(BarGradient.gradientAt(["#000000", "#ffffff"], 1), "#ffffff", "end");
    same(BarGradient.gradientAt(["#ff0000", "#00ff00", "#0000ff"], 0.5), "#00ff00", "via at the middle");
    same(BarGradient.gradientAt(["#ff0000", "#00ff00", "#0000ff"], 0.25), Qt.rgba(0.5, 0.5, 0, 1), "a quarter");
    same(BarGradient.gradientAt(["#000000", "#ffffff"], 2), "#ffffff", "clamped");
  }

  function test_gradient_slice_is_the_bars_between_its_ends() {
    const two = BarGradient.gradientSlice(["#000000", "#ffffff"], 0.25, 0.75, 1);
    compare(two.map(s => s.position), [0, 0.5, 1]);
    same(two[0].color, Qt.rgba(0.25, 0.25, 0.25, 1), "start");
    same(two[1].color, Qt.rgba(0.5, 0.5, 0.5, 1), "middle");
    same(two[2].color, Qt.rgba(0.75, 0.75, 0.75, 1), "end");
    // The via stop inside it is a stop of the slice
    const three = BarGradient.gradientSlice(["#ff0000", "#00ff00", "#0000ff"], 0.4, 0.8, 1);
    fuzzyCompare(three[1].position, 0.25, 1e-9);
    same(three[1].color, "#00ff00", "via");
    // Faded for a tint
    compare(BarGradient.gradientSlice(["#000000", "#ffffff"], 0, 1, 0.25)[2].color.a, 0.25);
  }
}
