import QtQuick
import QtTest
import qs.config
import qs.components.reusable

// ListEntryRow's standard actions: Duplicate and Remove show only for their
// `can…` flags, after the row's own actions, and emit `duplicated` and
// `removeRequested`; both are RowActions at Widget.compactHeight.
TestCase {
  id: root

  name: "ListEntryRow"
  when: windowShown
  visible: true
  width: 500
  height: 300

  Harness {
    id: harness
  }

  Component {
    id: rowComp

    ListEntryRow {
      id: entry
      width: 400
      height: Style.listRowHeight
      icon: "bar_chart"
      label: "Row"
      selected: true

      RowAction {
        objectName: "own"
        row: entry
        iconText: "visibility"
      }
    }
  }

  Component {
    id: selectedComp

    ListEntryRow {
      id: entry
      width: 400
      height: Style.listRowHeight
      icon: "bar_chart"
      label: "Row"
      selected: true
      changed: true

      leading: [
        StyledSwitch {
          checked: true
        }
      ]

      RowAction {
        objectName: "litAction"
        row: entry
        iconText: "visibility"
        lit: true
      }

      RowAction {
        objectName: "plainAction"
        row: entry
        iconText: "tune"
      }
    }
  }

  function findAllBy(item, pred, out) {
    if (pred(item))
      out.push(item);
    for (const c of item.children)
      findAllBy(c, pred, out);
    return out;
  }

  // A selected row is a solid accent: its inks, actions, dot and switch read on it
  function test_selected_row_reads_on_the_accent() {
    harness.configure({});
    const row = createTemporaryObject(selectedComp, root);
    waitForRendering(row);
    verify(row.inkScope === Style.inkAccent, "the row's ink is the accent's");
    const lit = findByName(row, "litAction");
    const plain = findByName(row, "plainAction");
    compare(lit.kind, "text", "a lit action isn't primary on the accent");
    const layer = findAllBy(plain, it => it.onAccent !== undefined && it.hovered !== undefined, [])[0];
    verify(layer !== undefined && layer.onAccent, "a plain action's state layer is the on-accent one");
    const dot = findAllBy(row, it => it.tone !== undefined && it.shown !== undefined, [])[0];
    verify(dot !== undefined);
    verify(Qt.colorEqual(dot.color, Style.inkAccent.accent), "the unsaved dot reads on the accent");
    const toggle = findAllBy(row, it => it.checked !== undefined && it._scope !== undefined, [])[0];
    verify(toggle !== undefined, "the switch");
    compare(toggle.background.border.width, Style.hairline, "the on track is outlined on the accent");
    row.selected = false;
    waitForRendering(row);
    compare(lit.kind, "primary", "a lit action is primary off the accent");
    compare(toggle.background.border.width, 0, "no outline off the accent");
  }

  function buttons(item, out) {
    if (item.iconText !== undefined && item.visible)
      out.push(item);
    for (const c of item.children)
      buttons(c, out);
    return out;
  }

  function test_standard_actions() {
    harness.configure({});
    const row = createTemporaryObject(rowComp, root);
    compare(buttons(row, []).map(b => b.iconText), ["visibility"], "none by default");
    let duplicated = 0;
    let removed = 0;
    row.duplicated.connect(() => duplicated++);
    row.removeRequested.connect(() => removed++);
    row.canDuplicate = true;
    row.canRemove = true;
    waitForRendering(row);
    const found = buttons(row, []);
    compare(found.map(b => b.iconText), ["visibility", "content_copy", "close"], "the row's own first");
    compare(found[1].width, Widget.compactHeight);
    compare(found[2].kind, "danger");
    tryCompare(found[1], "opacity", 1);
    mouseClick(found[1]);
    compare(duplicated, 1);
    mouseClick(found[2]);
    compare(removed, 1);
    row.canDuplicate = false;
    compare(buttons(row, []).map(b => b.iconText), ["visibility", "close"]);
  }

  // A row with neither standard action builds none; with both, Tab walks them in order
  function test_standard_actions_are_built_only_when_asked() {
    harness.configure({});
    const row = createTemporaryObject(rowComp, root);
    compare(findByName(row, "standardDuplicate"), null, "no Duplicate built");
    compare(findByName(row, "standardRemove"), null, "no Remove built");
    row.canDuplicate = true;
    row.canRemove = true;
    waitForRendering(row);
    const dup = findByName(row, "standardDuplicate");
    const rem = findByName(row, "standardRemove");
    verify(dup && rem);
    dup.forceActiveFocus(Qt.TabFocusReason);
    keyClick(Qt.Key_Tab);
    verify(rem.activeFocus, "Tab walks Duplicate to Remove");
  }

  function findByName(item, name) {
    if (item.objectName === name)
      return item;
    for (const c of item.children) {
      const hit = findByName(c, name);
      if (hit)
        return hit;
    }
    return null;
  }

  function test_image_replaces_the_glyph() {
    harness.configure({});
    const row = createTemporaryObject(rowComp, root);
    const glyphs = () => row.children.length > 0 && root.texts(row).filter(t => t.text === "bar_chart");
    compare(glyphs().length, 1, "the glyph");
    row.image = Qt.resolvedUrl("missing.png");
    compare(glyphs().length, 0, "hidden once there is a picture");
  }

  // A row with no icon keeps no slot for one: the label starts at the padding
  function test_no_icon_no_slot() {
    harness.configure({});
    const row = createTemporaryObject(rowComp, root);
    waitForRendering(row);
    const labelOf = () => root.texts(row).find(t => t.text === "Row");
    const before = labelOf().mapToItem(row, 0, 0).x;
    row.icon = "";
    wait(50);
    const x = labelOf().mapToItem(row, 0, 0).x;
    compare(x, Widget.padding, "the label sits at the padding");
    verify(x < before, "the icon's slot is gone");
  }

  function texts(item) {
    const out = [];
    const walk = it => {
      if (it.visible && it.paintedWidth !== undefined && it.lineCount !== undefined)
        out.push(it);
      for (const c of it.children)
        walk(c);
    };
    walk(item);
    return out;
  }
}
