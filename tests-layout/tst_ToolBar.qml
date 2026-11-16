import QtQuick
import QtTest
import qs.config
import qs.components.views.base

// ToolBar's count caption: the bare number, or "count of total" while a
// search or chips narrow the list under its `total`.
TestCase {
  id: root

  name: "ToolBar"
  when: windowShown
  visible: true
  width: 800
  height: 200

  Harness {
    id: harness
  }

  Component {
    id: barComp

    ToolBar {
      width: 700
    }
  }

  function initTestCase() {
    harness.configure({});
  }

  function captions(bar) {
    return harness.texts(bar, false).map(t => t.text);
  }

  function test_count_caption() {
    const bar = createTemporaryObject(barComp, root, {
      "count": 3
    });
    verify(root.captions(bar).includes("3"), "no total: the bare count");
    bar.total = 10;
    verify(root.captions(bar).includes("3 of 10"), "narrowed: count of total");
    bar.count = 10;
    verify(root.captions(bar).includes("10"), "nothing hidden: the bare count");
  }
}
