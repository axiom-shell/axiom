import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.forms
import qs.components.reusable

// PickedChips in both add modes: the picks as chips (a click takes one away,
// a value no longer in the options still shows), "inline" listing the others
// under their group's header (a click adds one at the end), "picker" one
// button opening a TypePickerPopup of the others; `ordered` drags the chips
// into place.
TestCase {
  id: root

  name: "PickedChips"
  when: windowShown
  visible: true
  width: 500
  height: 600

  Harness {
    id: harness
  }

  Component {
    id: chipsComp

    PickedChips {
      id: chips
      property var out: []
      width: 400
      label: "Picks"
      value: ["b"]
      options: ["a", "b", "c", "d"]
      labels: ({
          "a": "Alpha",
          "b": "Bravo",
          "c": "Charlie",
          "d": "Delta"
        })
      groups: ({
          "a": "First",
          "b": "First",
          "c": "Second",
          "d": "Second"
        })
      addText: "Add one"
      onEdited: value => chips.out.push(value)
    }
  }

  function findAll(item, test) {
    const out = [];
    const walk = it => {
      if (test(it))
        out.push(it);
      for (const child of it.children)
        walk(child);
    };
    walk(item);
    return out;
  }

  function chipsOf(item) {
    return root.findAll(item, it => it.payload !== undefined && it.label !== undefined && it.dragLayer !== undefined);
  }

  function addButtons(item) {
    return root.findAll(item, it => it.visible && it.kind === "outlined" && it.iconText !== undefined && it.text !== "");
  }

  function init() {
    harness.configure({});
  }

  function test_inline_chips_and_add() {
    const chips = createTemporaryObject(chipsComp, root);
    verify(chips);
    wait(50);
    compare(root.chipsOf(chips).map(c => c.label), ["Bravo"]);
    compare(root.addButtons(chips).map(b => b.text), ["Alpha", "Charlie", "Delta"], "the others, outlined chips");
    root.addButtons(chips)[1].clicked();
    compare(chips.out[0], ["b", "c"]);
    root.chipsOf(chips)[0].clicked();
    compare(chips.out[1], []);
  }

  function test_inline_empty_says_so() {
    const chips = createTemporaryObject(chipsComp, root, {
      "value": []
    });
    verify(chips);
    wait(50);
    compare(root.chipsOf(chips).length, 0);
    verify(root.findAll(chips, it => it.visible && it.text === "None chosen. Add some from below.").length === 1);
  }

  function test_a_value_outside_the_options_shows_and_goes() {
    const chips = createTemporaryObject(chipsComp, root, {
      "value": ["gone", "a"]
    });
    verify(chips);
    wait(50);
    compare(root.chipsOf(chips).map(c => c.label), ["gone", "Alpha"]);
    root.chipsOf(chips)[0].clicked();
    compare(chips.out[0], ["a"]);
  }

  // Dragging is only for `ordered`: a chip carries a payload then
  function test_ordered_drags() {
    const plain = createTemporaryObject(chipsComp, root, {
      "value": ["a", "b", "c"]
    });
    verify(plain);
    wait(50);
    verify(root.chipsOf(plain).every(c => c.payload === null), "no drag without ordered");
    const chips = createTemporaryObject(chipsComp, root, {
      "ordered": true,
      "value": ["a", "b", "c"]
    });
    verify(chips);
    wait(50);
    verify(root.chipsOf(chips).every(c => c.payload !== null));
    const layer = root.findAll(chips, it => it.registerTarget !== undefined)[0];
    verify(layer);
    // The first dropped before the end
    layer.dropped({
      "index": 0
    }, layer.targets?.[0] ?? null, 3);
    compare(chips.out[0], ["b", "c", "a"]);
    // The last dropped before the first
    layer.dropped({
      "index": 2
    }, null, 0);
    compare(chips.out[1], ["c", "a", "b"]);
  }

  function test_picker_mode() {
    const chips = createTemporaryObject(chipsComp, root, {
      "addMode": "picker"
    });
    verify(chips);
    wait(50);
    compare(root.chipsOf(chips).map(c => c.label), ["Bravo"]);
    compare(chips._types.map(t => t.type), ["a", "c", "d"], "the picker offers the others");
    compare(chips._types.map(t => t.label), ["Alpha", "Charlie", "Delta"]);
    const buttons = root.addButtons(chips);
    compare(buttons.length, 1, "one add button, no inline list");
    compare(buttons[0].text, "Add one");
    compare(buttons[0].enabled, true);
    const picker = chips.data.filter(o => o.typeSelected !== undefined)[0];
    verify(picker);
    picker.typeSelected("d");
    compare(chips.out[0], ["b", "d"]);
    // Nothing left to pick: the button is off
    chips.value = ["a", "b", "c", "d"];
    compare(buttons[0].enabled, false);
  }

  // Ids show as they are, not translated or looked up on the prototype
  function test_ids_show_as_they_are() {
    const chips = createTemporaryObject(chipsComp, root, {
      "value": ["constructor", "b1"],
      "options": [],
      "labels": ({}),
      "icons": ({}),
      "groups": ({})
    });
    verify(chips);
    waitForRendering(chips);
    compare(chips.labelOf("constructor"), "constructor");
    compare(chips.labelOf("b1"), "b1");
    compare(chips.iconOf("constructor"), "");
    compare(chips.iconOf("b1"), "");
    const found = findAll(chips, it => it.label !== undefined && it.dragLayer !== undefined);
    compare(found.map(c => c.label), ["constructor", "b1"]);
    compare(found.map(c => c.icon), ["", ""]);
  }
}
