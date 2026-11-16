import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.views.base

// InspectorCard: `scrolls: false` builds no CardScroll, the children fill the
// body; scrolling (the default) puts them in one.
TestCase {
  id: root

  name: "InspectorCard"
  when: windowShown
  visible: true
  width: 500
  height: 400

  Harness {
    id: harness
  }

  Component {
    id: cardComp

    InspectorCard {
      width: 400
      height: 300

      Rectangle {
        objectName: "fill"
        Layout.fillWidth: true
        Layout.fillHeight: true
      }
    }
  }

  function initTestCase() {
    harness.configure({});
  }

  function walk(item, test, out) {
    if (test(item))
      out.push(item);
    for (const child of item.children)
      root.walk(child, test, out);
    return out;
  }

  function scrollsIn(card) {
    return root.walk(card, it => it.flickable !== undefined && it.body !== undefined, []);
  }

  function test_plain_body_fills_without_a_scroll() {
    const card = createTemporaryObject(cardComp, root, {
      "scrolls": false
    });
    verify(card);
    wait(50);
    compare(root.scrollsIn(card).length, 0, "no CardScroll built");
    const fill = root.walk(card, it => it.objectName === "fill", [])[0];
    verify(fill);
    compare(fill.width, card.width - Widget.padding * 2, "fills the body's width");
    verify(fill.height > 100, "fills the rest");
  }

  function test_scrolling_body_sits_in_a_scroll() {
    const card = createTemporaryObject(cardComp, root);
    verify(card);
    wait(50);
    compare(root.scrollsIn(card).length, 1);
    const fill = root.walk(card, it => it.objectName === "fill", [])[0];
    verify(fill);
    verify(fill.width > 100);
  }
}
