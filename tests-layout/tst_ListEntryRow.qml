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
