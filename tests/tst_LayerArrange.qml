import QtQuick
import QtTest
import qs.components.methods
import qs.components.methods.layer
import "layer/LayerArrange.js" as Rows
import "layer/Fixtures.js" as Fixtures

// Where layer surfaces land (LayerArrange). The first case is the probe
// measured in nested sway and niri (docs/dev/compositor/layer-arrangement.md)
TestCase {
  id: test
  name: "LayerArrange"

  RepoFiles {
    id: files
  }

  EngineRows {
    id: rows
    testCase: test
    facade: LayerArrange
    fixtures: Fixtures
    rows: Rows.rows
  }

  function test_rows_data() {
    return rows.data();
  }

  function test_rows(data) {
    rows.run(data);
  }

  function strip(id, seq, edge, zone, depth, margins) {
    const vertical = edge === "left" || edge === "right";
    const anchors = {
      "left": edge !== "right",
      "right": edge !== "left",
      "top": edge !== "bottom",
      "bottom": edge !== "top"
    };
    return {
      "id": id,
      "outputName": "O",
      "namespace": "probe",
      "seq": seq,
      "anchors": anchors,
      "margins": margins ?? {},
      "width": vertical ? depth : 0,
      "height": vertical ? 0 : depth,
      "zone": zone
    };
  }

  function rectsById(result, output) {
    return result[output].layers.reduce((acc, l) => {
      acc[l.id] = [l.x, l.y, l.width, l.height];
      return acc;
    }, {});
  }

  // Map order alone; blue was remapped after everything else
  function test_measured_probe() {
    const W = 1648, H = 1408;
    const surfaces = [strip("red", 0, "top", 30, 30), strip("green", 1, "top", 30, 30), strip("yellow", 3, "left", 40, 40), strip("magenta", 4, "right", 20, 20, {
        "right": 10
      }), strip("cyan", 5, "right", 20, 20), strip("white", 6, "bottom", 0, 25), strip("orange", 7, "bottom", 25, 25), strip("blue", 9, "left", 40, 40),
      {
        "id": "box",
        "outputName": "O",
        "namespace": "probe-box",
        "seq": 8,
        "anchors": {
          "top": true,
          "left": true
        },
        "margins": {
          "left": 300,
          "top": 200
        },
        "width": 200,
        "height": 200,
        "zone": -1
      }
    ];
    const r = rectsById(LayerArrange.arrange({
      "outputs": {
        "O": {
          "width": W,
          "height": H
        }
      },
      "surfaces": surfaces,
      "ordered": false
    }), "O");
    compare(r.red, [0, 0, W, 30], "first mapped takes the edge and both corners");
    compare(r.green, [0, 30, W, 30]);
    compare(r.yellow, [0, 60, 40, H - 60], "below the top strips, mapped before the bottom one");
    compare(r.magenta, [W - 30, 60, 20, H - 60], "its margin");
    compare(r.cyan, [W - 50, 60, 20, H - 60], "past the margin too");
    compare(r.orange, [40, H - 25, W - 90, 25], "after yellow and the right strips, before blue");
    compare(r.blue, [40, 60, 40, H - 85], "remapped: inside everything");
    compare(r.white, [80, H - 50, W - 130, 25], "reserving nothing: in what's left at the end");
    compare(r.box, [300, 200, 200, 200], "ignoring zones: from the output's corner");
  }

  // A free menu's window (ExclusionMode.Ignore, anchored to every side):
  // the whole output, however many strips reserve before it, which keep
  // their places
  function test_full_screen_ignore() {
    const menu = {
      "id": "menu",
      "outputName": "O",
      "namespace": "axiom-menu",
      "seq": 0,
      "anchors": {
        "left": true,
        "right": true,
        "top": true,
        "bottom": true
      },
      "margins": {},
      "width": 0,
      "height": 0,
      "zone": -1
    };
    const bar = strip("bar", 1, "top", 30, 30);
    const r = rectsById(LayerArrange.arrange({
      "outputs": {
        "O": {
          "width": 1000,
          "height": 800
        }
      },
      "surfaces": [menu, bar],
      "ordered": false
    }), "O");
    compare(r.menu, [0, 0, 1000, 800], "the whole output");
    compare(r.bar, [0, 0, 1000, 30], "the bar keeps its edge");
  }

  // A negative margin on the anchored edge reaches back over what's
  // reserved before it, and reserves that much less
  function test_negative_margin() {
    const border = strip("border", 0, "top", 8, 8);
    const pill = strip("pill", 1, "top", 30, 32, {
      "top": -2
    });
    const dock = strip("dock", 2, "top", 10, 10);
    const r = rectsById(LayerArrange.arrange({
      "outputs": {
        "O": {
          "width": 500,
          "height": 500
        }
      },
      "surfaces": [border, pill, dock],
      "ordered": false
    }), "O");
    compare(r.pill, [0, 6, 500, 32]);
    compare(r.dock, [0, 36, 500, 10]);
  }

  function ruleOf(result, output, id) {
    return result[output].layers.find(l => l.id === id).rule;
  }

  // Size 0 between two anchored edges stretches (a rule of its own)
  function test_stretch_when_size_zero() {
    const wide = {
      "id": "w",
      "outputName": "O",
      "seq": 0,
      "anchors": {
        "left": true,
        "right": true
      },
      "width": 0,
      "height": 20,
      "zone": 0
    };
    const result = LayerArrange.arrange({
      "outputs": {
        "O": {
          "width": 300,
          "height": 200
        }
      },
      "surfaces": [wide],
      "ordered": false
    });
    compare(rectsById(result, "O").w, [0, 90, 300, 20]);
    compare(ruleOf(result, "O", "w"), "stretchWhenSizeZero");
  }

  function test_centred_and_corner_anchors() {
    const out = {
      "O": {
        "width": 1000,
        "height": 600
      }
    };
    const bar = strip("bar", 0, "left", 40, 40);
    const centred = {
      "id": "c",
      "outputName": "O",
      "seq": 1,
      "anchors": {},
      "width": 100,
      "height": 50,
      "zone": 0
    };
    const corner = {
      "id": "k",
      "outputName": "O",
      "seq": 2,
      "anchors": {
        "bottom": true,
        "right": true
      },
      "margins": {
        "right": 5,
        "bottom": 5
      },
      "width": 20,
      "height": 20,
      "zone": 50
    };
    const arranged = LayerArrange.arrange({
      "outputs": out,
      "surfaces": [bar, centred, corner],
      "ordered": false
    });
    const r = rectsById(arranged, "O");
    compare(r.c, [470, 275, 100, 50], "centred in the room left");
    compare(ruleOf(arranged, "O", "c"), "centredWhenUnanchored");
    compare(r.k, [975, 575, 20, 20]);
    compare(LayerArrange.zoneEdge(corner.anchors), "", "a corner reserves nothing");
  }

  // A positive zone with no edge to reserve on counts as 0: placed in
  // what's left at the end, after a strip mapped later
  function test_zone_without_edge() {
    const corner = {
      "id": "k",
      "outputName": "O",
      "seq": 0,
      "anchors": {
        "bottom": true,
        "right": true
      },
      "width": 20,
      "height": 20,
      "zone": 50
    };
    const bottom = strip("bottom", 1, "bottom", 30, 30);
    const arranged = LayerArrange.arrange({
      "outputs": {
        "O": {
          "width": 400,
          "height": 300
        }
      },
      "surfaces": [corner, bottom],
      "ordered": false
    });
    const r = rectsById(arranged, "O");
    compare(ruleOf(arranged, "O", "k"), "zoneOnlyOnAnEdge");
    compare(r.k, [380, 250, 20, 20], "above the strip");
    compare(r.bottom, [0, 270, 400, 30], "the strip reserves the whole edge");
  }

  function test_layers_and_outputs() {
    const top = strip("top", 1, "top", 20, 20);
    const over = Object.assign(strip("over", 5, "top", 10, 10), {
      "layer": "overlay"
    });
    const other = Object.assign(strip("other", 0, "top", 30, 30), {
      "outputName": "P"
    });
    const result = LayerArrange.arrange({
      "outputs": {
        "O": {
          "width": 100,
          "height": 100
        },
        "P": {
          "width": 50,
          "height": 50
        }
      },
      "surfaces": [top, over, other],
      "ordered": false
    });
    const r = rectsById(result, "O");
    compare(r.over, [0, 0, 100, 10], "a higher layer reserves first");
    compare(r.top, [0, 10, 100, 20]);
    compare(rectsById(result, "P").other, [0, 0, 50, 30]);
    compare(result.P.width, 50);
    compare(result.O.reserved, {
      "top": 30,
      "right": 0,
      "bottom": 0,
      "left": 0
    }, "what the reserving surfaces take from each edge");
    compare(result.P.reserved.top, 30);
  }

  // Each computed rect pairs with the nearest reported one of its
  // namespace, each taken once; others, and those not kept, go unmatched
  function test_match() {
    const computed = {
      "O": {
        "width": 1000,
        "height": 800,
        "layers": [
          {
            "id": 1,
            "namespace": "axiom-border",
            "x": 0,
            "y": 0,
            "width": 1000,
            "height": 8
          },
          {
            "id": 2,
            "namespace": "axiom-border",
            "x": 0,
            "y": 8,
            "width": 8,
            "height": 792
          },
          {
            "id": 3,
            "namespace": "axiom-dock",
            "x": 0,
            "y": 700,
            "width": 100,
            "height": 50
          },
          {
            "id": 4,
            "namespace": "axiom-osd",
            "x": 0,
            "y": 0,
            "width": 10,
            "height": 10
          }
        ]
      }
    };
    // Another app's 40 px panel on the left moves the border's strips in
    const reported = {
      "O": {
        "w": 1000,
        "h": 800,
        "layers": [
          {
            "namespace": "axiom-border",
            "x": 40,
            "y": 8,
            "w": 8,
            "h": 792
          },
          {
            "namespace": "axiom-border",
            "x": 40,
            "y": 0,
            "w": 960,
            "h": 8
          },
          {
            "namespace": "axiom-osd",
            "x": 5,
            "y": 5,
            "w": 10,
            "h": 10
          }
        ]
      }
    };
    const m = LayerArrange.match({
      "computed": computed,
      "reported": reported,
      "mappedIds": [1, 2, 3]
    });
    compare(m[1], {
      "x": 40,
      "y": 0,
      "width": 960,
      "height": 8
    }, "the top strip, not the left one");
    compare(m[2], {
      "x": 40,
      "y": 8,
      "width": 8,
      "height": 792
    });
    compare(m[3], undefined, "nothing reported in its namespace");
    compare(m[4], undefined, "not kept");
    compare(LayerArrange.match({
      "computed": computed,
      "reported": null,
      "mappedIds": [1, 2, 3, 4]
    }), {});
  }

  // Captured from a live Hyprland: every surface lands where Hyprland put it
  function test_hyprland_fixture() {
    const fixture = files.json("tests/fixtures/layers/hyprland-two-bars.json");
    const outputs = {};
    for (const name in fixture.reported)
      outputs[name] = {
        "width": fixture.reported[name].w,
        "height": fixture.reported[name].h
      };
    const result = LayerArrange.arrange({
      "outputs": outputs,
      "surfaces": fixture.surfaces,
      "ordered": false
    });
    for (const name in result)
      for (const l of result[name].layers) {
        const theirs = fixture.reported[name].layers.filter(r => r.namespace === l.namespace);
        verify(theirs.some(r => r.x === l.x && r.y === l.y && r.w === l.width && r.h === l.height), `${l.namespace} at ${l.x},${l.y} ${l.width}x${l.height}`);
      }
    compare(result["DP-1"].layers.length, fixture.surfaces.length);
  }
}
