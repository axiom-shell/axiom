import QtQuick
import QtTest
import qs.components.methods

// NiriState: niri's IPC replies and events (tests/fixtures/niri, from a
// nested niri) as the shapes the shell reads.
TestCase {
  name: "NiriState"

  RepoFiles {
    id: files
  }

  function fixture(name) {
    return files.json("tests/fixtures/niri/" + name + ".json");
  }

  // The state the fixtures' replies give
  function loaded() {
    let state = NiriState.empty();
    state = NiriState.reduce(state, {
      "WorkspacesChanged": {
        "workspaces": fixture("workspaces")
      }
    });
    return NiriState.reduce(state, {
      "WindowsChanged": {
        "windows": fixture("windows")
      }
    });
  }

  readonly property var bases: ({
      "winit": 1
    })

  function test_workspaces() {
    const list = NiriState.workspaces(loaded(), bases, 10);
    compare(list.map(ws => ws.id), [1, 2, 3]);
    compare(list[0], {
      "id": 1,
      "name": "",
      "output": "winit",
      "windowCount": 3,
      "active": true,
      "focused": true
    });
    // Past the block, or on an output without one: no id of axiom's
    compare(NiriState.workspaces(loaded(), bases, 2).map(ws => ws.id), [1, 2]);
    compare(NiriState.workspaces(loaded(), {}, 10), []);
    compare(NiriState.workspaceId({
      "output": "winit",
      "idx": 3
    }, {
      "winit": 11
    }, 10), 13);
  }

  function test_outputs() {
    const outputs = NiriState.outputs(fixture("outputs"), loaded(), bases, 10);
    compare(outputs.length, 1);
    compare(outputs[0].name, "winit");
    compare(outputs[0].description, "Smithay Winit");
    compare(outputs[0].width, 1691);
    compare(outputs[0].focused, true);
    compare(outputs[0].activeWorkspaceId, 1);
    compare(NiriState.focusedOutput(loaded()), "winit");
    compare(outputs[0].reserved.top, 0, "nothing reserved without axiom's layers");
  }

  // niri doesn't say what layers reserve: an output's is axiom's own
  function test_outputs_reserved() {
    const reserved = {
      "top": 40,
      "right": 0,
      "bottom": 8,
      "left": 0
    };
    const outputs = NiriState.outputs(fixture("outputs"), loaded(), bases, 10, {
      "winit": reserved,
      "gone": {
        "top": 99,
        "right": 0,
        "bottom": 0,
        "left": 0
      }
    });
    compare(outputs[0].reserved, reserved);
  }

  function test_windows() {
    const outputs = NiriState.outputs(fixture("outputs"), loaded(), bases, 10);
    const windows = NiriState.windows(loaded(), outputs, bases, 10, 16);
    const byId = id => windows.find(w => w.id === id);
    // The floating window is where niri says, and focused
    compare(byId("5").floating, true);
    compare(byId("5").x, 870);
    compare(byId("5").focusRank, 0);
    compare(byId("5").column, undefined);
    // Tiled ones are laid out from their column and place in it
    compare(byId("2").column, 1);
    compare(byId("3").tile, 2);
    compare(byId("2").x, 16);
    compare(byId("2").y, 16);
    compare(byId("3").y, 16 + 602 + 16);
    compare(byId("4").workspaceId, 2);
    compare(byId("2").fullscreen, false);
    // The strip fits on its output: a tiled window covers its column, the
    // output's height; a floating one has no cover (its place is niri's)
    compare(byId("3").cover, {
      "x": 16,
      "y": 0,
      "w": 810,
      "h": outputs[0].height
    });
    compare(byId("5").cover, undefined);
    // Ranked by niri's focus timestamps
    compare(windows.slice().sort((a, b) => a.focusRank - b.focusRank).map(w => w.id), ["5", "3", "4", "2"]);
    compare(NiriState.focusedWindowId(loaded()), "5");
  }

  // A strip wider than its output fills the view wherever niri scrolled it
  function test_wideStripCoversTheOutput() {
    let state = loaded();
    const win = Object.assign({}, state.windows["2"]);
    win.layout = Object.assign({}, win.layout, {
      "pos_in_scrolling_layout": [2, 1],
      "tile_size": [1200, 1295]
    });
    state = NiriState.reduce(state, {
      "WindowOpenedOrChanged": {
        "window": win
      }
    });
    const outputs = NiriState.outputs(fixture("outputs"), state, bases, 10);
    const cover = NiriState.windows(state, outputs, bases, 10, 16).find(w => w.id === "3").cover;
    compare(cover.x, outputs[0].x);
    compare(cover.w, outputs[0].width);
  }

  function test_fullscreenIsATileAsBigAsItsOutput() {
    let state = loaded();
    const win = Object.assign({}, state.windows["2"]);
    win.layout = Object.assign({}, win.layout, {
      "tile_size": [1691, 1327]
    });
    state = NiriState.reduce(state, {
      "WindowOpenedOrChanged": {
        "window": win
      }
    });
    const outputs = NiriState.outputs(fixture("outputs"), state, bases, 10);
    compare(NiriState.windows(state, outputs, bases, 10, 16).find(w => w.id === "2").fullscreen, true);
  }

  // The event stream captured while focusing, opening and closing windows
  function test_eventStream() {
    let state = NiriState.empty();
    const lines = files.text("tests/fixtures/niri/events.jsonl").split("\n").filter(line => line !== "");
    for (const line of lines)
      state = NiriState.reduce(state, JSON.parse(line));
    compare(Object.keys(state.windows).sort(), ["3", "4", "5", "6"]);
    compare(NiriState.focusedWindowId(state), "3");
    compare(state.windows["3"].layout.tile_size, [684, 1226]);
    compare(state.windows["3"].focus_timestamp.secs, 8773);
    compare(state.configFailed, false);
    compare(NiriState.keyboard(state, ""), {
      "layouts": ["us"],
      "index": 0,
      "keymap": "English (US)"
    });
  }

  function test_reduceFocusAndWorkspaces() {
    let state = loaded();
    state = NiriState.reduce(state, {
      "WorkspaceActivated": {
        "id": 2,
        "focused": true
      }
    });
    compare(state.workspaces["1"].is_active, false);
    compare(state.workspaces["2"].is_active, true);
    compare(state.workspaces["2"].is_focused, true);
    compare(state.workspaces["1"].is_focused, false);
    // A workspace the switch doesn't change stays the same object
    const before = state;
    state = NiriState.reduce(state, {
      "WorkspaceActivated": {
        "id": 2,
        "focused": false
      }
    });
    verify(state.workspaces["1"] === before.workspaces["1"]);
    state = NiriState.reduce(state, {
      "WindowFocusChanged": {
        "id": null
      }
    });
    compare(NiriState.focusedWindowId(state), "");
    state = NiriState.reduce(state, {
      "WindowClosed": {
        "id": 5
      }
    });
    verify(!("5" in state.windows));
    // An event holding nothing of the state leaves it as it is
    compare(NiriState.reduce(state, {
      "CastsChanged": {
        "casts": []
      }
    }), state);
  }

  function test_outputDetails() {
    compare(NiriState.outputDetails(fixture("outputs")), [
      {
        "name": "winit",
        "description": "Smithay Winit",
        "width": 1691,
        "height": 1327,
        "refreshRate": 60,
        "x": 0,
        "y": 0,
        "scale": 1,
        "transform": 6,
        "disabled": false,
        "mirrorOf": "none",
        "vrr": false,
        "availableModes": ["1691x1327@60.00Hz"]
      }
    ]);
  }
}
