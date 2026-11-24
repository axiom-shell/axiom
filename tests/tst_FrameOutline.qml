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
    compare(FrameOutline.innerPath(spec({}), 160, 100), "M 16 10 L 144 10 A 6 6 0 0 1 150 16 L 150 84 A 6 6 0 0 1 144 90 L 16 90 A 6 6 0 0 1 10 84 L 10 16 A 6 6 0 0 1 16 10 Z");
  }

  // Radius 0 and 1 with stroke 2: the arc's radius is 0 and the formula is clamped
  function test_innerPath_radius_0() {
    compare(FrameOutline.innerPath(spec({
      "innerBorderRadius": 0
    }), 160, 100), "M 10 10 L 150 10 A 0 0 0 0 1 150 10 L 150 90 A 0 0 0 0 1 150 90 L 10 90 A 0 0 0 0 1 10 90 L 10 10 A 0 0 0 0 1 10 10 Z");
  }
  function test_innerPath_radius_1() {
    compare(FrameOutline.innerPath(spec({
      "innerBorderRadius": 1
    }), 160, 100), "M 10 10 L 150 10 A 0 0 0 0 1 150 10 L 150 90 A 0 0 0 0 1 150 90 L 10 90 A 0 0 0 0 1 10 90 L 10 10 A 0 0 0 0 1 10 10 Z");
  }

  // A non-AA Rectangle's stroke on device px (the live 1.25 numbers: the
  // top stroke 7.5..10 fills rows 7, 8, 9; the bottom strip's at device 890
  // fills 890, 891)
  function test_strokePixels() {
    compare(r4(FrameOutline.strokePixels(Qt.rect(0, 6, 1280, 2), Qt.point(0, 0), 1.25)), r4(Qt.rect(0, 7 / 1.25, 1280, 3 / 1.25)));
    compare(r4(FrameOutline.strokePixels(Qt.rect(0, 712, 1280, 2), Qt.point(0, 712), 1.25)), r4(Qt.rect(0, 890 / 1.25, 1280, 2 / 1.25)));
  }
  function test_strokePixels_whole() {
    compare(r4(FrameOutline.strokePixels(Qt.rect(6, 6, 20, 2), Qt.point(0, 0), 1)), [6, 6, 20, 2]);
    compare(r4(FrameOutline.strokePixels(Qt.rect(0, 98, 160, 2), Qt.point(0, 98), 2)), [0, 98, 160, 2]);
  }
  function test_stripStroke() {
    compare(r4(FrameOutline.stripStroke("top", 160, 8, 6, 2)), [14, 6, 132, 2]);
    compare(r4(FrameOutline.stripStroke("bottom", 160, 8, 6, 2)), [14, 0, 132, 2]);
    compare(r4(FrameOutline.stripStroke("left", 84, 8, 6, 2)), [6, 6, 2, 72]);
    compare(r4(FrameOutline.stripStroke("right", 84, 8, 6, 2)), [0, 6, 2, 72]);
  }
  function test_windowPixels() {
    compare(r4(FrameOutline.windowPixels(Qt.rect(6, 6, 8, 8), 1.25)), r4(Qt.rect(8 / 1.25, 8 / 1.25, 10 / 1.25, 10 / 1.25)));
    compare(r4(FrameOutline.windowPixels(Qt.rect(6, 6, 8, 8), 1)), [6, 6, 8, 8]);
  }

  function test_blurRegion() {
    const pieces = FrameOutline.blurRegion(spec({}), 160, 100);
    compare(pieces.length, 1);
    compare(r4(pieces[0]), [0, 0, 160, 100]);
    compare(pieces[0].cuts.length, 1);
    compare(r4(pieces[0].cuts[0]), [10, 10, 140, 80]);
    compare(pieces[0].cuts[0].ellipse, false);
    compare(pieces[0].cuts[0].radius, 6);
  }
  // The cut's radius is innerPath's
  function test_blurRegion_radius_0() {
    compare(FrameOutline.blurRegion(spec({
      "innerBorderRadius": 0
    }), 160, 100)[0].cuts[0].radius, 0);
  }
  function test_blurRegion_radius_1() {
    compare(FrameOutline.blurRegion(spec({
      "innerBorderRadius": 1
    }), 160, 100)[0].cuts[0].radius, 0);
  }
  function test_blurRegion_menus() {
    const pieces = FrameOutline.blurRegion(spec({
      "outerLeft": 4,
      "innerLeft": 14
    }), 160, 100);
    compare(r4(pieces[0]), [4, 0, 156, 100]);
    compare(r4(pieces[0].cuts[0]), [14, 10, 136, 80]);
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
