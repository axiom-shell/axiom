import QtQuick
import QtTest
import qs.components.reusable

// HoledCopy keeps its pieces: as its holes come and go (none, two, one, none,
// two again) every drawing it has built stays built, so a slide that changes
// the hole count rebuilds nothing after the most it has ever needed.
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
    id: drawingComp

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
      drawing: drawingComp
      fillOnly: fillComp
    }
  }

  function test_noRebuildAfterHighWaterMark() {
    root.built = 0;
    root.builtFill = 0;
    const copy = createTemporaryObject(copyComp, root);
    verify(copy);
    const two = [Qt.rect(10, 10, 20, 20), Qt.rect(60, 60, 20, 20)];
    const one = [Qt.rect(10, 10, 20, 20)];
    copy.holes = two;
    wait(0);
    const builtAtMost = root.built, fillAtMost = root.builtFill;
    verify(builtAtMost > 0, "drawn outside the holes");
    verify(fillAtMost > 0, "the fill alone inside them");
    for (const holes of [one, [], two, one, [], one, two]) {
      copy.holes = holes;
      wait(0);
      compare(root.built, builtAtMost, "no drawing rebuilt at " + holes.length + " holes");
      compare(root.builtFill, fillAtMost, "no fill rebuilt at " + holes.length + " holes");
    }
  }
}
