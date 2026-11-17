import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.views.Layouts

// MenuOpening: "Show on screen" and "Show other menus" share a row while both
// fit at their widest, and stack one under the other when they don't.
TestCase {
  id: root

  name: "MenuOpening"
  when: windowShown
  visible: true
  width: 900
  height: 400

  Harness {
    id: harness
  }

  Component {
    id: hostComp

    Item {
      property alias opening: inner

      height: 300

      ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        MenuOpening {
          id: inner

          menu: ({
              "id": "left"
            })
        }
      }
    }
  }

  function initTestCase() {
    harness.configure({});
  }

  function buttons(item, out) {
    if (item.iconText !== undefined && item.kind !== undefined && item.text !== undefined)
      out.push(item);
    for (const child of item.children)
      root.buttons(child, out);
    return out;
  }

  function test_buttons_share_a_row_only_while_both_fit() {
    const host = createTemporaryObject(hostComp, root, {
      "width": 700
    });
    waitForRendering(host);
    const pair = root.buttons(host.opening, []).filter(b => b.iconText === "visibility" || b.iconText === "layers");
    compare(pair.length, 2);
    const need = pair[0].implicitWidth + pair[1].implicitWidth + Widget.spacing;
    verify(need < 700, "both buttons fit a wide row");
    compare(pair[0].y, pair[1].y, "side by side at a wide width");
    verify(pair[0].width >= pair[0].implicitWidth - 1 && pair[1].width >= pair[1].implicitWidth - 1, "neither is squeezed");

    host.width = Math.ceil(need) - 20;
    waitForRendering(host);
    verify(pair[1].y > pair[0].y + pair[0].height - 1, "stacked at a narrow width");
    verify(pair[0].width >= pair[0].implicitWidth - 1 && pair[1].width >= pair[1].implicitWidth - 1, "neither is squeezed when stacked");
  }
}
