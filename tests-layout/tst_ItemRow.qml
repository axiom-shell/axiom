import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.reusable
import qs.components.content.parts

// ItemRow: its actions show while the row is hovered or one of them has
// keyboard focus, and stay out of reach otherwise.
TestCase {
  id: root

  name: "ItemRow"
  when: windowShown
  visible: true
  width: 400
  height: 200

  Harness {
    id: harness
  }

  Component {
    id: rowComp

    ItemRow {
      width: 360
      title: "Entry"

      StyledIconButton {
        objectName: "action"
        iconText: "delete"
      }
    }
  }

  function initTestCase() {
    harness.configure({});
  }

  function test_actionsHiddenUntilFocused() {
    const row = createTemporaryObject(rowComp, root);
    verify(row);
    const action = findChild(row, "action");
    verify(action);
    verify(!row.revealed, "nothing hovered or focused");
    compare(action.parent.opacity, 0);
    action.forceActiveFocus();
    verify(row.revealed, "a focused action reveals the row's actions");
    tryCompare(action.parent, "opacity", 1);
    action.focus = false;
    root.forceActiveFocus();
    verify(!row.revealed);
  }
}
