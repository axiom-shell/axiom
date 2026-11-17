import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.forms
import qs.components.reusable
import qs.components.content.base
import qs.components.views.base

// Every box of cards (the settings page's TitledCard, a ToolPane's columns, an
// inspector's own box, the element inspector's inner box) puts its cards at
// the settings page's gutter (Widget.padding left, the same plus the scroll
// bar's lane right) and spaces them by Style.cardGap, down and across.
TestCase {
  id: root

  name: "CardGutters"
  when: windowShown
  visible: true
  width: 1000
  height: 700

  Harness {
    id: harness
  }

  Component {
    id: settingsComp

    TitledCard {
      width: 900
      height: 600
      property alias g1: g1
      property alias g2: g2

      FieldGroup {
        id: g1
        title: "One"
        FormRow {
          id: r1
          first: true
          bodyHeight: Widget.height
        }
        FormRow {
          bodyHeight: Widget.height
        }
      }
      FieldGroup {
        id: g2
        title: "Two"
        FormRow {
          first: true
          bodyHeight: Widget.height
        }
        FormRow {
          bodyHeight: Widget.height
        }
      }
    }
  }

  Component {
    id: toolComp

    // (a TitledCard fills its parent, so the width is the holder's)
    Item {
      width: 1400
      height: 600
      property alias g1: g1
      property alias g2: g2
      property alias cols: cols

      ToolPane {
        anchors.fill: parent

        GroupColumns {
          id: cols
          Layout.fillWidth: true

          FieldGroup {
            id: g1
            title: "One"
            FormRow {
              first: true
              bodyHeight: Widget.height
            }
          }
          FieldGroup {
            id: g2
            title: "Two"
            FormRow {
              first: true
              bodyHeight: Widget.height
            }
          }
        }
      }
    }
  }

  // An inspector's own page box (WidgetInspector's shape), and the element
  // inspector's inner box: a Surface, its padding, a CardScroll
  Component {
    id: boxComp

    Surface {
      id: box
      width: 400
      height: 600
      tone: "surface"
      property alias g1: g1
      property alias g2: g2

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Widget.padding

        CardScroll {
          Layout.fillWidth: true
          Layout.fillHeight: true

          FieldGroup {
            id: g1
            Layout.fillWidth: true
            title: "One"
            FormRow {
              first: true
              bodyHeight: Widget.height
            }
          }
          FieldGroup {
            id: g2
            Layout.fillWidth: true
            title: "Two"
            FormRow {
              first: true
              bodyHeight: Widget.height
            }
          }
        }
      }
    }
  }

  Component {
    id: inspectorComp

    Surface {
      width: 400
      height: 600
      tone: "surface"
      property alias g1: g1
      property alias g2: g2

      CardScroll {
        anchors.fill: parent
        anchors.margins: Widget.padding

        FieldGroup {
          id: g1
          Layout.fillWidth: true
          title: "One"
          FormRow {
            first: true
            bodyHeight: Widget.height
          }
        }
        FieldGroup {
          id: g2
          Layout.fillWidth: true
          title: "Two"
          FormRow {
            first: true
            bodyHeight: Widget.height
          }
        }
      }
    }
  }

  function rows() {
    const out = [];
    for (const scale of [100, 150])
      for (const density of ["compact", "normal", "roomy"])
        out.push({
          "tag": `${scale}% ${density}`,
          "scale": scale,
          "density": density
        });
    return out;
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

  function clipOf(item) {
    for (let p = item.parent; p; p = p.parent) {
      if (p.clip)
        return p;
    }
    return null;
  }

  function make(comp, data) {
    harness.configure(data);
    const box = createTemporaryObject(comp, root);
    verify(box);
    waitForRendering(box);
    tryVerify(() => box.g1.width > 0 && box.g2.width > 0);
    wait(80);
    return box;
  }

  // The gutters of a box's first card: left, right
  function gutters(box) {
    const at = box.g1.mapToItem(box, 0, 0).x;
    // (the right edge of the rightmost card: columns put two side by side)
    const right = Math.max(box.g1.mapToItem(box, box.g1.width, 0).x, box.g2.mapToItem(box, box.g2.width, 0).x);
    return [Math.round(at), Math.round(box.width - right)];
  }

  function test_gutter_data() {
    return rows();
  }

  function test_gutter(data) {
    // The box's padding, and on the right the scroll bar's lane past it
    for (const comp of [settingsComp, toolComp, boxComp, inspectorComp]) {
      const box = make(comp, data);
      const want = [Widget.padding, Widget.padding + Math.max(0, Widget.px(12))];
      const got = root.gutters(box);
      compare(got[0], want[0], `left, ${data.tag}`);
      compare(got[1], want[1], `right, ${data.tag}`);
    }
  }

  function test_gap_down_data() {
    return rows();
  }

  function test_gap_down(data) {
    for (const comp of [settingsComp, boxComp, inspectorComp]) {
      const box = make(comp, data);
      compare(Math.round(box.g2.mapToItem(box.g1.parent, 0, 0).y - (box.g1.y + box.g1.height)), Style.cardGap, data.tag);
    }
  }

  function test_gap_across_data() {
    return rows();
  }

  function test_gap_across(data) {
    const box = make(toolComp, data);
    tryVerify(() => box.cols.count === 2, 2000, `two columns (${box.cols.count} in ${box.cols.width})`);
    wait(80);
    compare(Math.round(box.g2.x - (box.g1.x + box.g1.width)), Style.cardGap, data.tag);
  }

  function test_tint_in_clip_data() {
    return rows();
  }

  function test_tint_in_clip(data) {
    const box = make(settingsComp, data);
    const row = box.g1.contentChildren[0];
    const tint = () => root.findAll(row, it => it.objectName === "rowTint")[0];
    tryVerify(() => tint() !== undefined);
    const clip = root.clipOf(tint());
    verify(clip);
    const left = tint().mapToItem(clip, 0, 0).x;
    verify(left >= -0.5 && left + tint().width <= clip.width + 0.5, `${left} + ${tint().width} of ${clip.width}`);
  }
}
