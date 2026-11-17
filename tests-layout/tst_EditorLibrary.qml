import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.reusable
import qs.components.views.base

// EditorLibrary: `groupable: false` keeps its TypeLibrary flat even when the
// kept choice is By category.
TestCase {
  id: root

  name: "EditorLibrary"
  when: windowShown
  visible: true
  width: 500
  height: 400

  Harness {
    id: harness
  }

  Component {
    id: libComp

    EditorLibrary {
      width: 400
      height: 300
      types: [
        {
          "type": "a",
          "label": "a",
          "group": "g"
        }
      ]
      groups: ["g"]
      delegate: Rectangle {
        required property var modelData
        width: 40
        height: 20
      }
    }
  }

  function typeLibraryOf(item) {
    if (item.grouped !== undefined && item.groupable !== undefined && item.sections !== undefined)
      return item;
    for (const child of item.children) {
      const found = typeLibraryOf(child);
      if (found)
        return found;
    }
    return null;
  }

  function initTestCase() {
    harness.configure({});
  }

  function test_groupable_off_stays_flat() {
    const lib = createTemporaryObject(libComp, root, {
      "groupable": false
    });
    verify(lib);
    const inner = typeLibraryOf(lib);
    verify(inner, "builds a TypeLibrary");
    verify(!inner.grouped, "not grouped without groupable");
    lib.groupable = true;
    verify(inner.grouped, "grouped by the kept choice when groupable");
  }
}
