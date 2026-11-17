import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.views.base

// ListSection: a collapsible header is a Tab stop that Space folds, and the
// hint folds with the rows.
TestCase {
  id: root

  name: "ListSection"
  when: windowShown
  visible: true
  width: 500
  height: 400

  Harness {
    id: harness
  }

  Component {
    id: sectionComp

    ListSection {
      property int toggles: 0
      width: 400
      title: "Section"
      hint: "A hint"
      collapsible: true
      onToggled: toggles++

      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 20
      }
    }
  }

  function initTestCase() {
    harness.configure({});
  }

  function hintOf(section) {
    const walk = it => {
      if (it.text === "A hint")
        return it;
      for (const child of it.children) {
        const found = walk(child);
        if (found)
          return found;
      }
      return null;
    };
    return walk(section);
  }

  function test_space_on_the_header_toggles() {
    const section = createTemporaryObject(sectionComp, root);
    verify(section);
    waitForRendering(section);
    keyClick(Qt.Key_Tab);
    keyClick(Qt.Key_Space);
    compare(section.toggles, 1, "Tab reaches the header, Space emits toggled");
  }

  function test_folded_hides_the_hint() {
    const section = createTemporaryObject(sectionComp, root);
    verify(section);
    verify(root.hintOf(section).visible, "shown while open");
    section.open = false;
    verify(!root.hintOf(section).visible, "hidden while folded");
  }
}
