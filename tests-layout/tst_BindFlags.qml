import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.views.Keybinds

// BindFlags: each flag is a boxed form row (padded, at least Style.rowHeight
// tall) with its switch at the row's right end; the old bare rows were only as
// tall as their text.
TestCase {
  id: root

  name: "BindFlags"
  when: windowShown
  visible: true
  width: 500
  height: 600

  Harness {
    id: harness
  }

  Component {
    id: hostComp

    ColumnLayout {
      property alias flags: inner

      width: 420

      BindFlags {
        id: inner

        Layout.fillWidth: true
      }
    }
  }

  function initTestCase() {
    harness.configure({});
  }

  // The rows: the items of the group that hold a switch
  function rows(item, out) {
    if (item.bodyHeight !== undefined && item.hoverable !== undefined && item.objectName !== "blockHead")
      out.push(item);
    for (const child of item.children)
      root.rows(child, out);
    return out;
  }

  function test_rows_are_padded_and_stacked() {
    const host = createTemporaryObject(hostComp, root);
    waitForRendering(host);
    const rows = root.rows(host, []);
    compare(rows.length, 3);
    for (let i = 0; i < rows.length; i++) {
      verify(rows[i].height >= Style.rowHeight, "row " + i + " is at least a row tall: " + rows[i].height);
      verify(rows[i].height >= rows[i].bodyHeight + Style.rowPadding * 2 - 1, "row " + i + " is padded");
      if (i > 0)
        verify(rows[i].y >= rows[i - 1].y + rows[i - 1].height, "row " + i + " sits under the one above");
    }
    verify(rows[0].first && !rows[1].first, "only the top row has no divider");
  }
}
