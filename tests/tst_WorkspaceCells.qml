import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "WorkspaceCells"

  function test_layout_of_equal_cells() {
    compare(WorkspaceCells.layout([20, 20, 20], 4, -1, 0), {
      "starts": [0, 24, 48],
      "lengths": [20, 20, 20],
      "total": 68
    });
  }

  function test_layout_widens_the_active_cell_by_extra() {
    const row = WorkspaceCells.layout([20, 20, 20], 4, 1, 20);
    compare(row.lengths, [20, 40, 20], "grows by one normal cell, not twice its own length");
    compare(row.starts, [0, 24, 68], "only cells after it move");
    compare(row.total, 88);
  }

  function test_layout_of_cells_of_different_lengths() {
    const row = WorkspaceCells.layout([20, 50, 20], 0, 1, 20);
    compare(row.lengths, [20, 70, 20], "a long cell grows by the normal cell's length too");
    compare(row.starts, [0, 20, 90]);
    compare(row.total, 110);
  }

  function test_layout_of_no_cells() {
    compare(WorkspaceCells.layout([], 4, -1, 0).total, 0);
  }

  function test_startOf() {
    compare(WorkspaceCells.startOf([20, 50, 20], 4, 0), 0);
    compare(WorkspaceCells.startOf([20, 50, 20], 4, 2), 78);
    compare(WorkspaceCells.startOf([20, 50, 20], 4, -1), 0, "none: the start");
    compare(WorkspaceCells.startOf([20, 50, 20], 4, 3), 102, "past the end: where a next cell would start");
  }

  function test_rowLength() {
    compare(WorkspaceCells.rowLength(1, 20, 20), 20, "one icon: a normal cell");
    // 3 × 13 + 2 × 2 + 7
    compare(WorkspaceCells.rowLength(3, 20, 20), 50);
    compare(WorkspaceCells.rowLength(0, 20, 12), 12, "never under the rest length");
  }

  function test_distinctApps() {
    const windows = [
      {
        "id": "a",
        "appId": "firefox"
      },
      {
        "id": "b",
        "appId": "Firefox"
      },
      {
        "id": "c",
        "appId": "kitty"
      },
      {
        "id": "d",
        "appId": ""
      },
      {
        "id": "e",
        "appId": ""
      }
    ];
    compare(WorkspaceCells.distinctApps(windows, 5).map(w => w.id), ["a", "c", "d", "e"], "each app once, its biggest window; no app id: each window its own");
    compare(WorkspaceCells.distinctApps(windows, 2).map(w => w.id), ["a", "c"], "at most max, biggest first");
    compare(WorkspaceCells.distinctApps([], 3), []);
  }

  function test_squareSlots() {
    compare(WorkspaceCells.squareSlots(0), []);
    compare(WorkspaceCells.squareSlots(1), [
      {
        "x": 0.5,
        "y": 0.5,
        "size": 0.65
      }
    ], "one: a full-size icon");
    const two = WorkspaceCells.squareSlots(2);
    compare(two.map(s => [s.x, s.y]), [[0.3, 0.5], [0.7, 0.5]], "two: side by side, centred");
    verify(two[0].size < 0.5, "half size");
    compare(WorkspaceCells.squareSlots(3).map(s => [s.x, s.y]), [[0.3, 0.3], [0.7, 0.3], [0.5, 0.7]], "three: two over one centred");
    compare(WorkspaceCells.squareSlots(7).length, 4, "four or more: a 2×2 block");
  }

  function test_labelFor() {
    const entries = [
      {
        "workspace": 2,
        "label": "web"
      },
      {
        "workspace": 3,
        "label": ""
      }
    ];
    compare(WorkspaceCells.labelFor(entries, 2), "web");
    compare(WorkspaceCells.labelFor(entries, 3), "", "an empty label is none");
    compare(WorkspaceCells.labelFor(entries, 4), "");
    compare(WorkspaceCells.labelFor(undefined, 1), "");
  }

  function test_nameShown() {
    compare(WorkspaceCells.nameShown("3", 3, 3), "", "Hyprland's default name is its id");
    compare(WorkspaceCells.nameShown("1", 11, 1), "", "or the relative number shown");
    compare(WorkspaceCells.nameShown("3:web", 3, 3), "3:web");
    compare(WorkspaceCells.nameShown("", 3, 3), "", "niri's unnamed ones");
  }

  function test_pick_in_priority_order() {
    compare(WorkspaceCells.pick("circle", "web", ["a"], "mail").kind, "glyph", "the grid's arrow first");
    compare(WorkspaceCells.pick("", "web", ["a"], "mail"), {
      "kind": "text",
      "text": "web"
    }, "a label of one's own before app icons");
    compare(WorkspaceCells.pick("", "", ["a"], "mail").kind, "icons", "app icons before the name");
    compare(WorkspaceCells.pick("", "", [], "mail"), {
      "kind": "name",
      "text": "mail"
    }, "a name, drawn as words even where it's an icon's name");
    compare(WorkspaceCells.pick("", "", [], "").kind, "labels");
  }
}
