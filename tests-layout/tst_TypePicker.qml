import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.reusable

// The custom widgets editor's { } picker (PathInsertButton): parented to the
// row holding the field and the button and opened at that row, its list is
// as wide as the whole row, not only the field.
TestCase {
  id: root

  name: "TypePicker"
  when: windowShown
  visible: true
  width: 500
  height: 300

  Harness {
    id: harness
  }

  Component {
    id: rowComp

    RowLayout {
      id: row

      property alias picker: picker

      x: 20
      y: 20
      width: 400

      Rectangle {
        objectName: "field"
        Layout.fillWidth: true
        implicitHeight: 30
      }
      Rectangle {
        implicitWidth: 30
        implicitHeight: 30
      }
      TypePickerPopup {
        id: picker
        parent: row
        matchWidth: true
        types: [
          {
            "type": "a",
            "label": "a"
          }
        ]
        labelOf: type => type.label
      }
    }
  }

  function test_listSpansTheRow() {
    harness.configure({});
    const row = createTemporaryObject(rowComp, root);
    verify(row);
    wait(0);
    row.picker.openAt(row);
    compare(row.picker.width, row.width, "as wide as the row");
    const field = row.children[0];
    verify(row.picker.width > field.width, "wider than the field");
    row.picker.close();
  }
}
