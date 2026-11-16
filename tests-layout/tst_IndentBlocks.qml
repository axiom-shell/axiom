import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.forms
import qs.components.reusable
import qs.components.views.base
import qs.components.views.Settings

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

  Component {
    id: paneComp

    Surface {
      id: pane
      property alias group: group
      property string head: "auto"
      property bool lead: false
      property var levels: [0, 0]
      property bool hostVisible: true
      property bool allHidden: false
      width: 400
      height: 500
      tone: "surface"

      ColumnLayout {
        width: parent.width

        FieldGroup {
          id: group
          title: "Size"
          head: pane.head
          visible: pane.hostVisible

          FakeForm {
            levels: pane.levels
            leads: pane.lead
            allHidden: pane.allHidden
          }
        }
      }
    }
  }

  function findNamed(item, name) {
    if (item.objectName === name)
      return item;
    for (const child of item.children) {
      const found = root.findNamed(child, name);
      if (found)
        return found;
    }
    return null;
  }

  // The FormRows of a pane's form, top to bottom
  function formRows(pane) {
    const out = [];
    const walk = it => {
      if (it.bodyHeight !== undefined && it.depth !== undefined && it.objectName !== "blockHead")
        out.push(it);
      for (const child of it.children)
        walk(child);
    };
    walk(pane);
    return out.sort((a, b) => a.mapToItem(pane, 0, 0).y - b.mapToItem(pane, 0, 0).y);
  }

  function probeX(row) {
    return root.findNamed(row, "probe").mapToItem(row, 0, 0).x;
  }

  function hasHeading(group) {
    const walk = it => {
      if (it.visible && it.title !== undefined && it.description !== undefined && it !== group && (it.title === true || it.title !== ""))
        return true;
      return Array.from(it.children).some(walk);
    };
    return walk(group);
  }

  function test_blockHeadIsARowWithoutAControl_data() {
    return rows();
  }

  function test_blockHeadIsARowWithoutAControl(data) {
    harness.configure(data);
    const pane = createTemporaryObject(paneComp, root);
    verify(pane);
    wait(50);
    const head = root.findNamed(pane.group, "blockHead");
    verify(head && head.visible, "a block head");
    verify(root.findNamed(head, "rowTint") === null, "no hover tint");
    compare(head.hoverable, false);
    compare(head.tinted, false);
    compare(pane.group.rowBase, 1);
    const rows = root.formRows(pane);
    compare(rows.length, 2);
    for (const row of rows)
      compare(root.probeX(row), root.step(), "each row is one step under the head");
    verify(rows[0].mapToItem(pane, 0, 0).y >= head.mapToItem(pane, 0, head.height).y - 1, "rows below the head");
    compare(Math.round(rows[0].mapToItem(pane, 0, 0).y - head.mapToItem(pane, 0, head.height).y), 0, "abutting it");
    const divider = Array.from(rows[0].children).find(it => it.objectName === "" && it.height === 1 && it.x === root.step());
    verify(divider, "the first row's divider starts at the indent");
  }

  function test_leadDropsTheHeading_data() {
    return rows();
  }

  function test_leadDropsTheHeading(data) {
    harness.configure(data);
    const pane = createTemporaryObject(paneComp, root, {
      "lead": true,
      "levels": [0, 1, 1, 2]
    });
    verify(pane);
    wait(50);
    verify(!root.findNamed(pane.group, "blockHead").visible, "no head row");
    verify(!root.hasHeading(pane.group), "no heading drawn");
    compare(pane.group.rowBase, 0);
    const rows = root.formRows(pane);
    compare(rows.map(r => root.probeX(r)), [0, 1, 1, 2].map(n => n * root.step()), "indent by tree level");
    compare(root.rails(rows[3]), [0, root.step()], "two rails on the double-indented row");
  }

  Component {
    id: extrasComp

    Surface {
      property alias group: group
      property alias chip: chip
      width: 400
      height: 300
      tone: "surface"

      ColumnLayout {
        width: parent.width

        FieldGroup {
          id: group
          title: "Surface"
          headerExtras: Item {
            id: chip
            implicitWidth: 20
            implicitHeight: 10
          }

          FakeForm {
            levels: [0, 1]
            leads: true
          }
        }
      }
    }
  }

  function test_aLeadingFormWithExtrasStaysABlock_data() {
    return rows();
  }

  function test_aLeadingFormWithExtrasStaysABlock(data) {
    harness.configure(data);
    const pane = createTemporaryObject(extrasComp, root);
    verify(pane);
    wait(50);
    const head = root.findNamed(pane.group, "blockHead");
    verify(head.visible, "extras need the head row");
    const at = pane.chip.mapToItem(head, 0, 0);
    verify(at.y >= 0 && at.y + pane.chip.height <= head.height, "the extras sit on the head row: " + at.y);
    verify(at.x > head.width / 2, "at its right");
  }

  function test_handBuiltRowInABlockIsDoubleIndented_data() {
    return rows();
  }

  function test_handBuiltRowInABlockIsDoubleIndented(data) {
    harness.configure(data);
    const pane = createTemporaryObject(paneComp, root, {
      "levels": [0, 1]
    });
    verify(pane);
    wait(50);
    const rows = root.formRows(pane);
    compare(root.probeX(rows[0]), root.step());
    compare(root.probeX(rows[1]), 2 * root.step(), "indented under a block: base 1 + level 1");
  }

  function test_allHiddenHidesTheGroup_data() {
    return rows();
  }

  function test_allHiddenHidesTheGroup(data) {
    harness.configure(data);
    const pane = createTemporaryObject(paneComp, root, {
      "allHidden": true
    });
    verify(pane);
    wait(50);
    compare(pane.group.visible, false, "every row hidden: the head goes too");
    pane.allHidden = false;
    compare(pane.group.visible, true);
    pane.hostVisible = false;
    compare(pane.group.visible, false, "a host's own visible still wins");
    pane.allHidden = true;
    pane.allHidden = false;
    compare(pane.group.visible, false, "and after the rows come and go");
  }

  function test_boxedGroupKeepsItsSectionHeading_data() {
    return rows();
  }

  function test_boxedGroupKeepsItsSectionHeading(data) {
    harness.configure(data);
    const col = createTemporaryObject(boxedComp, root);
    verify(col);
    wait(50);
    verify(root.hasHeading(col.group), "a SectionHeading");
    verify(!root.findNamed(col.group, "blockHead").visible);
    compare(col.group.rowBase, 0);
  }

  Component {
    id: boxedComp

    ColumnLayout {
      property alias group: group
      width: 400

      FieldGroup {
        id: group
        title: "Group"

        FormRow {
          first: true
          bodyHeight: Widget.height
        }
      }
    }
  }

  // Outside any FieldGroup (the settings page) a dependent row has one rail
  function test_settingsPageRowsKeepOneLevel_data() {
    return rows();
  }

  function test_settingsPageRowsKeepOneLevel(data) {
    harness.configure(data);
    const host = createTemporaryObject(hostComp, root, {
      "rowBase": 0
    });
    host.row.indented = true;
    wait(20);
    compare(host.probe.mapToItem(host.row, 0, 0).x, root.step());
    compare(root.rails(host.row), [0]);
  }

  // A hand-built lead group with no title (the bind inspector's Key): no
  // heading and no gap above its row, whose own rows indent as before
  Component {
    id: bareComp

    Surface {
      property alias group: group
      property alias row: row
      width: 400
      height: 300
      tone: "surface"

      ColumnLayout {
        width: parent.width

        FieldGroup {
          id: group
          title: ""
          head: "lead"

          FormRow {
            id: row
            first: true
            bodyHeight: Widget.height
          }
        }
      }
    }
  }

  function test_titlelessLeadGroupIsJustItsRows_data() {
    return rows();
  }

  function test_titlelessLeadGroupIsJustItsRows(data) {
    harness.configure(data);
    const pane = createTemporaryObject(bareComp, root);
    verify(pane);
    wait(50);
    compare(pane.row.mapToItem(pane.group, 0, 0).y, 0, "nothing above the row");
    compare(pane.group.height, pane.row.height);
    compare(pane.group.rowBase, 0);
  }

  // A settings card ending on a shut fold row (SettingsGroupCard sets
  // bottomInset: 0): the row's own padding closes the card, so the space
  // under the fold's text equals the space above it
  Component {
    id: cardComp

    ColumnLayout {
      property alias card: card
      property alias row: row
      width: 400

      FoldingCard {
        id: card
        title: "Card"

        FormRow {
          id: row
          first: true
          bodyHeight: Widget.height
        }
      }
    }
  }

  function test_foldingCardBottomInset_data() {
    return rows();
  }

  function test_foldingCardBottomInset(data) {
    harness.configure(data);
    const host = createTemporaryObject(cardComp, root);
    verify(host);
    wait(50);
    const bottom = () => host.row.mapToItem(host.card, 0, host.row.height).y;
    compare(Math.round(host.card.height - bottom()), Style.space3, "padded under the last row by default");
    host.card.bottomInset = 0;
    wait(20);
    compare(Math.round(host.card.height - bottom()), 0, "none when the last row is a shut fold");
    compare(host.card.implicitHeight, host.card.height);
  }
}
