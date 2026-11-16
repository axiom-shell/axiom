import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.surfaces.launcher

// LauncherRow: the title shows in full whatever sits beside it, a long title
// elides inside the row instead of overflowing it, and a command's usage
// follows a short title.
TestCase {
  id: root

  name: "LauncherRow"
  when: windowShown
  visible: true
  width: 600
  height: 300

  Harness {
    id: harness
  }

  Component {
    id: rowComp

    LauncherRow {
      width: 560
      height: 56
      index: 0
    }
  }

  readonly property string longTitle: "A very long window title that goes on and on and on and on, well past the width of the row it sits in, to prove it elides"

  function initTestCase() {
    harness.configure({});
  }

  function findLabel(item, text) {
    if (item.text === text && item.implicitWidth !== undefined && item.truncated !== undefined)
      return item;
    for (let i = 0; i < item.children.length; i++) {
      const hit = findLabel(item.children[i], text);
      if (hit)
        return hit;
    }
    return null;
  }

  function makeRow(data) {
    const row = createTemporaryObject(rowComp, root);
    verify(row);
    row.modelData = data;
    wait(50);
    waitForRendering(row);
    return row;
  }

  function test_titleShows_data() {
    return [
      {
        tag: "app",
        title: "Zen Browser",
        kind: "app",
        subtitle: "Experience tranquility while browsing the web without being disturbed by ads and trackers"
      },
      {
        tag: "app no subtitle",
        title: "1Password",
        kind: "app"
      },
      {
        tag: "app with hint",
        title: "Files",
        kind: "app",
        subtitle: "Browse your files",
        hint: "Enter"
      }
    ];
  }

  function test_titleShows(data) {
    const row = makeRow(data);
    const title = findLabel(row, data.title);
    verify(title, "title label found");
    verify(title.implicitWidth < 200);
    verify(title.width > 0, "title width " + title.width);
    verify(!title.truncated, "title truncated at width " + title.width);
  }

  function test_titleShowsWhenAssignedLate() {
    const row = createTemporaryObject(rowComp, root);
    verify(row);
    row.modelData = ({});
    wait(50);
    row.modelData = {
      title: "Zen Browser",
      kind: "app",
      subtitle: "A calm browser"
    };
    wait(50);
    waitForRendering(row);
    const title = findLabel(row, "Zen Browser");
    verify(title);
    verify(title.width > 0, "title width " + title.width);
    verify(!title.truncated);
  }

  function test_longTitleWithUsageFits() {
    const row = makeRow({
      title: root.longTitle,
      kind: "command",
      usage: "<arg> usage"
    });
    const title = findLabel(row, root.longTitle);
    verify(title);
    const line = title.parent;
    verify(line.width <= row.width, "title line " + line.width + " wider than the row " + row.width);
    verify(title.width > 0);
  }

  function test_usageFollowsShortTitle() {
    const row = makeRow({
      title: "calc",
      kind: "command",
      usage: "<expr> evaluate"
    });
    const title = findLabel(row, "calc");
    const usage = findLabel(row, "<expr> evaluate");
    verify(title && usage);
    verify(title.width > 0 && !title.truncated);
    const gap = usage.mapToItem(title.parent, 0, 0).x - (title.x + title.width);
    verify(gap < 2 * Widget.spacing + 1, "usage " + gap + " px after the title");
  }

  // The hint is a StatusChip: a pill at least a small control tall, inside the row
  function findChip(item) {
    if (item.tone !== undefined && item.ink !== undefined && item.text === "Enter")
      return item;
    for (let i = 0; i < item.children.length; i++) {
      const hit = findChip(item.children[i]);
      if (hit)
        return hit;
    }
    return null;
  }

  function test_hintIsStatusChip() {
    const row = makeRow({
      title: "Files",
      kind: "app",
      hint: "Enter"
    });
    const chip = findChip(row);
    verify(chip, "hint chip found");
    verify(chip.height >= Widget.smallHeight, "chip " + chip.height + " px tall, a small control is " + Widget.smallHeight);
    compare(chip.radius, chip.height / 2);
    verify(chip.x + chip.width <= row.width, "chip inside the row");
  }
}
