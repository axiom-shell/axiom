import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "DockLayout"

  function win(id, appId, extra) {
    return Object.assign({
      "id": id,
      "appId": appId,
      "title": appId,
      "hidden": false,
      "output": "A",
      "workspaceId": 1,
      "focusRank": 5
    }, extra ?? {});
  }

  readonly property var byClass: w => w.appId

  function test_scope() {
    const w = win("0x1", "kitty", {
      "output": "B",
      "workspaceId": 3
    });
    verify(DockLayout.inScope(w, "all", "A", 1));
    verify(DockLayout.inScope(w, "monitor", "B", 1));
    verify(!DockLayout.inScope(w, "monitor", "A", 3));
    verify(DockLayout.inScope(w, "workspace", "A", 3));
    verify(!DockLayout.inScope(w, "workspace", "B", 1));
    verify(!DockLayout.inScope(win("0x2", "a", {
      "hidden": true
    }), "all", "A", 1), "hidden");
  }

  function test_pinned_first_in_order() {
    const windows = [win("0x1", "kitty"), win("0x2", "firefox"), win("0x3", "discord")];
    const items = DockLayout.buildItems(["firefox", "files", "kitty"], windows, byClass, true);
    compare(items.map(i => i.key), ["firefox", "files", "kitty", "discord"]);
    compare(items.map(i => i.pinned), [true, true, true, false]);
    compare(items[1].windows.length, 0, "a pinned app with no windows");
  }

  function test_running_hidden() {
    const items = DockLayout.buildItems(["firefox"], [win("0x1", "kitty"), win("0x2", "firefox")], byClass, false);
    compare(items.map(i => i.key), ["firefox"]);
  }

  function test_duplicate_pins_once() {
    const items = DockLayout.buildItems(["a", "a", ""], [], byClass, true);
    compare(items.map(i => i.key), ["a"]);
  }

  function test_windows_grouped_recent_first() {
    const windows = [win("0x1", "kitty", {
        "focusRank": 4
      }), win("0x2", "kitty", {
        "focusRank": 0
      }), win("0x3", "kitty", {
        "focusRank": 2
      })];
    const items = DockLayout.buildItems([], windows, byClass, true);
    compare(items.length, 1);
    compare(items[0].windows.map(w => w.id), ["0x2", "0x3", "0x1"]);
  }

  function test_unresolved_skipped() {
    const items = DockLayout.buildItems([], [win("0x1", "")], w => w.appId, true);
    compare(items.length, 0);
  }

  function test_click_target() {
    const windows = [win("0x2", "k"), win("0x1", "k"), win("0x3", "k")];
    compare(DockLayout.clickTarget([], ""), "");
    compare(DockLayout.clickTarget(windows, "0x9"), "0x2", "most recent when none is focused");
    compare(DockLayout.clickTarget(windows, "0x1"), "0x2", "cycles in a stable order");
    compare(DockLayout.clickTarget(windows, "0x2"), "0x3");
    compare(DockLayout.clickTarget(windows, "0x3"), "0x1", "wraps");
  }

  function test_magnify_off() {
    compare(DockLayout.magnifiedSizes(3, null, 48, 80, 3, 6), [48, 48, 48]);
    compare(DockLayout.magnifiedSizes(3, 30, 48, 48, 3, 6), [48, 48, 48], "max not above base");
  }

  function test_magnify_peak_and_falloff() {
    // Icon 2's centre at rest: 2 * 54 + 24
    const sizes = DockLayout.magnifiedSizes(7, 132, 48, 80, 2, 6);
    compare(sizes[2], 80, "peak under the pointer");
    fuzzyCompare(sizes[1], sizes[3], 0.001, "symmetric");
    verify(sizes[1] < 80 && sizes[1] > 48);
    compare(sizes[0], 48, "outside the range");
    compare(sizes[4], 48);
    compare(sizes[6], 48);
  }

  function test_magnify_before_row() {
    // Left of the first icon (the grown box reaching past the row at rest)
    // still magnifies, falling off as it does past the last icon
    const before = DockLayout.magnifiedSizes(3, -10, 48, 80, 2, 6);
    const after = DockLayout.magnifiedSizes(3, 3 * 54 - 6 + 10, 48, 80, 2, 6);
    verify(before[0] > 48, "first icon still grown");
    fuzzyCompare(before[0], after[2], 0.001, "mirrors the far end");
    fuzzyCompare(before[1], after[1], 0.001);
  }

  function test_overlap() {
    const dock = {
      "x": 100,
      "y": 1000,
      "width": 400,
      "height": 80
    };
    verify(DockLayout.overlaps(dock, {
      "x": 0,
      "y": 900,
      "width": 200,
      "height": 150
    }));
    verify(!DockLayout.overlaps(dock, {
      "x": 0,
      "y": 0,
      "width": 1920,
      "height": 1000
    }), "touching edges don't overlap");
    verify(DockLayout.covered(dock, [
      {
        "x": 0,
        "y": 0,
        "w": 1920,
        "h": 1001
      }
    ]));
    verify(!DockLayout.covered(dock, [
      {
        "x": 600,
        "y": 900,
        "w": 100,
        "h": 200
      }
    ]));
    // A window's cover stands in for its geometry
    verify(DockLayout.covered(dock, [
      {
        "x": 600,
        "y": 900,
        "w": 100,
        "h": 200,
        "cover": {
          "x": 0,
          "y": 0,
          "w": 1920,
          "h": 1080
        }
      }
    ]));
  }
}
