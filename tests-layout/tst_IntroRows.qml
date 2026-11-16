import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.forms
import qs.components.reusable

// What the settings intros are built from: an IntroColumn spaces its lines
// the one way, and a switch line in it (a SwitchRow in a FormColumn) is the
// top row of its own column, so it draws no divider; a StatusLine carries a
// chip, its text and its buttons; a ConfirmLine answers with Keep and the
// confirm button.
TestCase {
  id: root

  name: "IntroRows"
  when: windowShown
  visible: true
  width: 500
  height: 400

  Harness {
    id: harness
  }

  Component {
    id: introComp

    IntroColumn {
      property alias line: line
      property alias flip: flip
      property alias ask: ask
      property int flips: 0
      property int confirms: 0
      property int keeps: 0
      width: 400

      StatusLine {
        id: line
        text: "Status words"
        chip: "On"
        chipTone: "success"
        Layout.fillWidth: true

        StyledTextButton {
          text: "Act"
        }
      }

      FormColumn {
        Layout.fillWidth: true

        SwitchRow {
          id: flip
          label: "Flip"
          onToggled: newValue => parent.parent.flips++
        }
      }

      ConfirmLine {
        id: ask
        question: "Sure?"
        confirmText: "Yes"
        Layout.fillWidth: true
        onConfirmed: parent.confirms++
        onKept: parent.keeps++
      }
    }
  }

  function initTestCase() {
    harness.configure({});
  }

  function test_intro_spacing_is_fixed() {
    const intro = createTemporaryObject(introComp, root);
    verify(intro);
    compare(intro.spacing, Widget.spacing);
  }

  function test_switch_line_in_an_intro_is_a_top_row() {
    const intro = createTemporaryObject(introComp, root);
    verify(intro);
    wait(50);
    verify(intro.flip.first, "its own column's first row: no divider");
  }

  function test_status_line_holds_chip_text_and_action() {
    const intro = createTemporaryObject(introComp, root);
    verify(intro);
    wait(50);
    verify(intro.line.width > 0);
    compare(intro.line.chip, "On");
    verify(intro.line.implicitHeight >= Widget.smallHeight);
  }

  function test_confirm_line_answers() {
    const intro = createTemporaryObject(introComp, root);
    verify(intro);
    wait(50);
    intro.ask.confirmed();
    intro.ask.kept();
    compare(intro.confirms, 1);
    compare(intro.keeps, 1);
  }
}
