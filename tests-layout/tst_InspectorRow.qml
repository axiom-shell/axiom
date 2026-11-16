import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.forms
import qs.components.reusable
import qs.components.views.CustomWidgets

// InspectorRow with `besideLabel` (the custom widgets editor's Name and Values
// rows) at a half-pane width: the text field fills what the label leaves, and
// the row is one control line tall, as the Key/Test row beside it (a FormRow
// of a RowLayout of label and control). ScreenForm itself needs the editor
// service, so the row is built directly.
TestCase {
  id: root

  name: "InspectorRow"
  when: windowShown
  visible: true
  width: 400
  height: 400

  Harness {
    id: harness
  }

  Component {
    id: nameComp

    InspectorRow {
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

  // The Key/Test row's shape (ScreenForm), its control a text entry
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

  function initTestCase() {
    harness.configure({});
  }

  function test_besideLabelFills_data() {
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

  function test_besideLabelFills(data) {
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
    compare(row.height, key.height, "as tall as the Key/Test row");
  }
}
