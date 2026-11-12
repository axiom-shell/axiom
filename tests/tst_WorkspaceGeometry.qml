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

  function test_usableRect() {
    compare(WorkspaceGeometry.usableRect(1920, 1080, {
      "top": 40
    }), {
      "x": 0,
      "y": 40,
      "w": 1920,
      "h": 1040
    });
    const left = WorkspaceGeometry.usableRect(1920, 1080, {
      "left": 50
    });
    compare(left.x, 50);
    compare(left.w, 1870);
    compare(WorkspaceGeometry.usableRect(1920, 1080, null), {
      "x": 0,
      "y": 0,
      "w": 1920,
      "h": 1080
    });
    compare(WorkspaceGeometry.usableRect(1920, 1080, {
      "left": 1000,
      "right": 1000
    }).w, 1);
    compare(WorkspaceGeometry.usableRect(1920, 1080, {
      "top": -5,
      "left": -5
    }), {
      "x": 0,
      "y": 0,
      "w": 1920,
      "h": 1080
    });
  }

  function test_usableOrigin() {
    compare(WorkspaceGeometry.usableOrigin({
      "x": 1920,
      "y": 0,
      "reserved": {
        "left": 0,
        "top": 40,
        "right": 0,
        "bottom": 0
      }
    }), {
      "x": 1920,
      "y": 40
    });
    compare(WorkspaceGeometry.usableOrigin(null), {
      "x": 0,
      "y": 0
    });
    compare(WorkspaceGeometry.usableOrigin({
      "x": 5,
      "y": 7
    }), {
      "x": 5,
      "y": 7
    });
  }

  function test_windowRect_cropped() {
    // A window 10 px below a 40 px top bar's edge, the origin the usable area's
    const top = WorkspaceGeometry.windowRect({
      "x": 0,
      "y": 50,
      "w": 400,
      "h": 300
    }, 0, 40, 0.1, 192, 104);
    compare(top.y, 1);
    const side = WorkspaceGeometry.windowRect({
      "x": 60,
      "y": 0,
      "w": 400,
      "h": 300
    }, 50, 0, 0.1, 192, 108);
    compare(side.x, 1);
  }

  function test_wallpaperRect() {
    const r = WorkspaceGeometry.wallpaperRect({
      "x": 0,
      "y": 40,
      "w": 1920,
      "h": 1040
    }, 1920, 1080, 0.1);
    compare(r.x, 0);
    compare(r.y, -4);
    compare(r.w, 192);
    compare(r.h, 108);
  }

  function test_fitScale_side() {
    compare(WorkspaceGeometry.fitScale(330, 200, 100, 50, 10, 2, 1, 20), 1);
    compare(WorkspaceGeometry.fitScale(330, 200, 100, 50, 10, 2, 1), 1.6);
    compare(WorkspaceGeometry.fitScale(330, 200, 100, 50, 10, 2, 1, 0), 1.6);
  }

  function test_scratchColumn() {
    compare(WorkspaceGeometry.scratchColumn(0, 40, 30, 5, 3, 2, 10), null);
    const one = WorkspaceGeometry.scratchColumn(1, 40, 30, 5, 3, 2, 10);
    compare(one.x, 140);
    compare(one.dividerX, 135);
    compare(one.boardWidth, 180);
    compare(one.scale, 1);
    compare(one.rects[0], {
      "x": 140,
      "y": 0,
      "w": 40,
      "h": 30
    });
    const two = WorkspaceGeometry.scratchColumn(2, 40, 30, 5, 3, 2, 10);
    compare(two.scale, 1);
    compare(two.rects[0].y, 0);
    compare(two.rects[1].y, 35);
    const four = WorkspaceGeometry.scratchColumn(4, 40, 30, 5, 3, 2, 10);
    compare(four.scale, 50 / 120);
    compare(four.rects[1], {
      "x": 152,
      "y": 17,
      "w": 16,
      "h": 12
    });
  }

  function test_scratchCellAt() {
    const column = WorkspaceGeometry.scratchColumn(4, 40, 30, 5, 3, 2, 10);
    column.rects.forEach((r, i) => compare(WorkspaceGeometry.scratchCellAt(column, r.x + r.w / 2, r.y + r.h / 2), i));
    compare(WorkspaceGeometry.scratchCellAt(column, 137, 5), -1);
    const last = column.rects[3];
    compare(WorkspaceGeometry.scratchCellAt(column, last.x + 1, last.y + last.h + 3), -1);
    compare(WorkspaceGeometry.scratchCellAt(null, 150, 5), -1);
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
    compare(WorkspaceGeometry.blockBases([
      {
        "name": "DP-2",
        "description": ""
      }
    ], "", 10, profiles), {
      "DP-2": 11
    }, "a monitor with no description yet keeps its block by the connector it was last seen on");
    compare(WorkspaceGeometry.blockBases([
      {
        "name": "DP-2",
        "description": ""
      }
    ], "", 10, profiles.concat([
      {
        "outputs": [
          {
            "output": "DP-2",
            "label": "DP-2"
          }
        ]
      }
    ])), {
      "DP-2": 31
    }, "a rule naming the connector itself comes before one last seen on it");
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

  function test_orderMonitors_ignores_locale() {
    const keys = ["HDMI-A-1", "eDP-1", "desc:a", "DP-1", "dp-1"];
    compare(WorkspaceGeometry.orderMonitors(keys.map(key => ({
          "name": key,
          "key": key
        })), "").map(m => m.key), ["desc:a", "DP-1", "dp-1", "eDP-1", "HDMI-A-1"], "case-insensitive, then by code point, under any locale");
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

  // B (11..20) unplugged: the compositor left its workspaces on A
  function test_rehome_unplugged_output() {
    const monitors = [_monitors(1, 0)[0]];
    const windows = _windows([["a1", 1, 0], ["b1", 13, 0], ["b2", 13, 0], ["b3", 15, 0], ["x", 25, 0], ["s", -98, 0]]);
    const plan = WorkspaceGeometry.rehomeWorkspaces(monitors, windows, {
      "size": 10,
      "bases": {
        "A": 1
      }
    }, {
      "size": 10,
      "bases": {
        "A": 1,
        "B": 11
      }
    }, ["B"]);
    // 25 was no block's, and a special workspace isn't one: they stay
    compare(_moves(plan), "b1>2 b2>2 b3>3");
    compare(_focus(plan), "A:1");
    verify(plan.changed);
  }

  function test_rehome_shown_orphan_follows() {
    const monitors = [_monitors(13, 0)[0]];
    const windows = _windows([["a1", 1, 0], ["b1", 13, 0]]);
    const plan = WorkspaceGeometry.rehomeWorkspaces(monitors, windows, {
      "size": 10,
      "bases": {
        "A": 1
      }
    }, {
      "size": 10,
      "bases": {
        "A": 1,
        "B": 11
      }
    }, ["B"]);
    compare(_moves(plan), "b1>2");
    compare(_focus(plan), "A:2");
  }

  // An unnamed output's block moved (B, 21..30 to 11..20, as another
  // before it went): its own windows follow into it; a window put on
  // another output's ids stays
  function test_rehome_shifted_block() {
    const monitors = _monitors(1, 21);
    const windows = _windows([["a1", 1, 0], ["b1", 21, 1], ["b2", 22, 1], ["y", 5, 1]]);
    const plan = WorkspaceGeometry.rehomeWorkspaces(monitors, windows, {
      "size": 10,
      "bases": {
        "A": 1,
        "B": 11
      }
    }, {
      "size": 10,
      "bases": {
        "A": 1,
        "C": 11,
        "B": 21
      }
    }, ["C"]);
    compare(_moves(plan), "b1>11 b2>12");
    compare(_focus(plan), "B:11 A:1");
  }

  // B turned off (a profile): the compositor no longer has it, though a
  // window still reads as on it. Neither plan names B: no focus, no move
  // (it's re-homed once the compositor has moved it to A)
  function test_plans_name_only_the_outputs_on() {
    const monitors = [_monitors(1, 0)[0]];
    const windows = _windows([["a1", 1, 0], ["b1", 13, 1]]);
    const layout = {
      "blocks": true,
      "size": 10,
      "bases": {
        "A": 1
      }
    };
    const rehome = WorkspaceGeometry.rehomeWorkspaces(monitors, windows, layout, {
      "size": 10,
      "bases": {
        "A": 1,
        "B": 11
      }
    }, ["B"]);
    compare(_moves(rehome), "");
    compare(_focus(rehome), "");
    verify(!rehome.changed);
    const remap = WorkspaceGeometry.remapWorkspaces(monitors, windows, layout, layout);
    compare(_moves(remap), "");
    compare(_focus(remap), "A:1");
  }

  // Each orphan moves whole into the first workspace of A's block with no
  // window, lowest orphan first, never into one with windows
  function test_rehome_first_empty_workspaces() {
    const monitors = [_monitors(2, 0)[0]];
    const windows = _windows([["a1", 1, 0], ["a2", 2, 0], ["a4", 4, 0], ["b7", 17, 0], ["b1", 11, 0], ["b1b", 11, 0], ["b3", 13, 0]]);
    const plan = WorkspaceGeometry.rehomeWorkspaces(monitors, windows, {
      "size": 10,
      "bases": {
        "A": 1
      }
    }, {
      "size": 10,
      "bases": {
        "A": 1,
        "B": 11
      }
    }, ["B"]);
    compare(_moves(plan), "b1>3 b1b>3 b3>5 b7>6");
    compare(plan.moves.find(m => m.id === "b7").from, 17);
    compare(plan.moves.find(m => m.id === "b7").origin, "B");
    compare(_focus(plan), "A:2");
  }

  // No empty workspace left: the rest join the block's last
  function test_rehome_full_block_uses_last() {
    const monitors = [_monitors(1, 0)[0]];
    const windows = _windows([["a1", 1, 0], ["a2", 2, 0], ["b1", 4, 0], ["b2", 5, 0]]);
    const plan = WorkspaceGeometry.rehomeWorkspaces(monitors, windows, {
      "size": 3,
      "bases": {
        "A": 1
      }
    }, {
      "size": 3,
      "bases": {
        "A": 1,
        "B": 4
      }
    }, ["B"]);
    compare(_moves(plan), "b1>3 b2>3");
  }

  // A shifted block's windows (no output gone) have no origin to return to
  function test_rehome_shifted_block_has_no_origin() {
    const windows = _windows([["b1", 21, 1]]);
    const plan = WorkspaceGeometry.rehomeWorkspaces(_monitors(1, 21), windows, {
      "size": 10,
      "bases": {
        "A": 1,
        "B": 11
      }
    }, {
      "size": 10,
      "bases": {
        "A": 1,
        "C": 11,
        "B": 21
      }
    }, ["C"]);
    compare(plan.moves[0].origin, "");
  }

  function test_returnOutput_by_description_then_connector() {
    const outputs = [
      {
        "name": "DP-1",
        "description": "Work Monitor 2"
      },
      {
        "name": "DP-2",
        "description": "Home Monitor 1"
      }
    ];
    // Its monitor on another connector (sway renames them on replug)
    compare(WorkspaceGeometry.returnOutput({
      "monitor": "DP-1",
      "description": "Home Monitor 1"
    }, outputs), "DP-2");
    // A different monitor on its connector isn't it
    compare(WorkspaceGeometry.returnOutput({
      "monitor": "DP-1",
      "description": "Lab Monitor 3"
    }, outputs), "");
    // Not known yet
    compare(WorkspaceGeometry.returnOutput({
      "monitor": "DP-1",
      "description": "Work Monitor 2"
    }, [
      {
        "name": "DP-1",
        "description": ""
      }
    ]), "");
    // Two alike: the one on its connector
    compare(WorkspaceGeometry.returnOutput({
      "monitor": "DP-2",
      "description": "Twin"
    }, [
      {
        "name": "DP-1",
        "description": "Twin"
      },
      {
        "name": "DP-2",
        "description": "Twin"
      }
    ]), "DP-2");
    // No description: by connector
    compare(WorkspaceGeometry.returnOutput({
      "monitor": "HQ",
      "description": ""
    }, [
      {
        "name": "HQ",
        "description": ""
      }
    ]), "HQ");
  }

  function _record(workspace, monitor, shown) {
    return {
      "workspace": workspace,
      "monitor": monitor,
      "description": "",
      "shown": !!shown
    };
  }

  // B back: its windows go back wherever they are now (b3 moved by hand,
  // b5 already on its workspace), each workspace onto B; B, on a workspace
  // outside its block, shows the one it showed. A gone window's record is
  // dropped; one of a monitor still away stays
  function test_return_windows() {
    const records = {
      "b2": _record(12, "B"),
      "b3": _record(13, "B", true),
      "b5": _record(15, "B"),
      "gone": _record(14, "B"),
      "c1": _record(21, "C")
    };
    const windows = _windows([["a1", 1, 0], ["b2", 2, 0], ["b3", 7, 0], ["b5", 15, 0], ["c1", 3, 0]]);
    const outputs = [
      {
        "name": "A",
        "description": "",
        "active": 1
      },
      {
        "name": "B",
        "description": "",
        "active": 4
      }
    ];
    const plan = WorkspaceGeometry.returnWindows(records, windows, outputs, {
      "size": 10,
      "bases": {
        "A": 1,
        "B": 11
      }
    });
    compare(_moves(plan), "b2>12 b3>13");
    compare(plan.moves.every(m => m.monitor === "B"), true);
    compare(plan.workspaces.map(w => w.id + ">" + w.monitor).join(" "), "12>B 13>B 15>B");
    compare(_focus({
      "focus": plan.show
    }), "B:13");
    compare(plan.done.sort().join(" "), "b2 b3 b5 gone");
    verify(plan.changed);
  }

  // A workspace already on its monitor with its window there: nothing to
  // do, and a monitor on its own block keeps what it shows
  function test_return_nothing_to_move() {
    const plan = WorkspaceGeometry.returnWindows({
      "b1": _record(11, "B")
    }, _windows([["b1", 11, 1]]), [
      {
        "name": "B",
        "description": "",
        "active": 12
      }
    ], {
      "size": 10,
      "bases": {
        "B": 11
      }
    });
    verify(!plan.changed);
    compare(plan.done.join(" "), "b1");
  }

  // The monitor still away: nothing moves, the record stays
  function test_return_waits_for_its_monitor() {
    const plan = WorkspaceGeometry.returnWindows({
      "b1": _record(11, "B")
    }, _windows([["b1", 3, 0]]), [
      {
        "name": "A",
        "description": "",
        "active": 1
      }
    ], {
      "size": 10,
      "bases": {
        "A": 1
      }
    });
    verify(!plan.changed);
    compare(plan.done.length, 0);
  }

  function test_rehome_nothing_orphaned() {
    const windows = _windows([["a1", 1, 0], ["b1", 11, 1]]);
    const plan = WorkspaceGeometry.rehomeWorkspaces(_monitors(1, 11), windows, {
      "size": 10,
      "bases": {
        "A": 1,
        "B": 11
      }
    }, {
      "size": 10,
      "bases": {
        "A": 1,
        "B": 11
      }
    }, []);
    compare(plan.moves.length, 0);
    verify(!plan.changed);
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

  function test_remap_follows_a_block_order_change() {
    // A new primary, B, takes the first block: A's moves to the second
    const windows = _windows([["a1", 1, 0], ["a3", 3, 0], ["b2", 12, 1]]);
    const plan = WorkspaceGeometry.remapWorkspaces(_monitors(3, 12), windows, {
      "blocks": true,
      "size": 10,
      "bases": {
        "A": 1,
        "B": 11
      }
    }, {
      "blocks": true,
      "size": 10,
      "bases": {
        "A": 11,
        "B": 1
      }
    });
    compare(_moves(plan), "a1>11 a3>13 b2>2");
    compare(_focus(plan), "B:2 A:13");
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
