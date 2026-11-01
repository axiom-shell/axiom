import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "WorkspaceGeometry"

  function test_fitScale() {
    // 2×1 monitors of 100×50, 10 apart, in 210×200: width-bound at 1
    compare(WorkspaceGeometry.fitScale(210, 200, 100, 50, 10, 2, 1), 1);
    compare(WorkspaceGeometry.fitScale(210, 30, 100, 50, 10, 2, 1), 0.6);
    compare(WorkspaceGeometry.fitScale(10, 10, 0, 50, 0, 1, 1), 0.1);
  }

  function test_cellRect_and_cellAt_agree() {
    for (let i = 0; i < 5; i++) {
      const r = WorkspaceGeometry.cellRect(i, 40, 30, 5, 3);
      compare(WorkspaceGeometry.cellAt(r.x + 1, r.y + 1, 40, 30, 5, 3, 5), i);
    }
  }

  function test_cellAt_misses() {
    compare(WorkspaceGeometry.cellAt(42, 1, 40, 30, 5, 3, 5), -1, "gap");
    compare(WorkspaceGeometry.cellAt(-1, 1, 40, 30, 5, 3, 5), -1, "outside");
    compare(WorkspaceGeometry.cellAt(91, 36, 40, 30, 5, 3, 5), -1, "past the last cell");
  }

  function test_windowRect_clamps_into_the_cell() {
    const r = WorkspaceGeometry.windowRect({
      "x": 1900,
      "y": 1000,
      "w": 400,
      "h": 300
    }, 1000, 0, 0.1, 100, 60);
    compare(r.w, 40);
    compare(r.h, 30);
    compare(r.x, 60);
    compare(r.y, 30);
    const tiny = WorkspaceGeometry.windowRect({}, 0, 0, 0.1, 100, 60);
    compare(tiny.w, 8);
  }

  function test_stripRects_squeeze_the_strip_into_the_cell() {
    // Three 1000 px columns on a 2000 px monitor, the first scrolled half
    // off it: 3000 px of strip from -500 squeezed into a 100 px cell
    const wins = [-500, 500, 1500].map(x => ({
          "x": x,
          "y": 0,
          "w": 1000,
          "h": 1000
        }));
    const rects = WorkspaceGeometry.stripRects(wins, 0, 0, 0.05, 100, 50, false);
    compare(rects.map(r => Math.round(r.x)), [0, 33, 67]);
    compare(Math.round(rects[0].w), 33);
    compare(rects[0].h, 50);
    // A strip that fits stays as windowRect has it
    const fits = WorkspaceGeometry.stripRects([wins[1]], 0, 0, 0.05, 100, 50, false);
    compare(fits[0], WorkspaceGeometry.windowRect(wins[1], 0, 0, 0.05, 100, 50));
    // Vertical: squeezed down the cell instead
    const rows = WorkspaceGeometry.stripRects([0, 1000].map(y => ({
          "x": 0,
          "y": y,
          "w": 2000,
          "h": 1000
        })), 0, 0, 0.05, 100, 50, true);
    compare(rows.map(r => r.y), [0, 25]);
    compare(rows[0].h, 25);
  }

  function test_stripOrder() {
    const wins = [
      {
        "id": "float",
        "floating": true,
        "x": 0,
        "y": 0
      },
      {
        "id": "right",
        "x": 900,
        "y": 0
      },
      {
        "id": "lower",
        "x": -400,
        "y": 500
      },
      {
        "id": "upper",
        "x": -400,
        "y": 0
      }
    ];
    compare(WorkspaceGeometry.stripOrder(wins, false).map(w => w.id), ["upper", "lower", "right", "float"]);
    compare(WorkspaceGeometry.stripOrder(wins, true).map(w => w.id), ["upper", "right", "lower", "float"]);
  }

  function test_stripDropTarget_goes_after_the_nearest() {
    const items = [
      {
        "id": "a",
        "rect": {
          "x": 0,
          "y": 0,
          "w": 40,
          "h": 60
        }
      },
      {
        "id": "b",
        "rect": {
          "x": 50,
          "y": 0,
          "w": 40,
          "h": 60
        }
      }
    ];
    const target = WorkspaceGeometry.stripDropTarget(items, 55, 10, false);
    compare(target.id, "b");
    compare(target.side, "right");
    compare(target.rect.x, 70);
    compare(WorkspaceGeometry.stripDropTarget(items, 5, 10, true).side, "bottom");
    compare(WorkspaceGeometry.stripDropTarget([], 5, 10, false), null);
  }

  function test_windowAt_prefers_floating() {
    const items = [
      {
        "id": "tiled",
        "floating": false,
        "rect": {
          "x": 0,
          "y": 0,
          "w": 100,
          "h": 100
        }
      },
      {
        "id": "float",
        "floating": true,
        "rect": {
          "x": 10,
          "y": 10,
          "w": 20,
          "h": 20
        }
      },
      {
        "id": "top",
        "floating": false,
        "rect": {
          "x": 0,
          "y": 0,
          "w": 50,
          "h": 50
        }
      }
    ];
    compare(WorkspaceGeometry.windowAt(items, 15, 15), "float");
    compare(WorkspaceGeometry.windowAt(items, 40, 40), "top");
    compare(WorkspaceGeometry.windowAt(items, 200, 200), "");
  }

  function test_dropTarget_splits_the_long_side() {
    const wide = [
      {
        "id": "w",
        "rect": {
          "x": 0,
          "y": 0,
          "w": 200,
          "h": 100
        }
      }
    ];
    const right = WorkspaceGeometry.dropTarget(wide, 150, 50, 1);
    compare(right.side, "right");
    compare(right.rect.x, 100);
    compare(right.rect.w, 100);
    // Multiplier 3: 200 wide is not > 300, so it splits top/bottom
    compare(WorkspaceGeometry.dropTarget(wide, 150, 10, 3).side, "top");
    compare(WorkspaceGeometry.dropTarget([], 0, 0, 1), null);
  }

  function test_resizeEdges() {
    const r = {
      "x": 0,
      "y": 0,
      "w": 90,
      "h": 90
    };
    const corner = WorkspaceGeometry.resizeEdges(r, 5, 85);
    verify(corner.left && corner.bottom && !corner.right && !corner.top);
    const middle = WorkspaceGeometry.resizeEdges(r, 40, 35);
    compare([middle.left, middle.right, middle.top, middle.bottom], [false, false, true, false]);
  }

  function test_stripOrderByColumn() {
    // niri says the column and the place in it; positions are unknown (0)
    const wins = [
      {
        "id": "b",
        "column": 2,
        "tile": 1
      },
      {
        "id": "a2",
        "column": 1,
        "tile": 2
      },
      {
        "id": "float",
        "floating": true
      },
      {
        "id": "a1",
        "column": 1,
        "tile": 1
      }
    ];
    compare(WorkspaceGeometry.stripOrder(wins, false).map(w => w.id), ["a1", "a2", "b", "float"]);
  }

  function test_blockBases() {
    const outputs = [
      {
        "name": "HDMI-A-1",
        "description": "c"
      },
      {
        "name": "DP-1",
        "description": "a"
      }
    ];
    compare(WorkspaceGeometry.blockBases(outputs, "", 10), {
      "DP-1": 1,
      "HDMI-A-1": 11
    });
    compare(WorkspaceGeometry.blockBases(outputs, "HDMI-A-1", 5), {
      "HDMI-A-1": 1,
      "DP-1": 6
    });
    compare(WorkspaceGeometry.blockBases([], "", 5), {});
  }

  function test_blockBases_profiles() {
    const profiles = [
      {
        "outputs": [
          {
            "output": "desc:a",
            "label": "DP-1"
          },
          {
            "output": "desc:b",
            "label": "DP-2"
          }
        ]
      },
      {
        "outputs": [
          {
            "output": "desc:b",
            "label": "DP-2"
          },
          {
            "output": "desc:c",
            "label": "HDMI-A-1"
          }
        ]
      }
    ];
    const all = [
      {
        "name": "DP-1",
        "description": "a"
      },
      {
        "name": "DP-2",
        "description": "b"
      },
      {
        "name": "HDMI-A-1",
        "description": "c"
      }
    ];
    compare(WorkspaceGeometry.blockBases(all, "", 100, profiles), {
      "DP-1": 1,
      "DP-2": 101,
      "HDMI-A-1": 201
    });
    compare(WorkspaceGeometry.blockBases([all[0], all[2]], "", 100, profiles), {
      "DP-1": 1,
      "HDMI-A-1": 201
    }, "a middle monitor unplugged moves no block");
    compare(WorkspaceGeometry.blockBases([all[0], all[1]], "HDMI-A-1", 100, profiles), {
      "DP-1": 101,
      "DP-2": 201
    }, "the unplugged primary keeps the first block by its label");
    compare(WorkspaceGeometry.blockBases([
      {
        "name": "DP-3",
        "description": "0 unknown"
      },
      all[1]], "", 100, profiles), {
      "DP-2": 101,
      "DP-3": 301
    }, "an unknown monitor goes after every named one");
    compare(WorkspaceGeometry.blockBases([
      {
        "name": "DP-9",
        "description": "c"
      }
    ], "", 10, profiles), {
      "DP-9": 21
    }, "a named monitor on another port keeps its block");
  }

  function test_outputToward() {
    const outputs = [
      {
        "name": "A",
        "x": 0,
        "y": 0,
        "width": 1920,
        "height": 1080
      },
      {
        "name": "B",
        "x": 1920,
        "y": 0,
        "width": 2560,
        "height": 1440
      },
      {
        "name": "C",
        "x": 1920,
        "y": 1440,
        "width": 1920,
        "height": 1080
      }
    ];
    compare(WorkspaceGeometry.outputToward(outputs, "A", "right"), "B", "the one beside beats the one diagonally");
    compare(WorkspaceGeometry.outputToward(outputs, "B", "left"), "A");
    compare(WorkspaceGeometry.outputToward(outputs, "B", "down"), "C");
    compare(WorkspaceGeometry.outputToward(outputs, "A", "left"), "", "none that way");
    compare(WorkspaceGeometry.outputToward(outputs, "A", "up"), "");
    compare(WorkspaceGeometry.outputToward(outputs.slice(0, 1), "A", "right"), "", "one monitor");
    compare(WorkspaceGeometry.outputToward(outputs, "X", "right"), "", "unknown output");
  }

  function test_orderMonitors_primary_first_then_by_key() {
    const monitors = [
      {
        "id": 2,
        "name": "HDMI-A-1",
        "key": "desc:c"
      },
      {
        "id": 0,
        "name": "DP-1",
        "key": "desc:a"
      },
      {
        "id": 1,
        "name": "DP-2",
        "key": "desc:b"
      }
    ];
    const ordered = WorkspaceGeometry.orderMonitors(monitors, "DP-2");
    compare(ordered.map(m => m.name), ["DP-2", "DP-1", "HDMI-A-1"]);
  }

  function test_orderMonitors_no_primary_connected_falls_back_to_key_order() {
    const monitors = [
      {
        "id": 2,
        "name": "HDMI-A-1",
        "key": "desc:c"
      },
      {
        "id": 0,
        "name": "DP-1",
        "key": "desc:a"
      }
    ];
    const ordered = WorkspaceGeometry.orderMonitors(monitors, "DP-2");
    compare(ordered.map(m => m.name), ["DP-1", "HDMI-A-1"]);
  }

  function test_orderMonitors_ignores_hyprland_connection_order() {
    const a = {
      "id": 0,
      "name": "DP-1",
      "key": "desc:a"
    };
    const b = {
      "id": 1,
      "name": "DP-2",
      "key": "desc:b"
    };
    const c = {
      "id": 2,
      "name": "HDMI-A-1",
      "key": "desc:c"
    };
    const expected = ["DP-2", "DP-1", "HDMI-A-1"];
    compare(WorkspaceGeometry.orderMonitors([a, b, c], "DP-2").map(m => m.name), expected);
    compare(WorkspaceGeometry.orderMonitors([c, a, b], "DP-2").map(m => m.name), expected);
    compare(WorkspaceGeometry.orderMonitors([b, c, a], "DP-2").map(m => m.name), expected);
  }

  function test_orderMonitors_survives_reconnect_by_key_not_name() {
    // DP-1 replugged into a different port: id/name change, key (the
    // description-based identity) stays the same.
    const monitors = [
      {
        "id": 5,
        "name": "DP-3",
        "key": "desc:a"
      },
      {
        "id": 1,
        "name": "DP-2",
        "key": "desc:b"
      }
    ];
    compare(WorkspaceGeometry.orderMonitors(monitors, "DP-2").map(m => m.key), ["desc:b", "desc:a"]);
  }

  function test_orderMonitors_removed_and_appended() {
    const a = {
      "id": 0,
      "name": "DP-1",
      "key": "desc:a"
    };
    const c = {
      "id": 2,
      "name": "HDMI-A-1",
      "key": "desc:c"
    };
    const d = {
      "id": 3,
      "name": "DP-3",
      "key": "desc:d"
    };
    // B disconnects, D connects later (appended, as Hyprland's own list
    // would do) — A and C should keep their relative order.
    compare(WorkspaceGeometry.orderMonitors([a, c, d], "").map(m => m.key), ["desc:a", "desc:c", "desc:d"]);
  }

  // Two monitors, A (id 0, primary) focused and B (id 1)
  function _monitors(activeA, activeB) {
    return [
      {
        "id": 0,
        "name": "A",
        "block": 0,
        "active": activeA,
        "focused": true
      },
      {
        "id": 1,
        "name": "B",
        "block": 1,
        "active": activeB,
        "focused": false
      }
    ];
  }

  function _windows(list) {
    return list.map(([id, workspace, monitor]) => ({
          "id": id,
          "workspace": workspace,
          "output": ["A", "B"][monitor]
        }));
  }

  function _moves(plan) {
    return plan.moves.map(m => m.id + ">" + m.to).sort().join(" ");
  }

  function _focus(plan) {
    return plan.focus.map(f => f.monitor + ":" + f.id).join(" ");
  }

  function test_remap_standard_to_perMonitor() {
    const windows = _windows([["a1", 1, 0], ["a2", 2, 0], ["b1", 3, 1], ["b2", 4, 1], ["b3", 4, 1]]);
    const plan = WorkspaceGeometry.remapWorkspaces(_monitors(1, 3), windows, {
      "blocks": false,
      "size": 10
    }, {
      "blocks": true,
      "size": 10
    });
    compare(_moves(plan), "b1>13 b2>14 b3>14");
    compare(_focus(plan), "B:13 A:1");
    verify(plan.changed);
  }

  function test_remap_perMonitor_to_standard_collides() {
    const windows = _windows([["a1", 1, 0], ["a2", 2, 0], ["b1", 11, 1], ["b2", 12, 1], ["b3", 15, 1]]);
    const plan = WorkspaceGeometry.remapWorkspaces(_monitors(2, 11), windows, {
      "blocks": true,
      "size": 10
    }, {
      "blocks": false,
      "size": 10
    });
    // 1 and 2 are A's, so B's first two take the first free ids
    compare(_moves(plan), "b1>3 b2>4 b3>5");
    compare(_focus(plan), "B:3 A:2");
  }

  function test_remap_shifted_block_does_not_chain() {
    // perMonitor 10 → grid 3×3: B's block moves from 11..20 to 10..18
    const windows = _windows([["a1", 1, 0], ["a10", 10, 0], ["b11", 11, 1], ["b12", 12, 1]]);
    const plan = WorkspaceGeometry.remapWorkspaces(_monitors(10, 12), windows, {
      "blocks": true,
      "size": 10
    }, {
      "blocks": true,
      "size": 9
    });
    compare(_moves(plan), "a10>2 b11>10 b12>11");
    compare(_focus(plan), "B:11 A:2");
  }

  function test_remap_shrinking_uses_free_ids() {
    const windows = _windows([["a1", 1, 0], ["a3", 3, 0], ["a7", 7, 0], ["a9", 9, 0]]);
    const plan = WorkspaceGeometry.remapWorkspaces(_monitors(7, 11), windows, {
      "blocks": true,
      "size": 10
    }, {
      "blocks": true,
      "size": 3
    });
    // 1 and 3 keep their place, 7 takes the only free id, 9 merges into the last
    compare(_moves(plan), "a7>2 a9>3");
    compare(_focus(plan), "B:4 A:2");
  }

  function test_remap_unchanged_is_a_no_op() {
    const windows = _windows([["a1", 1, 0], ["b1", 12, 1], ["s", -98, 1]]);
    const layout = {
      "blocks": true,
      "size": 10
    };
    const plan = WorkspaceGeometry.remapWorkspaces(_monitors(1, 12), windows, layout, layout);
    compare(plan.moves.length, 0);
    verify(!plan.changed);
  }

  function test_remap_reconcile_rehomes_stuck_workspaces() {
    // B shows 3, left over from the standard layout
    const windows = _windows([["a1", 1, 0], ["b3", 3, 1]]);
    const layout = {
      "blocks": true,
      "size": 10
    };
    const plan = WorkspaceGeometry.remapWorkspaces(_monitors(1, 3), windows, layout, layout);
    compare(_moves(plan), "b3>11");
    compare(_focus(plan), "B:11 A:1");
  }

  function test_remap_follows_the_blocks_not_the_places() {
    // B's block is the third (a monitor between them is unplugged)
    const monitors = _monitors(1, 22);
    monitors[1].block = 2;
    const windows = _windows([["a1", 1, 0], ["b2", 22, 1]]);
    const plan = WorkspaceGeometry.remapWorkspaces(monitors, windows, {
      "blocks": true,
      "size": 10
    }, {
      "blocks": true,
      "size": 100
    });
    compare(_moves(plan), "b2>202");
    compare(_focus(plan), "B:202 A:1");
  }

  function test_centreWorkspace() {
    compare(WorkspaceGeometry.centreWorkspace(1, 3, 3), 5, "3 × 3: the middle");
    compare(WorkspaceGeometry.centreWorkspace(10, 3, 3), 14, "a second block's middle");
    compare(WorkspaceGeometry.centreWorkspace(1, 4, 4), 11, "4 × 4: after the middle, right and down");
    compare(WorkspaceGeometry.centreWorkspace(1, 5, 1), 3, "one row");
    compare(WorkspaceGeometry.centreWorkspace(1, 1, 1), 1, "one cell");
  }

  function test_centreFocus() {
    // 3 × 3 blocks: A owns 1-9, B 10-18
    const start = WorkspaceGeometry.centreFocus(_monitors(1, 2), 9, 3, 3, true);
    compare(_focus(start), "B:14 A:5", "both where the compositor started them, the focused one last");
    verify(start.changed);
    const moved = WorkspaceGeometry.centreFocus(_monitors(1, 12), 9, 3, 3, true);
    compare(_focus(moved), "B:12 A:5", "B already moved within its block: kept");
    const all = WorkspaceGeometry.centreFocus(_monitors(3, 12), 9, 3, 3, false);
    compare(_focus(all), "B:14 A:5", "turning the grid on: every monitor");
    verify(!WorkspaceGeometry.centreFocus(_monitors(5, 14), 9, 3, 3, false).changed, "already there");
  }
}
