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

  function test_roomed_adds_each_cells_cap_room() {
    compare(WorkspaceCells.roomed([20, 30], [
      {
        "lead": 5,
        "trail": 0
      },
      {
        "lead": 0,
        "trail": 7.5
      }
    ]), [25, 37.5]);
    compare(WorkspaceCells.roomed([20, 30], null), [20, 30], "not segments: as they are");
  }

  function test_startOf() {
    compare(WorkspaceCells.startOf([20, 50, 20], 4, 0), 0);
    compare(WorkspaceCells.startOf([20, 50, 20], 4, 2), 78);
    compare(WorkspaceCells.startOf([20, 50, 20], 4, -1), 0, "none: the start");
    compare(WorkspaceCells.startOf([20, 50, 20], 4, 3), 102, "past the end: where a next cell would start");
  }

  function test_iconSize() {
    compare(WorkspaceCells.iconSize(20), 12, "an even margin on an even cell");
    compare(WorkspaceCells.iconSize(21), 13, "and on an odd one");
    compare(WorkspaceCells.iconSize(26), 16);
  }

  function test_rowLength() {
    compare(WorkspaceCells.rowLength(1, 20, 20), 20, "one icon: a normal cell");
    // 3 × 12 + 2 × 2 + 8
    compare(WorkspaceCells.rowLength(3, 20, 20), 48);
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

  function test_byPosition() {
    const windows = [
      {
        "id": "right",
        "x": 900,
        "y": 0
      },
      {
        "id": "lowerLeft",
        "x": 0,
        "y": 500
      },
      {
        "id": "upperLeft",
        "x": 0,
        "y": 0
      },
      {
        "id": "floating",
        "x": 400,
        "y": 300,
        "floating": true
      }
    ];
    compare(WorkspaceCells.byPosition(windows).map(w => w.id), ["upperLeft", "lowerLeft", "floating", "right"], "left to right, then top to bottom, a floating one by its own place");
    compare(WorkspaceCells.byPosition([]), []);
  }

  // Biggest first: a big kitty, firefox, a small kitty, mpv
  readonly property var bySize: [
    {
      "id": "k1",
      "appId": "kitty"
    },
    {
      "id": "ff",
      "appId": "firefox"
    },
    {
      "id": "k2",
      "appId": "kitty"
    },
    {
      "id": "mpv",
      "appId": "mpv"
    }
  ]

  function test_chosen_by_size_ordered_by_place() {
    // On screen: mpv, small kitty, firefox, big kitty
    const onScreen = [bySize[3], bySize[2], bySize[1], bySize[0]];
    compare(WorkspaceCells.chosen(bySize, 2, true, onScreen).map(w => w.id), ["ff", "k1"], "the two biggest, in their order on screen");
    compare(WorkspaceCells.chosen(bySize, 4, true, onScreen).map(w => w.id), ["mpv", "k2", "ff", "k1"], "every window counts with perWindow");
  }

  function test_chosen_apps_at_their_biggest_window() {
    // The small kitty first on screen, the big one last
    const onScreen = [bySize[2], bySize[1], bySize[3], bySize[0]];
    compare(WorkspaceCells.chosen(bySize, 5, false, onScreen).map(w => w.id), ["ff", "mpv", "k1"], "kitty once, at its biggest window's place");
    compare(WorkspaceCells.chosen(bySize, 2, false, onScreen).map(w => w.id), ["ff", "k1"], "the two biggest apps, ordered by place");
  }

  function test_chosen_without_a_place() {
    compare(WorkspaceCells.chosen(bySize, 3, true, [bySize[1]]).map(w => w.id), ["ff", "k1", "k2"], "windows not on screen go last, biggest first");
    compare(WorkspaceCells.chosen([], 3, false, []), []);
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
        "show": "icon",
        "icon": "web",
        "text": "ignored"
      },
      {
        "workspace": 3,
        "show": "icon",
        "icon": "",
        "text": "hidden"
      },
      {
        "workspace": 5,
        "show": "text",
        "icon": "mail",
        "text": "mail"
      },
      {
        "workspace": 6,
        "show": "both",
        "icon": "terminal",
        "text": "dev"
      },
      {
        "workspace": 7,
        "show": "both",
        "icon": "",
        "text": "notes"
      },
      {
        "workspace": 8,
        "show": "text",
        "icon": "chat",
        "text": ""
      },
      {
        "workspace": 8,
        "icon": "chat"
      }
    ];
    const label = (icon, text, show) => ({
          "icon": icon,
          "text": text,
          "show": show
        });
    compare(WorkspaceCells.labelFor(entries, 2), label("web", "", "icon"), "Icon: the icon alone");
    compare(WorkspaceCells.labelFor(entries, 5), label("", "mail", "text"), "Text: the text alone");
    compare(WorkspaceCells.labelFor(entries, 6), label("terminal", "dev", "both"), "Both: the icon, then the text");
    compare(WorkspaceCells.labelFor(entries, 7), label("", "notes", "both"), "Both with no icon: the text");
    compare(WorkspaceCells.labelFor(entries, 8), label("chat", "", "icon"), "an entry showing nothing is skipped; no show is Icon");
    compare(WorkspaceCells.labelFor(entries, 3), label("", "", "icon"), "an empty icon is none, whatever its text");
    compare(WorkspaceCells.labelFor(entries, 4), label("", "", "icon"));
    compare(WorkspaceCells.labelFor(undefined, 1), label("", "", "icon"));
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
