.pragma library
// The fixtures of LayerArrange's rows (tests/layer/LayerArrange.js):
// builders, each returning a fresh object per call.

// One 1920x1080 output, DP-1
function oneOutput() {
  return {"DP-1": {"width": 1920, "height": 1080}};
}

// A bar across the top of the output: 30 px high, reserving 30 px
function _topBar(id, order, seq) {
  return {
    "id": id, "outputName": "DP-1", "namespace": "axiom-bar", "layer": "top", "order": order, "seq": seq,
    "anchors": {"top": true, "left": true, "right": true, "bottom": false}, "margins": {},
    "width": 0, "height": 30, "zone": 30
  };
}

// arrange's input: one top bar (order 5, mapped first)
function topBar30() {
  return {"outputs": oneOutput(), "surfaces": [_topBar(1, 5, 1)], "ordered": false};
}

// arrange's input: two top bars, the order-4 one mapped first (id 1, seq 1)
// and the order-5 one after it (id 2, seq 2)
function twoTopBars() {
  return {"outputs": oneOutput(), "surfaces": [_topBar(1, 4, 1), _topBar(2, 5, 2)], "ordered": false};
}

// correctionsOf's input: topBar30 as arrange places it, and the
// compositor's list with that bar 2 px to the right
function reportedShifted() {
  return {
    "computed": {
      "DP-1": {
        "width": 1920, "height": 1080,
        "layers": [{"id": 1, "namespace": "axiom-bar", "x": 0, "y": 0, "width": 1920, "height": 30, "rule": "reservingFirstByLayer"}],
        "reserved": {"top": 30, "right": 0, "bottom": 0, "left": 0}
      }
    },
    "reported": {"DP-1": {"w": 1920, "h": 1080, "layers": [{"namespace": "axiom-bar", "x": 2, "y": 0, "w": 1920, "h": 30}]}},
    "mappedIds": [1],
    "liveIds": [1],
    "current": {}
  };
}
