import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.forms
import qs.components.reusable
import qs.components.views.CustomWidgets

// FieldRow with `besideLabel` (the custom widgets editor's Name and Values
// rows) at a half-pane width: the text field fills what the label leaves, and
// the row is one control line tall, as a plain one-line row (a FormRow of a
// RowLayout of label and control). `activates` makes a click on the row off
// the control act on the control. ScreenForm itself needs the editor
// service, so the row is built directly.
TestCase {
  id: root

  name: "FieldRow"
  when: windowShown
  visible: true
  width: 400
  height: 400

  Harness {
    id: harness
  }

  Component {
    id: nameComp

    FieldRow {
      width: 300
      besideLabel: true
      first: true
      label: "Name"

      StyledTextEntry {
        objectName: "entry"
        Layout.fillWidth: true
        text: "back"
      }
    }
  }

  // A plain one-line row (a label and a text entry), the height `besideLabel` matches
  Component {
    id: keyComp

    FormRow {
      width: 300
      first: true
      bodyHeight: line.implicitHeight

      RowLayout {
        id: line
        width: parent.width
        spacing: Widget.spacing

        FieldHeader {
          Layout.fillWidth: false
          Layout.alignment: Qt.AlignVCenter
          label: "Key"
        }
        StyledTextEntry {
          Layout.fillWidth: true
          text: "state"
        }
      }
    }
  }

  // A dropdown row (the Button element's Color and Click rows) at a narrow
  // pane: the control on the label's line, one control line tall (FieldFit)
  Component {
    id: shortComp

    FieldRow {
      width: Widget.textPx(300)
      shortControl: true
      first: true
      label: "Color"

      StyledComboEntry {
        objectName: "combo"
        Layout.fillWidth: true
        options: [
          {
            "value": "",
            "label": "Auto"
          }
        ]
        value: ""
      }
    }
  }

  // A row whose control answers activate()
  Component {
    id: activatesComp

    FieldRow {
      width: 300
      first: true
      label: "Key"
      activates: target

      Item {
        id: target
        property int activated: 0
        Layout.fillWidth: true
        implicitHeight: Widget.height
        function activate() {
          target.activated++;
        }
      }
    }
  }

  function initTestCase() {
    harness.configure({});
  }

  function test_beside_label_fills_data() {
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

  function test_beside_label_fills(data) {
    harness.configure({
      scale: data.scale
    });
    const row = createTemporaryObject(nameComp, root);
    const key = createTemporaryObject(keyComp, root);
    verify(row && key);
    wait(50);
    waitForRendering(row);
    const entry = row.control[0];
    verify(entry.width > row.width / 2, "the field fills the row: " + entry.width + " of " + row.width);
    verify(row.height <= Widget.height + Style.rowPadding * 2 + 1, "one control line: " + row.height);
    compare(row.height, key.height, "as tall as a plain one-line row");
  }

  function test_short_control_keeps_the_label_line_data() {
    return test_beside_label_fills_data();
  }

  function test_short_control_keeps_the_label_line(data) {
    harness.configure({
      scale: data.scale
    });
    const row = createTemporaryObject(shortComp, root);
    verify(row);
    wait(50);
    waitForRendering(row);
    const combo = row.control[0];
    const label = findText(row, "Color");
    const centre = item => item.mapToItem(row, 0, item.height / 2).y;
    verify(Math.abs(centre(combo) - centre(label)) <= 1, "on the label's line");
    compare(row.height, Widget.height + Style.rowPadding * 2, "one control line");
  }

  function findText(item, text) {
    if (item.text === text && item.visible)
      return item;
    for (const child of item.children) {
      const found = findText(child, text);
      if (found)
        return found;
    }
    return null;
  }

  function test_activates_on_row_click() {
    const row = createTemporaryObject(activatesComp, root);
    verify(row);
    wait(50);
    waitForRendering(row);
    verify(row.hoverable, "a row that activates something is hoverable");
    mouseClick(row, row.width - 2, Style.rowPadding + 2);
    compare(row.control[0].activated, 1);
  }
}
