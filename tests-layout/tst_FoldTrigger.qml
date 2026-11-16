import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.forms
import qs.components.reusable

// A fold's header is a button over the host's whole header band (a Pressable,
// objectName foldTrigger): folded, the whole card in its rounded shape; open,
// down to the body's first row with the bottom corners square; a fold row, its
// row band; an ItemBox's, its padded header. A click anywhere on it toggles,
// but not on a header extra, which takes its own.
TestCase {
  id: root

  name: "FoldTrigger"
  when: windowShown
  visible: true
  width: 600
  height: 700

  Harness {
    id: harness
  }

  Component {
    id: cardComp

    FieldGroup {
      property alias row0: row0
      width: 400
      title: "Card"
      headerExtras: Loader {
        active: root.extraOn
        sourceComponent: StyledIconButton {
          objectName: "extra"
          iconText: "add"
          onClicked: root.extraClicks++
        }
      }

      FormRow {
        id: row0
        first: true
        bodyHeight: Widget.height
      }
    }
  }

  Component {
    id: foldRowComp

    FormColumn {
      property alias fold: fold
      width: 400

      FoldFormRow {
        id: fold
        title: "More"
        open: false
        onToggled: open = !open
      }
    }
  }

  Component {
    id: boxComp

    ItemBox {
      width: 300
      title: "Item"
      foldable: true
      open: true
      onToggled: open = !open

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 20
      }
    }
  }

  property bool extraOn: false
  property int extraClicks: 0

  function findAll(item, pred) {
    const out = [];
    const walk = it => {
      if (pred(it))
        out.push(it);
      for (const child of it.children)
        walk(child);
    };
    walk(item);
    return out;
  }

  function triggerOf(item) {
    const found = findAll(item, it => it.objectName === "foldTrigger");
    compare(found.length, 1, "one fold trigger");
    return found[0];
  }

  function layerOf(trigger) {
    return findAll(trigger, it => it.hovered !== undefined && it.bottomLeftRadius !== undefined)[0];
  }

  function near(a, b, what) {
    verify(Math.abs(a - b) < 1, what + ": " + a + " vs " + b);
  }

  function boundsIn(item, trigger) {
    const at = trigger.mapToItem(item, 0, 0);
    return {
      "x": at.x,
      "y": at.y,
      "w": trigger.width,
      "h": trigger.height
    };
  }

  function test_collapsed_card_is_one_button() {
    harness.configure({});
    root.extraOn = false;
    const card = createTemporaryObject(cardComp, root);
    verify(card);
    card.collapsed = true;
    waitForRendering(card);
    wait(400);
    const trigger = triggerOf(card);
    const b = boundsIn(card, trigger);
    near(b.x, 0, "x");
    near(b.y, 0, "y");
    near(b.w, card.width, "width");
    near(b.h, card.height, "height");
    const layer = layerOf(trigger);
    verify(layer, "its tint");
    compare(layer.bottomLeftRadius, card.radius);
    compare(layer.bottomRightRadius, card.radius);
    mouseMove(card, 3, 3);
    tryVerify(() => trigger.hovered, 1000, "hovered in the card's padding");
    mouseClick(card, 3, 3);
    compare(card.collapsed, false, "a click in the padding toggles");
  }

  function test_open_card_is_a_header_band() {
    harness.configure({});
    root.extraOn = true;
    root.extraClicks = 0;
    const card = createTemporaryObject(cardComp, root);
    verify(card);
    waitForRendering(card);
    wait(400);
    const trigger = triggerOf(card);
    const b = boundsIn(card, trigger);
    near(b.x, 0, "x");
    near(b.y, 0, "y");
    near(b.w, card.width, "spans the card, extras included");
    const rowTop = card.row0.mapToItem(card, 0, 0).y;
    verify(b.h <= rowTop + 0.5 && b.h > rowTop - Style.space3 - 1, "down to the body's first row: " + b.h + " vs " + rowTop);
    const layer = layerOf(trigger);
    compare(layer.bottomLeftRadius, 0);
    compare(layer.bottomRightRadius, 0);
    const extra = findAll(card, it => it.objectName === "extra")[0];
    verify(extra, "the header extra");
    mouseClick(extra);
    compare(root.extraClicks, 1);
    compare(card.collapsed, false, "a click on the extra doesn't toggle");
    root.extraOn = false;
  }

  function test_fold_row_trigger_is_the_row_band() {
    harness.configure({});
    const col = createTemporaryObject(foldRowComp, root);
    verify(col);
    waitForRendering(col);
    wait(50);
    const fold = col.fold;
    const trigger = triggerOf(fold);
    const b = boundsIn(fold, trigger);
    near(b.x, -Style.rowBleed, "x");
    near(b.y, 0, "y");
    near(b.h, fold.height, "height");
  }

  function test_item_box_header_is_a_button() {
    harness.configure({});
    const box = createTemporaryObject(boxComp, root);
    verify(box);
    waitForRendering(box);
    wait(400);
    const trigger = triggerOf(box);
    let b = boundsIn(box, trigger);
    near(b.x, 0, "x");
    near(b.y, 0, "y");
    near(b.w, box.width, "width");
    verify(b.h < box.height, "open: only the header band");
    compare(layerOf(trigger).bottomLeftRadius, 0);
    box.open = false;
    wait(400);
    b = boundsIn(box, trigger);
    near(b.h, box.height, "folded: the whole box");
    compare(layerOf(trigger).bottomLeftRadius, box.radius);
    keyClick(Qt.Key_Tab);
    verify(trigger.activeFocus, "Tab focuses the header");
    keyClick(Qt.Key_Space);
    compare(box.open, true, "Space toggles");
  }
}
