import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.reusable

// FactGrid with a `labelWidth`: a long label wraps in that width instead of
// eliding.
TestCase {
  id: root

  name: "FactGrid"
  when: windowShown
  visible: true
  width: 400
  height: 300

  Harness {
    id: harness
  }

  Component {
    id: gridComp

    FactGrid {
      width: 300
      monoLabels: true
      labelWidth: 80
      facts: [
        {
          "label": "a long key and another long key",
          "value": "v"
        }
      ]
    }
  }

  function initTestCase() {
    harness.configure({});
  }

  function test_labels_wrap_at_labelWidth() {
    const grid = createTemporaryObject(gridComp, root);
    verify(grid);
    wait(50);
    const label = grid.children.find(c => c.text === "a long key and another long key");
    verify(label, "the label cell");
    verify(label.width <= 80, "within labelWidth: " + label.width);
    verify(label.lineCount > 1, "wrapped");
    verify(!label.truncated, "not elided");
  }
}
