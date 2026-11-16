import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.forms
import qs.components.reusable
import qs.components.views.CustomWidgets

// The custom widgets editor's forms are built as the settings page builds
// its cards: a row's hover tint (StateLayer, which reaches Style.rowBleed past
// the row's sides) lies fully inside the scroll view that clips it, with
// room on both sides, so its ends stay rounded. A flat FieldGroup straight
// in a scroll view (the control) has its tint cut at the edge; FormInset
// (the editor's tabs and inspector) fixes that.
TestCase {
  id: root

  name: "FormInset"
  when: windowShown
  visible: true
  width: 400
  height: 400

  Harness {
    id: harness
  }

  // A pane's form: a flat group with a hoverable row and a row of the
  // editor's own (an InspectorRow with a dropdown)
  Component {
    id: formComp

    FieldGroup {
      Layout.fillWidth: true
      title: "Group"
      // Rows at depth 0, the ones whose tint bleeds past the edge (an indented
      // row's tint starts at its own rule)
      head: "lead"

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        FormRow {
          first: true
          hoverable: true
          bodyHeight: Widget.height

          StyledTextEntry {
            width: parent.width
            text: "x"
          }
        }
        InspectorRow {
          label: "Key"
          besideLabel: true

          StyledTextEntry {
            Layout.fillWidth: true
            text: "y"
          }
        }
      }
    }
  }

  Component {
    id: paneComp

    Surface {
      id: pane
      property bool inset: true
      readonly property alias scroll: scroll
      width: 320
      height: 300
      tone: "surface"

      StyledScrollView {
        id: scroll
        anchors.fill: parent

        Loader {
          width: scroll.availableWidth
          sourceComponent: pane.inset ? insetComp : rawComp
        }
      }

      Component {
        id: insetComp

        FormInset {
          Loader {
            Layout.fillWidth: true
            sourceComponent: formComp
          }
        }
      }

      Component {
        id: rawComp

        ColumnLayout {
          Loader {
            Layout.fillWidth: true
            sourceComponent: formComp
          }
        }
      }
    }
  }

  function initTestCase() {
    harness.configure({});
  }

  // Every StateLayer that bleeds (a FormRow's tint, built in a Loader) under `item`
  function layers(item) {
    let out = [];
    if (item.bleed !== undefined && item.bleed > 0 && item.hovered !== undefined)
      out.push(item);
    for (const child of item.children)
      out = out.concat(layers(child));
    return out;
  }

  // The nearest ancestor that clips what is drawn outside it
  function clipOf(item) {
    for (let p = item.parent; p; p = p.parent) {
      if (p.clip)
        return p;
    }
    return null;
  }

  function test_tintInsideTheClip_data() {
    return [
      {
        tag: "100%",
        scale: 100
      },
      {
        tag: "150%",
        scale: 150
      }
    ];
  }

  function test_tintInsideTheClip(data) {
    harness.configure({
      scale: data.scale
    });
    const pane = createTemporaryObject(paneComp, root);
    verify(pane);
    wait(50);
    waitForRendering(pane);
    const found = root.layers(pane.scroll);
    verify(found.length >= 2, "the rows' tints are built: " + found.length);
    for (const layer of found) {
      const clip = root.clipOf(layer);
      verify(clip, "something clips the tint");
      const left = layer.mapToItem(clip, 0, 0).x;
      verify(left >= 0, "room on the left: " + left);
      verify(left + layer.width <= clip.width, "room on the right: " + (left + layer.width) + " of " + clip.width);
    }
  }

  // Without the inset the tint is cut: the test above is not vacuous
  function test_withoutInsetTheTintIsCut() {
    const pane = createTemporaryObject(paneComp, root, {
      inset: false
    });
    verify(pane);
    wait(50);
    waitForRendering(pane);
    const found = root.layers(pane.scroll);
    verify(found.length >= 2);
    verify(found.some(layer => layer.mapToItem(root.clipOf(layer), 0, 0).x < 0), "a tint reaches past the left edge");
  }
}
