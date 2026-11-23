import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "FrameOutline"

  // A 160 x 100 screen, a 10 px border (inner side 10 px in), radius 8,
  // stroke 2
  function spec(extra) {
    return Object.assign({
      "width": 160,
      "height": 100,
      "outerLeft": 0,
      "outerTop": 0,
      "outerRight": 0,
      "outerBottom": 0,
      "innerLeft": 10,
      "innerTop": 10,
      "innerRight": 10,
      "innerBottom": 10,
      "innerBorderRadius": 8,
      "strokeWidth": 2
    }, extra);
  }

  // A rect as [x, y, width, height], as compare() doesn't compare objects
  // by value
  function r4(r) {
    return [r.x, r.y, r.width, r.height].map(v => Math.round(v * 100) / 100);
  }

  function test_cornerSize() {
    compare(FrameOutline.cornerSize(spec({})), 10);
  }

  function test_innerPath() {
    compare(FrameOutline.innerPath(spec({}), 160, 100, 1), "M 16 9 L 144 9 A 7 7 0 0 1 151 16 L 151 84 A 7 7 0 0 1 144 91 L 16 91 A 7 7 0 0 1 9 84 L 9 16 A 7 7 0 0 1 16 9 Z");
  }

  // Radius 0 and 1 with stroke 2: the arc's radius is 0 at the stroke's
  // outer side (R45)
  function test_innerPath_radius_0() {
    compare(FrameOutline.innerPath(spec({
      "innerBorderRadius": 0
    }), 160, 100, 1), "M 9 9 L 151 9 A 0 0 0 0 1 151 9 L 151 91 A 0 0 0 0 1 151 91 L 9 91 A 0 0 0 0 1 9 91 L 9 9 A 0 0 0 0 1 9 9 Z");
  }
  function test_innerPath_radius_1() {
    compare(FrameOutline.innerPath(spec({
      "innerBorderRadius": 1
    }), 160, 100, 1), "M 9 9 L 151 9 A 0 0 0 0 1 151 9 L 151 91 A 0 0 0 0 1 151 91 L 9 91 A 0 0 0 0 1 9 91 L 9 9 A 0 0 0 0 1 9 9 Z");
  }

  function test_cornerBox() {
    compare(r4(FrameOutline.cornerBox(spec({}), true, true)), [8, 8, 10, 10]);
    compare(r4(FrameOutline.cornerBox(spec({}), false, false)), [142, 82, 10, 10]);
  }

  function test_strokeHoles_uncovered() {
    const openings = [
      {
        "edge": "top",
        "start": 14,
        "end": 60
      }
    ];
    compare(FrameOutline.strokeHoles(spec({}), openings).map(r => r4(r)), [[14, 7, 46, 1], [18, 8, 42, 3]]);
    verify(!FrameOutline.cornerCovered(spec({}), openings, true, true));
  }

  function test_strokeHoles_covered() {
    const openings = [
      {
        "edge": "top",
        "start": 8,
        "end": 60
      }
    ];
    compare(FrameOutline.strokeHoles(spec({}), openings).map(r => r4(r)), [[8, 7, 52, 1], [18, 8, 42, 3], [8, 8, 10, 10]]);
    verify(FrameOutline.cornerCovered(spec({}), openings, true, true));
  }
}
