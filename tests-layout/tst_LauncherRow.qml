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

  function test_title_shows_data() {
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

  function test_title_shows(data) {
    const row = makeRow(data);
    const title = findLabel(row, data.title);
    verify(title, "title label found");
    verify(title.implicitWidth < 200);
    verify(title.width > 0, "title width " + title.width);
    verify(!title.truncated, "title truncated at width " + title.width);
    // The title starts where a row with a second line starts it, whether or not it has one
    const ref = makeRow({
      title: "Ref",
      kind: "app",
      subtitle: "x"
    });
    const refTitle = findLabel(ref, "Ref");
    verify(refTitle);
    const at = title.mapToItem(row, 0, 0).x;
    const refAt = refTitle.mapToItem(ref, 0, 0).x;
    verify(Math.abs(at - refAt) < 0.5, "title x " + at + " vs " + refAt);
  }

  function test_current_title_reads_on_its_fill() {
    harness.configure({
      theme: "rose-pine"
    });
    const row = makeRow({
      title: "Zen Browser",
      kind: "app"
    });
    row.current = true;
    wait(Appearance.animFast + 200);
    const title = findLabel(row, "Zen Browser");
    verify(title);
    compare(String(title.color), String(Style.inkAccentContainer.text));
    verify(String(title.color) !== "#000000", "title is black");
    harness.configure({});
  }

  function test_title_shows_when_assigned_late() {
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

  function test_long_title_with_usage_fits() {
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

  function test_usage_follows_short_title() {
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

  function test_hint_is_status_chip() {
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

  // A long hint stays whole inside its chip at the narrowest launcher: the
  // title gives way, the hint is never capped
  function test_long_hint_stays_in_its_chip() {
    const hint = "Press Enter again to confirm";
    const row = makeRow({
      title: "Shut down the computer",
      kind: "command",
      hint: hint
    });
    row.width = 400;
    wait(50);
    const chip = findLabel(row, hint);
    verify(chip, "hint label found");
    verify(!chip.truncated, "hint truncated");
    verify(chip.width <= chip.parent.width + 0.5, "hint " + chip.width + " wider than its chip " + chip.parent.width);
    verify(chip.mapToItem(row, chip.width, 0).x <= row.width, "hint inside the row");
  }

  // The pill's rest colour is the selected fill at alpha 0: a ColorAnimation
  // lerps each channel, so a rest of transparent black dips through grey
  function pillOf(row) {
    for (let i = 0; i < row.children.length; i++) {
      if (row.children[i].radius !== undefined)
        return row.children[i];
    }
    return null;
  }

  function test_selection_fades_in_hue_data() {
    return [
      {
        tag: "default",
        theme: undefined
      },
      {
        tag: "catppuccin-latte",
        theme: "catppuccin-latte"
      }
    ];
  }

  function test_selection_fades_in_hue(data) {
    if (data.theme)
      harness.configure({
        theme: data.theme
      });
    const row = makeRow({
      title: "x",
      kind: "app"
    });
    const pill = pillOf(row);
    verify(pill);
    row.current = true;
    wait(300);
    row.current = false;
    wait(300);
    const want = Style.accentContainer;
    fuzzyCompare(pill.color.r, want.r, 0.01);
    fuzzyCompare(pill.color.g, want.g, 0.01);
    fuzzyCompare(pill.color.b, want.b, 0.01);
    compare(pill.color.a, 0);
    harness.configure({});
  }
}
