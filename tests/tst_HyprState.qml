import QtQuick
import QtTest
import qs.components.methods

// HyprState: Hyprland's replies as the shapes the shell reads.
TestCase {
  name: "HyprState"

  function test_keyboardPrefersTheMainOne() {
    compare(HyprState.keyboard({
      "keyboards": [
        {
          "main": false,
          "layout": "fr"
        },
        {
          "main": true,
          "layout": "us, de",
          "active_layout_index": 1,
          "active_keymap": "German"
        }
      ]
    }), {
      "layouts": ["us", "de"],
      "index": 1,
      "keymap": "German"
    });
  }

  function test_keyboardFallsBackToTheFirst() {
    compare(HyprState.keyboard({
      "keyboards": [
        {
          "layout": "us"
        }
      ]
    }), {
      "layouts": ["us"],
      "index": 0,
      "keymap": ""
    });
    compare(HyprState.keyboard({
      "keyboards": []
    }), null);
    compare(HyprState.keyboard(null), null);
  }

  function test_gapSides_data() {
    return [
      {
        "tag": "no reply",
        "option": null,
        "sides": null
      },
      {
        "tag": "no css",
        "option": {
          "int": 5
        },
        "sides": null
      },
      {
        "tag": "empty css",
        "option": {
          "css": " "
        },
        "sides": null
      },
      {
        "tag": "not numbers",
        "option": {
          "css": "5 x"
        },
        "sides": null
      },
      {
        "tag": "one value",
        "option": {
          "css": "6"
        },
        "sides": {
          "top": 6,
          "right": 6,
          "bottom": 6,
          "left": 6
        }
      },
      {
        "tag": "two values",
        "option": {
          "css": "4 8"
        },
        "sides": {
          "top": 4,
          "right": 8,
          "bottom": 4,
          "left": 8
        }
      },
      {
        "tag": "four values",
        "option": {
          "css": " 1 2 3 4 "
        },
        "sides": {
          "top": 1,
          "right": 2,
          "bottom": 3,
          "left": 4
        }
      }
    ];
  }

  function test_gapSides(data) {
    compare(HyprState.gapSides(data.option), data.sides);
  }

  function test_window() {
    const client = {
      "address": "0x5a",
      "mapped": true,
      "hidden": false,
      "class": "kitty",
      "initialClass": "kitty",
      "title": "~",
      "workspace": {
        "id": 3,
        "name": "3"
      },
      "monitor": 1,
      "floating": false,
      "fullscreen": 2,
      "focusHistoryID": 0,
      "at": [1930, 10],
      "size": [800, 600]
    };
    compare(HyprState.window(client, {
      "1": "DP-1"
    }), {
      "id": "0x5a",
      "appId": "kitty",
      "initialAppId": "kitty",
      "title": "~",
      "workspaceId": 3,
      "workspaceName": "3",
      "output": "DP-1",
      "floating": false,
      "fullscreen": true,
      "maximized": false,
      "hidden": false,
      "focusRank": 0,
      "x": 1930,
      "y": 10,
      "w": 800,
      "h": 600
    });
    compare(HyprState.window(Object.assign({}, client, {
      "fullscreen": 1
    }), {}).maximized, true, "mode 1 is maximized, not fullscreen");
    compare(HyprState.window(Object.assign({}, client, {
      "mapped": false
    }), {}), null, "an unmapped client isn't a window");
  }

  function test_output() {
    compare(HyprState.output({
      "name": "DP-1",
      "description": "Dell U2720Q",
      "x": 1920,
      "y": 0,
      "width": 3840,
      "height": 2160,
      "scale": 2,
      "activeWorkspace": {
        "id": 4
      },
      "lastIpcObject": {
        "transform": 0,
        "reserved": [0, 30, 0, 0],
        "specialWorkspace": {
          "id": -98
        }
      }
    }, true), {
      "name": "DP-1",
      "description": "Dell U2720Q",
      "x": 1920,
      "y": 0,
      "width": 1920,
      "height": 1080,
      "scale": 2,
      "focused": true,
      "activeWorkspaceId": 4,
      "specialWorkspaceId": -98,
      "reserved": {
        "left": 0,
        "top": 30,
        "right": 0,
        "bottom": 0
      }
    });
    compare(HyprState.output({
      "name": "HDMI-A-1"
    }, false).activeWorkspaceId, -1, "a monitor not read yet");
  }

  function test_workspace() {
    compare(HyprState.workspace({
      "id": 2,
      "name": "2",
      "monitor": {
        "name": "DP-1"
      },
      "toplevels": {
        "values": [
          {},
          {}
        ]
      },
      "active": true,
      "focused": false
    }), {
      "id": 2,
      "name": "2",
      "output": "DP-1",
      "windowCount": 2,
      "active": true,
      "focused": false
    });
  }

  function test_layerRects() {
    const monitors = [
      {
        "name": "DP-1",
        "x": 1920,
        "y": 0,
        "width": 2160,
        "height": 3840,
        "scale": 2,
        "transform": 1
      }
    ];
    const layers = {
      "DP-1": {
        "levels": {
          "2": [
            {
              "namespace": "bar",
              "x": 1920,
              "y": 0,
              "w": 1080,
              "h": 30
            }
          ],
          "3": [
            {
              "namespace": "overlay",
              "x": 2000,
              "y": 100,
              "w": 400,
              "h": 300
            }
          ]
        }
      }
    };
    compare(HyprState.layerRects(monitors, layers), {
      "DP-1": {
        "w": 1920,
        "h": 1080,
        "layers": [
          {
            "namespace": "bar",
            "x": 0,
            "y": 0,
            "w": 1080,
            "h": 30
          },
          {
            "namespace": "overlay",
            "x": 80,
            "y": 100,
            "w": 400,
            "h": 300
          }
        ]
      }
    }, "a turned monitor swaps its sides; positions are relative, logical px");
  }
}
