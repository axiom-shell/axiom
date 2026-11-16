import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.forms
import qs.components.reusable

// FormColumn publishes its top row drawn, which a FormRow in it takes for
// `first` (no divider), moving to the next row when the top one hides; a
// SwitchRow flips on a click off its switch.
TestCase {
  id: root

  name: "FormColumn"
  when: windowShown
  visible: true
  width: 400
  height: 400

  Harness {
    id: harness
  }

  Component {
    id: columnComp

    FormColumn {
      property alias row1: row1
      property alias row2: row2
      property alias flip: flip
      property int flips: 0
      width: 300

      FormRow {
        id: row1
        bodyHeight: Widget.height
      }
      FormRow {
        id: row2
        bodyHeight: Widget.height
      }
      SwitchRow {
        id: flip
        label: "Flip"
        checked: false
        onToggled: newValue => parent.flips++
      }
    }
  }

  Component {
    id: cardComp

    FieldGroup {
      property alias row1: row1
      property alias row2: row2
      width: 300
      title: "Card"

      FormRow {
        id: row1
        bodyHeight: Widget.height
      }
      FormRow {
        id: row2
        bodyHeight: Widget.height
      }
    }
  }

  function initTestCase() {
    harness.configure({});
  }

  function test_first_moves_to_the_next_row() {
    const col = createTemporaryObject(columnComp, root);
    verify(col);
    wait(50);
    verify(col.row1.first, "the top row is first");
    verify(!col.row2.first);
    verify(!col.flip.first);
    col.row1.shown = false;
    wait(50);
    verify(!col.row1.first);
    verify(col.row2.first, "the next row is first once the top hides");
    col.row2.shown = false;
    wait(50);
    verify(col.flip.first, "a SwitchRow is a row too");
  }

  function test_card_rows_get_first() {
    const card = createTemporaryObject(cardComp, root);
    verify(card);
    wait(50);
    verify(card.row1.first, "a FieldGroup's top row has no divider");
    verify(!card.row2.first);
  }

  function test_switchRow_click_off_the_switch_flips() {
    const col = createTemporaryObject(columnComp, root);
    verify(col);
    wait(50);
    waitForRendering(col);
    const row = col.flip;
    verify(row.hoverable, "a row that activates something is hoverable");
    // The row's left edge, away from the switch at its right end
    const at = row.mapToItem(root, Style.space2, row.height / 2);
    mouseClick(root, at.x, at.y);
    compare(col.flips, 1, "a click off the switch flipped it");
  }

  function test_switchRow_unavailable_is_greyed_and_off_only() {
    const col = createTemporaryObject(columnComp, root);
    verify(col);
    col.flip.unavailableReason = "Not here";
    compare(col.flip.opacity, Style.opacityDisabled);
    verify(!col.flip.enabled, "off and unavailable: can't be switched");
    col.flip.checked = true;
    verify(col.flip.enabled, "on: can still be turned off");
  }
}
