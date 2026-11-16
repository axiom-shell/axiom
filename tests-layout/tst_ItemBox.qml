import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.forms
import qs.components.reusable

// ItemBox, a sunken box inside a card: padded Widget.padding all round, or a
// dense one-line item Widget.padding left and right and Widget.smallPadding
// above and below; a title makes a header with a remove button; a folded one
// hides its body.
TestCase {
  id: root

  name: "ItemBox"
  when: windowShown
  visible: true
  width: 500
  height: 500

  Harness {
    id: harness
  }

  Component {
    id: boxComp

    ItemBox {
      width: 300

      Rectangle {
        objectName: "fill"
        Layout.fillWidth: true
        Layout.preferredHeight: 20
      }
    }
  }

  Component {
    id: rowsComp

    ItemBox {
      property alias rowA: rowTop
      property alias rowB: rowNext
      width: 300

      FormRow {
        id: rowTop
        bodyHeight: Widget.height
      }
      FormRow {
        id: rowNext
        bodyHeight: Widget.height
      }
    }
  }

  function findByName(item, name) {
    if (item.objectName === name)
      return item;
    for (const c of item.children) {
      const hit = findByName(c, name);
      if (hit)
        return hit;
    }
    return null;
  }

  function test_paddings_dense_and_not() {
    for (const scale of [80, 100, 150]) {
      harness.configure({
        "scale": scale
      });
      const box = createTemporaryObject(boxComp, root);
      const fill = findByName(box, "fill");
      const at = fill.mapToItem(box, 0, 0);
      compare(at.x, Widget.padding, "scale " + scale + ": left");
      compare(at.y, Widget.padding, "scale " + scale + ": top");
      compare(box.implicitHeight, 20 + Widget.padding * 2, "scale " + scale + ": height");
      box.dense = true;
      const dense = fill.mapToItem(box, 0, 0);
      compare(dense.x, Widget.padding, "scale " + scale + ": dense left");
      compare(dense.y, Widget.smallPadding, "scale " + scale + ": dense top");
      compare(box.implicitHeight, 20 + Widget.smallPadding * 2, "scale " + scale + ": dense height");
    }
  }

  function test_first_row_is_the_first_that_draws() {
    harness.configure({});
    const box = createTemporaryObject(boxComp, root);
    const rows = createTemporaryObject(rowsComp, root);
    verify(rows);
    wait(50);
    verify(rows.rowA.first, "the top row has no divider");
    verify(!rows.rowB.first);
    rows.rowA.shown = false;
    wait(50);
    verify(!rows.rowA.first);
    verify(rows.rowB.first, "the second row is first once the top hides");
  }

  function test_header_remove() {
    harness.configure({});
    const box = createTemporaryObject(boxComp, root, {
      "title": "Item",
      "removable": true
    });
    let removed = 0;
    box.remove.connect(() => removed++);
    verify(box.hasHeader);
    const buttons = [];
    const walk = it => {
      if (it.visible && it.iconText === "close")
        buttons.push(it);
      for (const c of it.children)
        walk(c);
    };
    walk(box);
    compare(buttons.length, 1, "one close button");
    compare(buttons[0].width, Widget.compactHeight);
    mouseClick(buttons[0]);
    compare(removed, 1);
    box.removable = false;
    buttons.length = 0;
    walk(box);
    compare(buttons.length, 0, "no button when not removable");
  }

  function test_fold_hides_the_body() {
    harness.configure({});
    const box = createTemporaryObject(boxComp, root, {
      "title": "Item",
      "foldable": true,
      "open": true,
      "summary": "One line"
    });
    const open = box.implicitHeight;
    let toggled = 0;
    box.toggled.connect(() => toggled++);
    box.open = false;
    tryVerify(() => box.implicitHeight < open);
    mouseClick(box, box.width / 2, Widget.padding + 2);
    compare(toggled, 1, "a header click asks the host to flip it");
  }
}
