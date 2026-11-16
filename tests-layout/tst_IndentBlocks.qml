import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.forms
import qs.components.reusable
import qs.components.views.base

// Indent blocks: a FormRow's depth is its FieldGroup's block base plus its own
// level; one rail per depth, the body one step in per depth, the hover tint
// from the row's own rule. A group's head modes and hide rule are below the
// row cases.
TestCase {
  id: root

  name: "IndentBlocks"
  when: windowShown
  visible: true
  width: 500
  height: 700

  Harness {
    id: harness
  }

  // A stand-in for a block's FieldGroup: anything with a `rowBase`
  Component {
    id: hostComp

    Item {
      property int rowBase: 1
      property alias row: row
      property alias probe: probe
      width: 400
      height: 100

      FormRow {
        id: row
        width: parent.width
        bodyHeight: Widget.height

        Item {
          id: probe
          width: 10
          height: 10
        }
      }
    }
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

  function make(base, level, beside) {
    const host = createTemporaryObject(hostComp, root, {
      "rowBase": base
    });
    verify(host);
    host.row.level = level;
    host.row.beside = beside === true;
    wait(20);
    return host;
  }

  // The rails drawn beside a row's body, left to right
  function rails(row) {
    return Array.from(row.children).filter(it => it.width === 2 && it.color !== undefined && Qt.colorEqual(it.color, Style.rail)).map(it => it.x).sort((a, b) => a - b);
  }

  function tint(row) {
    const walk = it => {
      if (it.objectName === "rowTint")
        return it;
      for (const child of it.children) {
        const found = walk(child);
        if (found)
          return found;
      }
      return null;
    };
    return walk(row);
  }

  function step() {
    return Widget.spacing * 2;
  }

  function test_depthIsBasePlusLevel_data() {
    return rows();
  }

  function test_depthIsBasePlusLevel(data) {
    harness.configure(data);
    compare(make(0, 0).probe.mapToItem(make(0, 0).row, 0, 0).x, 0, "no base, no level: not indented");
    const one = make(1, 0);
    compare(one.probe.mapToItem(one.row, 0, 0).x, root.step(), "under a block head: one step");
    const two = make(1, 1);
    compare(two.probe.mapToItem(two.row, 0, 0).x, 2 * root.step(), "a level under a block: double indent");
    const three = make(1, 2);
    compare(three.probe.mapToItem(three.row, 0, 0).x, 3 * root.step(), "and deeper");
  }

  function test_oneRailPerDepth_data() {
    return rows();
  }

  function test_oneRailPerDepth(data) {
    harness.configure(data);
    compare(root.rails(make(0, 0).row), []);
    compare(root.rails(make(1, 0).row), [0]);
    compare(root.rails(make(1, 1).row), [0, root.step()]);
    compare(root.rails(make(1, 2).row), [0, root.step(), 2 * root.step()]);
  }

  function test_tintStartsAtTheRowsRule_data() {
    return rows();
  }

  function test_tintStartsAtTheRowsRule(data) {
    harness.configure(data);
    const at = host => root.tint(host.row).mapToItem(host.row, 0, 0).x;
    compare(at(make(0, 0)), -Style.rowBleed, "depth 0 bleeds past the edge as before");
    compare(at(make(1, 0)), 0, "depth 1 starts at the row's edge");
    compare(at(make(1, 1)), root.step(), "depth 2 at its own rule");
    const wide = make(1, 1);
    compare(root.tint(wide.row).mapToItem(wide.row, 0, 0).x + root.tint(wide.row).width, wide.row.width + Style.rowBleed, "the right side bleeds still");
  }

  function test_besideDrawsNoIndent_data() {
    return rows();
  }

  function test_besideDrawsNoIndent(data) {
    harness.configure(data);
    const half = make(1, 1, true);
    compare(half.probe.mapToItem(half.row, 0, 0).x, 0);
    compare(root.rails(half.row), []);
  }
}
