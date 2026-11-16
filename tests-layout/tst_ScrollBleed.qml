import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.reusable
import qs.components.forms

// A scroll view holding FormRows with `bleed: Style.rowBleed` and matching
// negative margins: the rows keep the full width and their tint stays in the view.
TestCase {
  id: root

  name: "ScrollBleed"
  when: windowShown
  visible: true
  width: 500
  height: 400

  Harness {
    id: harness
  }

  Component {
    id: pageComp

    ColumnLayout {
      id: page

      property bool bar: false
      property alias scroll: scroll
      property alias row: row

      width: 400
      height: 300
      spacing: 0

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 20
      }

      StyledScrollView {
        id: scroll

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: -Style.rowBleed
        Layout.rightMargin: -Style.rowBleed
        bleed: Style.rowBleed
        contentPadding: 0
        showScrollBar: page.bar

        ColumnLayout {
          width: scroll.availableWidth

          FormRow {
            id: row

            Layout.fillWidth: true
            bodyHeight: 30
            hoverable: true
          }
        }
      }
    }
  }

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

  function check(bar) {
    harness.configure({});
    const page = createTemporaryObject(pageComp, root, {
      "bar": bar
    });
    waitForRendering(page);
    tryVerify(() => page.row.width > 0);
    const at = page.row.mapToItem(page, 0, 0);
    compare(Math.round(at.x), 0);
    if (bar)
      verify(page.row.width < 400, `the scroll bar takes room (${page.row.width})`);
    else
      compare(Math.round(page.row.width), 400);
    tryVerify(() => findAll(page.row, it => it.objectName === "rowTint").length > 0);
    const tint = findAll(page.row, it => it.objectName === "rowTint")[0];
    const tl = tint.mapToItem(page.scroll, 0, 0);
    verify(tl.x >= -0.5 && tl.x + tint.width <= page.scroll.width + 0.5, `the tint lies in the view: ${tl.x} + ${tint.width} of ${page.scroll.width}`);
  }

  function test_bleed_without_scroll_bar() {
    check(false);
  }

  function test_bleed_with_scroll_bar() {
    check(true);
  }
}
