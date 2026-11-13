import QtQuick
import QtTest
import qs.components.methods

// SwayState: sway's IPC replies (tests/fixtures/sway, from a nested sway) as
// the shapes the shell reads.
TestCase {
  name: "SwayState"

  RepoFiles {
    id: files
  }

  function fixture(name) {
    return files.json("tests/fixtures/sway/" + name + ".json");
  }

  function test_quote() {
    compare(SwayState.quote("DP-1"), "DP-1");
    compare(SwayState.quote("AOC CU34G4Z XJ9"), "\"AOC CU34G4Z XJ9\"");
    // Sway keeps a backslash before a quote, so a `"` is single-quoted
    compare(SwayState.quote("say \"hi\""), "\"say \"'\"'\"hi\"'\"'");
    compare(SwayState.quote("\""), "'\"'");
    compare(SwayState.quote(""), "\"\"");
    compare(SwayState.quote("it's"), "\"it's\"");
  }

  function test_treeListsTheWindows() {
    const info = SwayState.tree(fixture("get_tree"));
    compare(info.windows.map(w => w.title), ["foot", "second", "floater", "tab1", "tab2"]);
    compare(info.focusedId, "11");
    compare(info.counts, {
      "1": 2,
      "2": 1,
      "3": 2
    });
  }

  function test_layoutsAreTheTiledWindowsParents() {
    compare(SwayState.tree(fixture("get_tree")).layouts, {
      "5": "splith",
      "6": "splith",
      "11": "tabbed",
      "12": "tabbed"
    });
  }

  function test_dropSplitsOnlyAcrossTheParent() {
    const rows = [["splith", "left", ""], ["splith", "right", ""], ["splith", "top", "v"], ["splitv", "bottom", ""], ["splitv", "left", "h"], ["tabbed", "right", "h"], ["stacked", "top", "v"], [undefined, "left", "h"]];
    for (const [layout, side, split] of rows)
      compare(SwayState.dropSplit(layout, side), split, `${layout} ${side}`);
  }

  function test_window() {
    const info = SwayState.tree(fixture("get_tree"));
    const win = info.windows.find(w => w.title === "floater");
    compare(win, {
      "id": "9",
      "appId": "foot",
      "initialAppId": "foot",
      "title": "floater",
      "workspaceId": 2,
      "workspaceName": "2",
      "output": "WL-1",
      "floating": true,
      "fullscreen": false,
      "maximized": false,
      "hidden": false,
      "focusRank": undefined,
      "x": 81,
      "y": 445,
      "w": 766,
      "h": 1243
    });
  }

  function test_tabsBehindTheFrontOneAreHidden() {
    const windows = SwayState.tree(fixture("get_tree")).windows;
    compare(windows.find(w => w.title === "tab1").hidden, false);
    compare(windows.find(w => w.title === "tab2").hidden, true);
    compare(windows.find(w => w.title === "tab2").workspaceName, "3:web");
  }

  function test_aFocusedFloatingWindowHidesNoTab() {
    const leaf = (id, title) => ({
          "id": id,
          "pid": id,
          "name": title,
          "rect": {
            "x": 0,
            "y": 0,
            "width": 10,
            "height": 10
          },
          "nodes": []
        });
    const windows = SwayState.tree({
      "nodes": [
        {
          "type": "output",
          "name": "WL-1",
          "nodes": [
            {
              "type": "workspace",
              "name": "1",
              "num": 1,
              "layout": "tabbed",
              "focus": [30, 20, 10],
              "nodes": [leaf(10, "back"), leaf(20, "front")],
              "floating_nodes": [leaf(30, "floating")]
            }
          ]
        }
      ]
    }).windows;
    compare(windows.map(w => [w.title, w.hidden]), [["back", true], ["front", false], ["floating", false]]);
  }

  function test_xwaylandWindowsUseTheirClass() {
    const win = SwayState.window({
      "id": 7,
      "app_id": null,
      "window_properties": {
        "class": "steam"
      },
      "name": "Steam",
      "fullscreen_mode": 2,
      "rect": {
        "x": 0,
        "y": 0,
        "width": 10,
        "height": 10
      }
    }, {
      "num": 4,
      "name": "4"
    }, "DP-1", false, false);
    compare(win.appId, "steam");
    compare(win.fullscreen, true);
  }

  function test_focusOrderFollowsSwaysStacks() {
    compare(SwayState.tree(fixture("get_tree")).order.slice(0, 5), ["11", "12", "5", "6", "9"]);
  }

  function test_ranked() {
    const info = SwayState.tree(fixture("get_tree"));
    const ranked = SwayState.ranked(info.windows, ["9", "11"], info.order, info.focusedId);
    const rank = title => ranked.find(w => w.title === title).focusRank;
    compare(rank("tab1"), 0);
    compare(rank("floater"), 1);
    compare(rank("tab2"), 2);
    compare(rank("foot"), 3);
  }

  function test_touch() {
    compare(SwayState.touch(["a", "b", "c"], "c"), ["c", "a", "b"]);
    compare(SwayState.touch(["a", "b"], "z", 2), ["z", "a"]);
    compare(SwayState.touch(null, "a"), ["a"]);
  }

  function test_outputReservesWhatTheWorkspaceLeaves() {
    const info = SwayState.tree(fixture("get_tree"));
    const out = SwayState.output({
      "name": "WL-1",
      "x": 0,
      "y": 0,
      "width": 822,
      "height": 1336,
      "scale": 1,
      "focused": true,
      "activeWorkspace": {
        "num": 3,
        "name": "3:web"
      },
      "lastIpcObject": {
        "make": "AOC",
        "model": "CU34G4Z",
        "serial": "XJ9R7HA000000"
      }
    }, info);
    compare(out.description, "AOC CU34G4Z XJ9R7HA000000");
    compare(out.activeWorkspaceId, 3);
    compare(out.specialWorkspaceId, 0);
    compare(out.reserved, {
      "left": 48,
      "top": 58,
      "right": 8,
      "bottom": 8
    });
    // Sway takes the edge gaps off the workspace too
    compare(SwayState.output({
      "name": "WL-1",
      "x": 0,
      "y": 0,
      "width": 822,
      "height": 1336,
      "activeWorkspace": {
        "num": 3,
        "name": "3:web"
      }
    }, info, {
      "top": 8,
      "right": 8,
      "bottom": 8,
      "left": 8
    }).reserved, {
      "left": 40,
      "top": 50,
      "right": 0,
      "bottom": 0
    });
  }

  function test_outputOnANamedWorkspace() {
    const out = SwayState.output({
      "name": "WL-1",
      "activeWorkspace": {
        "id": 12,
        "num": -1,
        "name": "music"
      },
      "lastIpcObject": {
        "make": "Unknown",
        "model": "Unknown",
        "serial": "Unknown"
      }
    }, null);
    compare(out.activeWorkspaceId, -12, "a named workspace's id is minus its con id");
    compare(out.description, "");
    compare(out.reserved.top, 0);
    compare(SwayState.output({
      "name": "WL-1"
    }, null).activeWorkspaceId, -1, "unknown with no active workspace");
  }

  function test_aWindowOnANamedWorkspace() {
    const leaf = {
      "id": 7,
      "app_id": "mpv",
      "name": "video",
      "fullscreen_mode": 1
    };
    const music = SwayState.window(leaf, {
      "id": 12,
      "num": -1,
      "name": "music"
    }, "WL-1", false, false);
    compare(music.workspaceId, -12);
    compare(music.workspaceName, "music");
    compare(SwayState.window(leaf, {
      "id": 13,
      "num": -1,
      "name": "scratch"
    }, "WL-1", false, false).workspaceId, -13, "each named workspace has its own id");
    compare(SwayState.window(leaf, {
      "id": 5,
      "num": 2,
      "name": "2"
    }, "WL-1", false, false).workspaceId, 2);
  }

  function test_workspace() {
    compare(SwayState.workspace({
      "num": 3,
      "name": "3:web",
      "monitor": {
        "name": "WL-1"
      },
      "active": true,
      "focused": true,
      "urgent": true
    }, {
      "3": 2
    }), {
      "id": 3,
      "name": "3:web",
      "output": "WL-1",
      "windowCount": 2,
      "active": true,
      "focused": true,
      "urgent": true
    });
    compare(SwayState.workspace({
      "num": 4
    }, {}).urgent, false, "not urgent unless it says so");
    compare(SwayState.workspace({
      "num": -1,
      "name": "music"
    }, {}), null);
  }

  function test_keyboard() {
    compare(SwayState.keyboard(fixture("get_inputs"), ""), {
      "layouts": ["us"],
      "index": 0,
      "keymap": "English (US)"
    });
    const two = [
      {
        "type": "keyboard",
        "name": "Power Button",
        "xkb_layout_names": ["English (US)"]
      },
      {
        "type": "keyboard",
        "name": "Some Keyboard",
        "xkb_layout_names": ["English (US)", "German"],
        "xkb_active_layout_index": 1,
        "xkb_active_layout_name": "German"
      }
    ];
    compare(SwayState.keyboard(two, "us, de"), {
      "layouts": ["us", "de"],
      "index": 1,
      "keymap": "German"
    });
    compare(SwayState.keyboard(two, "us").layouts, ["us", "ge"], "no registry: guessed");
    compare(SwayState.keyboard(two, "us", {
      "layouts": [
        {
          "name": "de",
          "description": "German",
          "variants": []
        }
      ]
    }).layouts, ["us", "de"], "named through the registry");
    compare(SwayState.keyboard([], "us"), null);
  }

  function test_configInfo() {
    const info = SwayState.configInfo("set $mod Mod4\n# gaps outer 99\ngaps inner 3\ngaps outer 6\ngaps vertical 2\nworkspace 2 gaps outer 40\ninput type:keyboard {\n    xkb_layout us,de\n}\ninput * xkb_layout fr\n");
    compare(info.gaps, {
      "top": 5,
      "right": 9,
      "bottom": 5,
      "left": 9
    });
    compare(info.layouts, "fr", "sway applies its lines in order: the last wins");
    compare(SwayState.configInfo("input type:keyboard {\n    xkb_layout us,de\n    xkb_variant ,neo\n}\n").layouts, "us,de", "in a block");
    compare(SwayState.configInfo("input type:keyboard xkb_layout us,de\ninput \"1:1:AT_Translated_Set_2_keyboard\" xkb_layout fr\n").layouts, "us,de", "a device's own doesn't override every keyboard's");
    compare(SwayState.configInfo("input 1:1:kbd {\n  xkb_layout \"de\"\n}\ninput 2:2:kbd xkb_layout fr\n").layouts, "fr", "only devices': the last");
    compare(SwayState.configInfo("input type:keyboard { xkb_layout jp }\ninput 1:1:kbd xkb_layout fr\n").layouts, "jp", "a block on one line");
    compare(SwayState.configInfo(""), {
      "gaps": {
        "top": 0,
        "right": 0,
        "bottom": 0,
        "left": 0
      },
      "layouts": "",
      "blur": {
        "enabled": false,
        "size": 5,
        "passes": 2
      },
      "dim": 0
    });
    compare(SwayState.configInfo("default_dim_inactive 0.25\n").dim, 0.25, "SwayFX's dim, what turning axiom's off goes back to");
    // SwayFX's blur
    compare(SwayState.configInfo("blur enable\nblur_radius 7\nblur_passes 3\nblur_xray disable\n").blur, {
      "enabled": true,
      "size": 7,
      "passes": 3
    });
  }

  function test_outputDetails() {
    const details = SwayState.outputDetails(fixture("get_outputs"));
    compare(details.length, 2);
    const main = details[0];
    compare(main.name, "DP-1");
    compare(main.description, "AOC CU34G4Z XJ9R7HA000000");
    compare([main.width, main.height, main.refreshRate, main.x, main.y, main.scale], [3440, 1440, 240, 15, 83, 1]);
    compare(main.transform, 0);
    compare(main.disabled, false);
    compare(main.mirrorOf, "none");
    compare(main.availableModes[0], "3440x1440@240.00Hz");
    // Reads back as the mode it is (MonitorLayout)
    compare(MonitorLayout.parseMode(main.availableModes[1]).rate, 60);
    const off = details[1];
    compare(off.disabled, true);
    compare(off.transform, 5);
    compare(off.vrr, false);
  }

  function test_specialToggle() {
    const info = SwayState.tree(fixture("get_tree"));
    const marks = SwayState.marks(fixture("get_tree"));
    compare(marks, {
      "15": ["axiom-special-gaming-x"]
    });
    // In the scratchpad: shown next
    compare(SwayState.specialToggle(info.windows, marks, "gaming", "WL-1"), {
      "ids": ["15"],
      "show": true
    });
    // Shown on this output: hidden next
    const shown = info.windows.concat([Object.assign({}, info.windows[0], {
        "id": "15"
      })]);
    compare(SwayState.specialToggle(shown, marks, "gaming", "WL-1").show, false);
    compare(SwayState.specialToggle(info.windows, marks, "music", "WL-1").ids, []);
  }

  // Into a group, out of any other
  function test_specialMove() {
    const marks = {
      "15": ["axiom-special-music-15", "keep"]
    };
    compare(SwayState.specialMove(marks, "15", "gaming"), ["[con_id=15] unmark axiom-special-music-15", "[con_id=15] mark --add axiom-special-gaming-15", "[con_id=15] move scratchpad"]);
    compare(SwayState.specialMove({}, "16", "my games"), ["[con_id=16] mark --add \"axiom-special-my games-16\"", "[con_id=16] move scratchpad"]);
  }

  // A window leaving its special group on a drop
  function test_specialLeave() {
    const marks = {
      "7": ["axiom-special-term-7", "keep"]
    };
    compare(SwayState.specialLeave(marks, "7", true), ["[con_id=7] unmark axiom-special-term-7", "[con_id=7] scratchpad show", "[con_id=7] floating disable", "[con_id=7] floating enable"]);
    compare(SwayState.specialLeave(marks, "7", false), ["[con_id=7] unmark axiom-special-term-7", "[con_id=7] floating disable", "[con_id=7] floating enable"]);
    // The user's own shown scratchpad window (the unnamed special workspace, no marks): floated off and on again
    compare(SwayState.specialLeave({}, "9", false), ["[con_id=9] floating disable", "[con_id=9] floating enable"]);
  }

  // A group's name may hold "-": another group whose name it starts with
  // isn't it
  function test_specialGroup() {
    compare(SwayState.specialGroup("axiom-special-a-12"), "a");
    compare(SwayState.specialGroup("axiom-special-a-b-12"), "a-b");
    compare(SwayState.specialGroup("axiom-drop"), "");
    compare(SwayState.specialGroup("mine"), "");
    const marks = {
      "1": ["axiom-special-a-1"],
      "2": ["axiom-special-a-b-2"]
    };
    compare(SwayState.specialToggle([], marks, "a", "WL-1").ids, ["1"]);
    compare(SwayState.specialToggle([], marks, "a-b", "WL-1").ids, ["2"]);
  }

  function specialTree() {
    const leaf = (id, title, marks) => ({
          "id": id,
          "name": title,
          "pid": id,
          "nodes": [],
          "floating_nodes": [],
          "marks": marks ?? [],
          "rect": {
            "x": 0,
            "y": 0,
            "width": 10,
            "height": 10
          }
        });
    return {
      "id": 1,
      "nodes": [
        {
          "type": "output",
          "name": "__i3",
          "nodes": [
            {
              "type": "workspace",
              "name": "__i3_scratch",
              "num": -1,
              "id": 2,
              "nodes": [],
              "floating_nodes": [leaf(20, "hidden", ["axiom-special-a-20"])]
            }
          ]
        },
        {
          "type": "output",
          "name": "WL-1",
          "nodes": [
            {
              "type": "workspace",
              "name": "1",
              "num": 1,
              "id": 3,
              "nodes": [leaf(30, "plain"), leaf(31, "shown", ["axiom-special-b-31"])],
              "floating_nodes": []
            }
          ]
        }
      ]
    };
  }

  function test_treeKeepsScratchWindowsApart() {
    const info = SwayState.tree(fixture("get_tree"));
    compare(info.scratch.map(w => w.title), ["scratchy"]);
    compare(info.scratch[0].hidden, true);
    compare(info.scratch[0].output, "");
    verify(!info.windows.some(w => w.title === "scratchy"));
  }

  function test_specials() {
    const tree = specialTree();
    const info = SwayState.tree(tree);
    const marks = SwayState.marks(tree);
    const outputs = [
      {
        "name": "WL-1",
        "activeWorkspaceId": 1
      }
    ];
    const result = SwayState.specials(info, marks, outputs);
    const a = result.find(s => s.name === "a");
    compare(a.open, false);
    compare(a.output, "");
    compare(a.windows.map(w => w.title), ["hidden"]);
    const b = result.find(s => s.name === "b");
    compare(b.open, true);
    compare(b.output, "WL-1");
  }

  // Scratchpad windows with and without a group's mark; the state is what
  // tells a window shown from the scratchpad
  function unnamedTree() {
    const leaf = (id, title, marks, state) => ({
          "id": id,
          "name": title,
          "pid": id,
          "nodes": [],
          "floating_nodes": [],
          "marks": marks ?? [],
          "scratchpad_state": state ?? "none",
          "rect": {
            "x": 0,
            "y": 0,
            "width": 10,
            "height": 10
          }
        });
    return {
      "id": 1,
      "nodes": [
        {
          "type": "output",
          "name": "__i3",
          "nodes": [
            {
              "type": "workspace",
              "name": "__i3_scratch",
              "num": -1,
              "id": 2,
              "nodes": [],
              "floating_nodes": [leaf(20, "hidden", [], "fresh"), leaf(21, "grouped", ["axiom-special-a-21"], "fresh")]
            }
          ]
        },
        {
          "type": "output",
          "name": "WL-1",
          "nodes": [
            {
              "type": "workspace",
              "name": "1",
              "num": 1,
              "id": 3,
              "nodes": [leaf(30, "plain")],
              "floating_nodes": [leaf(31, "shown", [], "changed"), leaf(32, "shown marked", ["axiom-special-a-32"], "changed")]
            }
          ]
        }
      ]
    };
  }

  function test_specialsUnnamed() {
    const tree = unnamedTree();
    const info = SwayState.tree(tree);
    const marks = SwayState.marks(tree);
    compare(info.scratchIds.sort(), ["20", "21", "31", "32"], "every window that came from the scratchpad");
    const result = SwayState.specials(info, marks, []);
    compare(result.map(s => s.name), ["", "a"], "the unnamed group first, listed because it has windows");
    const unnamed = result[0];
    compare(unnamed.windows.map(w => w.title).sort(), ["hidden", "shown"], "a marked window is not in it");
    compare(unnamed.windowCount, 2);
    compare(unnamed.open, true);
    compare(unnamed.output, "WL-1");
    const bare = SwayState.tree({
      "id": 1,
      "nodes": []
    });
    compare(SwayState.specials(bare, {}, []), [], "no scratchpad windows, no unnamed group");
  }

  function test_specialToggleUnnamed() {
    const tree = unnamedTree();
    const info = SwayState.tree(tree);
    const marks = SwayState.marks(tree);
    // Shown on WL-1 (31): hide
    compare(SwayState.specialToggle(info.windows, marks, "", "WL-1", info.scratchIds), {
      "ids": ["20", "31"],
      "show": false
    });
    // None shown there: show every one
    compare(SwayState.specialToggle([], marks, "", "WL-1", info.scratchIds).show, true);
    compare(SwayState.specialToggle(info.windows, marks, "a", "WL-1", info.scratchIds).ids.sort(), ["21", "32"], "a group is unchanged");
  }

  function test_windowCommands() {
    const windows = [
      {
        "id": "4",
        "fullscreen": false
      },
      {
        "id": "7",
        "fullscreen": false
      },
      {
        "id": "9",
        "fullscreen": true
      }
    ];
    const opacity = {
      "active": 100,
      "inactive": 85,
      "fullscreen": 100
    };
    const first = SwayState.windowCommands(windows, "4", {
      "opacity": opacity
    }, {}, 0);
    compare(first.lines, ["[con_id=4] opacity 1", "[con_id=7] opacity 0.85", "[con_id=9] opacity 1"]);
    // Focus moves: only the two windows that change
    const moved = SwayState.windowCommands(windows, "7", {
      "opacity": opacity
    }, first.applied, 0);
    compare(moved.lines, ["[con_id=4] opacity 0.85", "[con_id=7] opacity 1"]);
    // Turned off: every window back
    compare(SwayState.windowCommands(windows, "7", null, moved.applied, 0).lines, ["[all] opacity 1"]);
    compare(SwayState.windowCommands(windows, "7", {}, {}, 0).lines, [], "nothing set, nothing to take back");
    // SwayFX: blur, shadows and dim on every window, not just the focused one
    const fx = {
      "opacity": opacity,
      "blur": true,
      "shadows": true,
      "dim": 0.15
    };
    const all = SwayState.windowCommands(windows, "7", fx, moved.applied, 0);
    compare(all.lines, ["[con_id=4] blur enable, shadows enable, dim_inactive 0.15", "[con_id=7] blur enable, shadows enable, dim_inactive 0.15", "[con_id=9] blur enable, shadows enable, dim_inactive 0.15"]);
    // A window opened later gets them too; the others are already set
    const opened = SwayState.windowCommands(windows.concat([
      {
        "id": "12",
        "fullscreen": false
      }
    ]), "7", fx, all.applied, 0);
    compare(opened.lines, ["[con_id=12] opacity 0.85, blur enable, shadows enable, dim_inactive 0.15"]);
    // Window blur off while the part stays on: off on each
    compare(SwayState.windowCommands([windows[0]], "7", Object.assign({}, fx, {
      "blur": false
    }), all.applied, 0).lines, ["[con_id=4] blur disable"]);
    // Dim off: back to the config's default; blur and shadows left alone
    // (null: the reload turning their part off takes them back)
    compare(SwayState.windowCommands(windows, "7", {
      "opacity": opacity
    }, all.applied, 0.1).lines, ["[all] dim_inactive 0.1"]);
  }
}
