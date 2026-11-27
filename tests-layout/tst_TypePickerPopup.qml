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

  name: "TypePickerPopup"
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

  Component {
    id: currentComp

    TypePickerPopup {
      parent: root
      x: 20
      y: 20
      width: 300
      types: ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n"].map(t => ({
            "type": t,
            "label": t
          }))
      labelOf: type => type.label
      current: "c"
    }
  }

  function marks(item) {
    const out = [];
    const walk = it => {
      if (it.objectName === "currentMark" && it.visible)
        out.push(it);
      for (const child of it.children)
        walk(child);
    };
    walk(item);
    return out;
  }

  // Opens on the current type: highlighted, and its row shows the mark
  function test_opens_on_the_current_type() {
    harness.configure({});
    const popup = createTemporaryObject(currentComp, root);
    verify(popup);
    popup.open();
    tryVerify(() => popup.opened);
    compare(popup.highlighted, 2, "c's index");
    tryVerify(() => marks(popup.contentItem).length === 1);
    popup.close();
  }
}
