import QtQuick
import QtTest
import qs.components.methods

// BindConditions: a keybind's "Only when" (compositor, layout, monitors),
// the rule the daemon's render.BindHolds follows too (its cases are
// recorded as shared fixtures and replayed in Go), and which binds can
// share a key.
TestCase {
  id: test
  name: "BindConditions"

  Shared {
    id: shared
    testCase: test
  }

  readonly property var tiling: ({
      "kind": "hyprland",
      "strips": false,
      "grid": false,
      "dynamic": false,
      "outputs": ["DP-1"]
    })
  readonly property var niri: ({
      "kind": "niri",
      "strips": true,
      "grid": false,
      "dynamic": true,
      "outputs": ["eDP-1"]
    })

  function _holds(bind, facts) {
    return shared.calls.BindConditions.holds(bind, facts);
  }

  function _unmet(bind, facts) {
    return shared.calls.BindConditions.unmet(bind, facts);
  }

  function test_noConditionAlwaysHolds() {
    verify(_holds({
      "action": "launcher"
    }, test.tiling));
    verify(_holds({
      "action": "launcher",
      "whenCompositors": [],
      "whenLayout": "",
      "whenMonitors": ""
    }, test.niri));
  }

  function test_compositors() {
    const bind = {
      "action": "closeWindow",
      "whenCompositors": ["niri"]
    };
    compare(_unmet(bind, test.tiling), "compositor");
    verify(_holds(bind, test.niri));
    const either = {
      "action": "closeWindow",
      "whenCompositors": ["hyprland", "sway"]
    };
    verify(_holds(either, test.tiling));
    compare(_unmet(either, test.niri), "compositor");
  }

  // A raw command's own compositor is BindActions.appliesUnder's, so
  // unmet doesn't turn it down for another compositor
  function test_rawCompositorNotHere() {
    verify(_holds({
      "action": "raw",
      "compositor": "sway"
    }, test.niri));
    compare(_unmet({
      "action": "raw",
      "compositor": "sway"
    }, test.niri), "");
  }

  // A strip action needs strips whatever its own layout says; Hyprland
  // only supporting them isn't enough
  function test_layouts() {
    compare(_unmet({
      "action": "stripWider"
    }, test.tiling), "strips");
    verify(_holds({
      "action": "stripWider"
    }, test.niri));
    compare(_unmet({
      "action": "stripWider",
      "whenLayout": "grid"
    }, test.niri), "grid", "its own layout first");
    verify(_holds({
      "action": "toggleSplit",
      "whenLayout": "tiling"
    }, test.tiling));
    compare(_unmet({
      "action": "toggleSplit",
      "whenLayout": "tiling"
    }, test.niri), "tiling");
    verify(_holds({
      "action": "workspaceStep",
      "whenLayout": "grid"
    }, Object.assign({}, test.tiling, {
      "grid": true
    })));
    verify(_holds({
      "action": "workspaceStep",
      "whenLayout": "dynamic"
    }, test.niri));
    compare(_unmet({
      "action": "workspaceStep",
      "whenLayout": "dynamic"
    }, test.tiling), "dynamic");
  }

  // The laptop's own panel is eDP, LVDS or DSI; unknown outputs hold
  // neither
  function test_monitors() {
    const docked = {
      "action": "launcher",
      "whenMonitors": "external"
    };
    const laptop = {
      "action": "launcher",
      "whenMonitors": "laptopOnly"
    };
    verify(_holds(docked, test.tiling));
    compare(_unmet(laptop, test.tiling), "laptopOnly");
    verify(_holds(laptop, test.niri));
    compare(_unmet(docked, test.niri), "external");
    const both = Object.assign({}, test.tiling, {
      "outputs": ["eDP-1", "HDMI-A-1"]
    });
    verify(_holds(docked, both));
    verify(!_holds(laptop, both));
    for (const outputs of [null, []]) {
      const unknown = Object.assign({}, test.tiling, {
        "outputs": outputs
      });
      verify(!_holds(docked, unknown), "external with " + JSON.stringify(outputs));
      verify(!_holds(laptop, unknown), "laptopOnly with " + JSON.stringify(outputs));
    }
  }

  function test_conditional() {
    verify(!BindConditions.conditional({
      "action": "stripWider"
    }), "a strip action's own need isn't a condition set");
    verify(BindConditions.conditional({
      "action": "launcher",
      "whenMonitors": "external"
    }));
  }

  function test_exclusive_data() {
    return [
      {
        "tag": "no compositor in common",
        "a": {
          "action": "launcher",
          "whenCompositors": ["niri"]
        },
        "b": {
          "action": "launcher",
          "whenCompositors": ["hyprland", "sway"]
        },
        "want": true
      },
      {
        "tag": "a compositor in common",
        "a": {
          "action": "launcher",
          "whenCompositors": ["niri", "sway"]
        },
        "b": {
          "action": "launcher",
          "whenCompositors": ["hyprland", "sway"]
        },
        "want": false
      },
      {
        "tag": "a raw command's own compositor",
        "a": {
          "action": "raw",
          "compositor": "sway"
        },
        "b": {
          "action": "launcher",
          "whenCompositors": ["niri"]
        },
        "want": true
      },
      {
        "tag": "one compositor, one any",
        "a": {
          "action": "launcher",
          "whenCompositors": ["niri"]
        },
        "b": {
          "action": "launcher"
        },
        "want": false
      },
      {
        "tag": "a strip action and tiling",
        "a": {
          "action": "stripNarrower"
        },
        "b": {
          "action": "toggleSplit",
          "whenLayout": "tiling"
        },
        "want": true
      },
      {
        "tag": "grid and dynamic",
        "a": {
          "action": "launcher",
          "whenLayout": "grid"
        },
        "b": {
          "action": "launcher",
          "whenLayout": "dynamic"
        },
        "want": true
      },
      {
        "tag": "strips and grid can hold together",
        "a": {
          "action": "launcher",
          "whenLayout": "strips"
        },
        "b": {
          "action": "launcher",
          "whenLayout": "grid"
        },
        "want": false
      },
      {
        "tag": "docked and laptop",
        "a": {
          "action": "launcher",
          "whenMonitors": "external"
        },
        "b": {
          "action": "launcher",
          "whenMonitors": "laptopOnly"
        },
        "want": true
      }
    ];
  }

  function test_exclusive(data) {
    compare(BindConditions.exclusive(data.a, data.b), data.want);
    compare(BindConditions.exclusive(data.b, data.a), data.want, "either way round");
  }
}
