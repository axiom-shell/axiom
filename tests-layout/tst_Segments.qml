import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.reusable
import qs.components.methods

// The choice controls (the layout harness): a SegmentRow and a StyledToggle are
// one Tab stop that Left, Right and Space drive, the text buttons are Tab
// stops in order, a chip shows its check when on, the entry tabs are
// default-height buttons showing their label whole.
TestCase {
  id: root

  name: "Segments"
  when: windowShown
  visible: true
  width: 700
  height: 500

  Harness {
    id: harness
  }

  Component {
    id: toggleComp

    StyledToggle {
      options: ["a", "b", "c"]
      labels: ({
          "a": "A",
          "b": "B",
          "c": "C"
        })
      value: "a"
      onPicked: v => value = v
    }
  }

  Component {
    id: pairComp

    StyledToggle {
      options: ["a", "b"]
      labels: ({
          "a": "A",
          "b": "B"
        })
      value: "a"
      onPicked: v => value = v
    }
  }

  Component {
    id: rowComp

    SegmentRow {
      property string chosen: "x"

      SegmentButton {
        text: "X"
        active: parent.parent.chosen === "x"
        onClicked: parent.parent.chosen = "x"
      }
      SegmentButton {
        text: "Y"
        available: false
        active: parent.parent.chosen === "y"
        onClicked: parent.parent.chosen = "y"
      }
      SegmentButton {
        text: "Z"
        active: parent.parent.chosen === "z"
        onClicked: parent.parent.chosen = "z"
      }
    }
  }

  Component {
    id: buttonsComp

    RowLayout {
      property alias first: one
      property alias second: two
      property alias third: three

      StyledTextButton {
        id: one
        text: "One"
      }
      StyledTextButton {
        id: two
        text: "Two"
      }
      StyledTextButton {
        id: three
        text: "Three"
      }
    }
  }

  Component {
    id: chipComp

    ToggleChip {
      text: "chip"
      iconText: "star"
    }
  }

  Component {
    id: tabsComp

    SegmentTabs {
      count: 3
      labelAt: i => ["first", "second", "third"][i]
    }
  }

  // Tab reaches the toggle once; Left and Right step, never past the ends
  function test_toggle_is_one_tab_stop_and_steps() {
    harness.configure({});
    const toggle = createTemporaryObject(toggleComp, root);
    waitForRendering(toggle);
    verify(toggle.activeFocusOnTab);
    keyClick(Qt.Key_Tab);
    verify(toggle.activeFocus, "Tab focuses the toggle");
    keyClick(Qt.Key_Right);
    compare(toggle.value, "b");
    keyClick(Qt.Key_Right);
    keyClick(Qt.Key_Right);
    compare(toggle.value, "c");
    keyClick(Qt.Key_Left);
    compare(toggle.value, "b");
    const buttons = findAll(toggle, it => it instanceof SegmentButton);
    compare(buttons.length, 3);
    for (const b of buttons)
      verify(!b.tabStop, "the segments are not stops of their own");
  }

  // Space flips two options, and does nothing for three
  function test_toggle_space_flips_two() {
    harness.configure({});
    const pair = createTemporaryObject(pairComp, root);
    waitForRendering(pair);
    keyClick(Qt.Key_Tab);
    keyClick(Qt.Key_Space);
    compare(pair.value, "b");
    keyClick(Qt.Key_Space);
    compare(pair.value, "a");
    const three = createTemporaryObject(toggleComp, root);
    waitForRendering(three);
    three.forceActiveFocus();
    keyClick(Qt.Key_Space);
    compare(three.value, "a");
  }

  // A segment row skips a button that can't be chosen
  function test_segment_row_skips_unavailable() {
    harness.configure({});
    const row = createTemporaryObject(rowComp, root);
    waitForRendering(row);
    row.forceActiveFocus();
    keyClick(Qt.Key_Right);
    compare(row.chosen, "z");
    keyClick(Qt.Key_Left);
    compare(row.chosen, "x");
  }

  // Text buttons are Tab stops in order, and Space and Enter click the focused one
  function test_text_buttons_tab_in_order() {
    harness.configure({});
    const row = createTemporaryObject(buttonsComp, root);
    waitForRendering(row);
    const clicks = [];
    row.second.clicked.connect(() => clicks.push("two"));
    keyClick(Qt.Key_Tab);
    const stops = [row.first, row.second, row.third];
    const focused = () => stops.findIndex(b => b.Window.window.activeFocusItem && b.Window.window.activeFocusItem.parent === b);
    compare(focused(), 0);
    keyClick(Qt.Key_Tab);
    compare(focused(), 1);
    keyClick(Qt.Key_Space);
    keyClick(Qt.Key_Return);
    compare(clicks.length, 2);
    keyClick(Qt.Key_Tab);
    compare(focused(), 2);
  }

  // The chip shows the check only while on, and its own icon either way
  function test_chip_check_when_on() {
    harness.configure({});
    const chip = createTemporaryObject(chipComp, root);
    waitForRendering(chip);
    const glyphs = () => findAll(chip, it => it.text !== undefined && it.visible && it.size !== undefined).map(it => it.text);
    compare(glyphs(), ["star"]);
    chip.checked = true;
    compare(glyphs(), ["check", "star"]);
    const toggles = [];
    chip.toggled.connect(() => toggles.push(1));
    keyClick(Qt.Key_Tab);
    keyClick(Qt.Key_Space);
    compare(toggles.length, 1);
  }

  // The entry tabs are default-height segment buttons (not shortened) showing their label whole
  function test_entry_tabs_default_height() {
    const tabs = createTemporaryObject(tabsComp, root, {
      "width": 400
    });
    waitForRendering(tabs);
    const buttons = Array.prototype.filter.call(tabs.children, c => c instanceof SegmentButton);
    compare(buttons.length, 3);
    for (const b of buttons) {
      verify(b.height >= Widget.height, `tab ${b.text} is ${b.height}, under ${Widget.height}`);
      compare(b.height, buttons[0].height);
    }
    for (const t of harness.texts(tabs))
      verify(!t.truncated, `"${t.text}" is elided`);
  }

  // A right click on a tab asks for its menu, with the tab's index
  function test_tab_right_click_requests_menu() {
    const tabs = createTemporaryObject(tabsComp, root, {
      "width": 400,
      "menus": true
    });
    waitForRendering(tabs);
    const asked = [];
    tabs.menuRequested.connect((i, item) => asked.push(i));
    const second = Array.prototype.filter.call(tabs.children, c => c instanceof SegmentButton)[1];
    mouseClick(second, second.width / 2, second.height / 2, Qt.RightButton);
    compare(asked, [1]);
    tabs.menus = false;
    mouseClick(second, second.width / 2, second.height / 2, Qt.RightButton);
    compare(asked, [1], "no menus: a right click isn't taken");
  }

  function findAll(item, match) {
    const found = [];
    const walk = it => {
      if (match(it))
        found.push(it);
      for (const child of it.children)
        walk(child);
    };
    walk(item);
    return found;
  }
}
