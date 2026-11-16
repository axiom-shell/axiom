import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.forms
import qs.components.reusable
import qs.components.views.base

// Small editors stack as the settings page does: rows in a group abut, the
// heading sits Style.space2 above its first row, a group is a card padded
// Style.space3 all round, and the column it sits in spaces cards by
// Style.space2 (the settings page's card gap).
TestCase {
  id: root

  name: "GroupRhythm"
  when: windowShown
  visible: true
  width: 500
  height: 600

  Harness {
    id: harness
  }

  Component {
    id: rowsComp

    Surface {
      property alias group: group
      property alias row1: row1
      property alias row2: row2
      width: 400
      height: 300
      tone: "surface"

      ColumnLayout {
        width: parent.width

        FieldGroup {
          id: group
          title: "Group"

          FormRow {
            id: row1
            first: true
            bodyHeight: Widget.height
          }
          FormRow {
            id: row2
            bodyHeight: Widget.height
          }
        }
      }
    }
  }

  Component {
    id: stackComp

    Surface {
      property alias g1: g1
      property alias g2: g2
      property alias last1: last1
      property alias col: col
      width: 400
      height: 400
      tone: "surface"

      ColumnLayout {
        id: col
        width: parent.width
        spacing: Style.space2

        FieldGroup {
          id: g1
          title: "One"

          FormRow {
            id: last1
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

  Component {
    id: columnsComp

    Surface {
      property alias g1: g1
      property alias g2: g2
      property alias last1: last1
      property alias cols: cols
      width: 400
      height: 400
      tone: "surface"

      GroupColumns {
        id: cols
        // One column wide
        width: Style.columnMin

        FieldGroup {
          id: g1
          title: "One"

          FormRow {
            id: last1
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

  Component {
    id: boxedComp

    ColumnLayout {
      property alias group: group
      property alias row: row
      width: 400

      FieldGroup {
        id: group
        title: "Group"

        FormRow {
          id: row
          first: true
          bodyHeight: Widget.height
        }
      }
    }
  }

  // The SectionHeading inside a group
  function heading(group) {
    const walk = it => {
      if (it.title !== undefined && it.description !== undefined && it !== group)
        return it;
      for (const child of it.children) {
        const found = walk(child);
        if (found)
          return found;
      }
      return null;
    };
    return walk(group);
  }

  function rows() {
    const out = [];
    for (const scale of [100, 150])
      for (const density of ["compact", "normal", "roomy"])
        out.push({
          tag: scale + "% " + density,
          scale: scale,
          density: density
        });
    return out;
  }

  function test_rowsAbut_data() {
    return rows();
  }

  function test_rowsAbut(data) {
    harness.configure(data);
    const pane = createTemporaryObject(rowsComp, root);
    verify(pane);
    wait(50);
    compare(pane.row2.y - (pane.row1.y + pane.row1.height), 0);
    verify(pane.row1.height > 0);
  }

  // The heading's bottom to the first row (a control: unchanged)
  function test_headingToFirstRow_data() {
    return rows();
  }

  function test_headingToFirstRow(data) {
    harness.configure(data);
    const pane = createTemporaryObject(rowsComp, root);
    verify(pane);
    wait(50);
    const heading = root.heading(pane.group);
    const bottom = heading.mapToItem(pane.group, 0, heading.height).y;
    const top = pane.row1.mapToItem(pane.group, 0, 0).y;
    compare(Math.round(top - bottom), Style.space2);
  }

  function test_cardsStackBySpace2_data() {
    return rows();
  }

  function test_cardsStackBySpace2(data) {
    harness.configure(data);
    const pane = createTemporaryObject(stackComp, root);
    verify(pane);
    wait(50);
    compare(Math.round(root.heading(pane.g1).mapToItem(pane.col, 0, 0).y), Style.space3);
    // Each card pads its own rows: the cards sit Style.space2 apart
    compare(pane.g2.y - (pane.g1.y + pane.g1.height), Style.space2);
    compare(Math.round(pane.g1.height - pane.last1.mapToItem(pane.g1, 0, pane.last1.height).y), Style.space3);
  }

  function test_groupColumnsGap_data() {
    return rows();
  }

  function test_groupColumnsGap(data) {
    harness.configure(data);
    const pane = createTemporaryObject(columnsComp, root);
    verify(pane);
    tryVerify(() => pane.g2.width > 0 && pane.g2.y > 0);
    wait(100);
    compare(pane.cols.rowGap, Style.space2);
    compare(Math.round(pane.g2.y - (pane.g1.y + pane.g1.height)), Style.space2);
  }

  // A group is an outlined card with its padding above and below
  function test_groupKeepsItsPadding_data() {
    return rows();
  }

  function test_groupKeepsItsPadding(data) {
    harness.configure(data);
    const col = createTemporaryObject(boxedComp, root);
    verify(col);
    wait(50);
    compare(col.group.border.width, Style.hairline);
    const heading = root.heading(col.group);
    compare(Math.round(heading.mapToItem(col.group, 0, 0).y), Style.space3);
    compare(Math.round(col.group.height - (col.row.mapToItem(col.group, 0, col.row.height).y)), Style.space3);
  }
}
