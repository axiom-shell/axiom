import QtQuick
import QtTest
import qs.components.reusable

// HoledCopy keeps its pieces: its fill is built once, and as its holes come
// and go (none, two, one, none, two again) every stroke it has built stays
// built, so a slide that changes the hole count rebuilds nothing after the
// most it has ever needed.
TestCase {
  id: root

  name: "HoledCopy"
  when: windowShown
  visible: true
  width: 400
  height: 400

  property int built: 0
  property int builtFill: 0

  Component {
    id: strokeComp

    Rectangle {
      color: "red"
      Component.onCompleted: root.built++
    }
  }

  Component {
    id: fillComp

    Rectangle {
      color: "blue"
      Component.onCompleted: root.builtFill++
    }
  }

  Component {
    id: copyComp

    HoledCopy {
      width: 100
      height: 100
      fillOnly: fillComp
      strokeOnly: strokeComp
    }
  }

  function test_no_rebuild_after_high_water_mark() {
    root.built = 0;
    root.builtFill = 0;
    const copy = createTemporaryObject(copyComp, root);
    verify(copy);
    const two = [Qt.rect(10, 10, 20, 20), Qt.rect(60, 60, 20, 20)];
    const one = [Qt.rect(10, 10, 20, 20)];
    copy.holes = two;
    wait(0);
    const builtAtMost = root.built, fillAtMost = root.builtFill;
    verify(builtAtMost > 0, "stroke drawn outside the holes");
    compare(fillAtMost, 1, "the fill built once, whole");
    for (const holes of [one, [], two, one, [], one, two]) {
      copy.holes = holes;
      wait(0);
      compare(root.built, builtAtMost, "no stroke rebuilt at " + holes.length + " holes");
      compare(root.builtFill, fillAtMost, "no fill rebuilt at " + holes.length + " holes");
    }
  }

  // Created with two holes, the first change to one and back to two builds
  // no stroke: the slots it began with are kept
  function test_no_rebuild_after_created_with_holes() {
    const two = [Qt.rect(10, 10, 20, 20), Qt.rect(60, 60, 20, 20)];
    const one = [Qt.rect(10, 10, 20, 20)];
    const copy = createTemporaryObject(copyComp, root, {
      "holes": two
    });
    verify(copy);
    wait(0);
    root.built = 0;
    copy.holes = one;
    wait(0);
    copy.holes = two;
    wait(0);
    compare(root.built, 0, "no stroke rebuilt");
  }
}
