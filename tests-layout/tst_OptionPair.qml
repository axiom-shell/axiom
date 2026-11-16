import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.surfaces.onboarding.pages

// OptionPair: two OptionCards in equal halves, each as tall as the taller
// (the onboarding's System page choices). A plain RowLayout of the same two
// cards leaves the short one short: the control case.
TestCase {
  id: root

  name: "OptionPair"
  when: windowShown
  visible: true
  width: 520
  height: 400

  Harness {
    id: harness
  }

  Component {
    id: pairComp

    OptionPair {
      width: 480

      OptionCard {
        title: "Short"
        description: "One line."
      }

      OptionCard {
        title: "Long"
        description: "A much longer description that wraps over several lines in a half-width card, so this card is taller."
      }
    }
  }

  Component {
    id: plainComp

    RowLayout {
      width: 480

      OptionCard {
        title: "Short"
        description: "One line."
      }

      OptionCard {
        title: "Long"
        description: "A much longer description that wraps over several lines in a half-width card, so this card is taller."
      }
    }
  }

  function initTestCase() {
    harness.configure({});
  }

  function test_equalHalvesAndHeights() {
    const pair = createTemporaryObject(pairComp, root);
    verify(pair);
    wait(100);
    const a = pair.children[0];
    const b = pair.children[1];
    compare(a.width, b.width);
    compare(a.height, b.height);
    compare(a.height, pair.height);
    verify(b.implicitHeight > a.implicitHeight, "the long card is the taller");
    compare(a.height, b.implicitHeight);
  }

  function test_plainRowLeavesTheShortOneShort() {
    const row = createTemporaryObject(plainComp, root);
    verify(row);
    wait(100);
    verify(row.children[0].height < row.children[1].height, "without OptionPair the cards differ in height");
  }
}
