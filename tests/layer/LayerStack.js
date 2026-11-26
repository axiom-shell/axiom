.pragma library
// LayerStack's contract rows (docs/dev/core/engines.md › The row format):
// the layer a window is on now, over a fullscreen window and under a modal.

var rows = [
  {
    "id": "LY-14",
    "why": "a window whose row has no overFullscreen stays on its row's layer over a fullscreen window",
    "call": "layerOf",
    "args": [
      "dock",
      {
        "fullscreen": true,
        "wanted": true,
        "movesKeepPlace": true,
        "underModal": ""
      }
    ],
    "expect": "top"
  },
  {
    "id": "LY-15",
    "why": "with no fullscreen window on its screen a window is on its row's layer",
    "call": "layerOf",
    "args": [
      "overlay",
      {
        "fullscreen": false,
        "wanted": true,
        "movesKeepPlace": true,
        "underModal": ""
      }
    ],
    "expect": "top"
  },
  {
    "id": "LY-16",
    "why": "an always window rises to Overlay over a fullscreen window where a move keeps its place",
    "call": "layerOf",
    "args": [
      "backdrop",
      {
        "fullscreen": true,
        "wanted": false,
        "movesKeepPlace": true,
        "underModal": ""
      }
    ],
    "expect": "overlay"
  },
  {
    "id": "LY-17",
    "why": "a whileShown window rises to Overlay over a fullscreen window where a move keeps its place",
    "call": "layerOf",
    "args": [
      "overlay",
      {
        "fullscreen": true,
        "wanted": false,
        "movesKeepPlace": true,
        "underModal": ""
      }
    ],
    "expect": "overlay"
  },
  {
    "id": "LY-18",
    "why": "where a move lands on top a wanted whileShown window rises to Overlay over a fullscreen window",
    "call": "layerOf",
    "args": [
      "overlay",
      {
        "fullscreen": true,
        "wanted": true,
        "movesKeepPlace": false,
        "underModal": ""
      }
    ],
    "expect": "overlay"
  },
  {
    "id": "LY-19",
    "why": "where a move lands on top a whileShown window not wanted comes down at once to its row's layer",
    "call": "layerOf",
    "args": [
      "overlay",
      {
        "fullscreen": true,
        "wanted": false,
        "movesKeepPlace": false,
        "underModal": ""
      }
    ],
    "expect": "top"
  },
  {
    "id": "LY-20",
    "why": "where a move lands on top an always window never moves",
    "call": "layerOf",
    "args": [
      "blur-backing",
      {
        "fullscreen": true,
        "wanted": true,
        "movesKeepPlace": false,
        "underModal": ""
      }
    ],
    "expect": "top"
  },
  {
    "id": "LY-21",
    "why": "a page that would rise keeps its layer while a modal shows on its screen",
    "call": "layerOf",
    "args": [
      "overlay",
      {
        "fullscreen": true,
        "wanted": true,
        "movesKeepPlace": false,
        "underModal": "top"
      }
    ],
    "expect": "top"
  },
  {
    "id": "LY-22",
    "why": "once the modal is gone the page rises",
    "call": "layerOf",
    "args": [
      "overlay",
      {
        "fullscreen": true,
        "wanted": true,
        "movesKeepPlace": false,
        "underModal": ""
      }
    ],
    "expect": "overlay"
  },
  {
    "id": "LY-23",
    "why": "a move down never waits for a modal: the page goes under it",
    "call": "layerOf",
    "args": [
      "overlay",
      {
        "fullscreen": false,
        "wanted": false,
        "movesKeepPlace": false,
        "underModal": "overlay"
      }
    ],
    "expect": "top"
  },
  {
    "id": "LY-24",
    "why": "a window already on the modal's layer stays there",
    "call": "layerOf",
    "args": [
      "osd",
      {
        "fullscreen": false,
        "wanted": true,
        "movesKeepPlace": true,
        "underModal": "overlay"
      }
    ],
    "expect": "overlay"
  },
  {
    "id": "LY-27",
    "why": "a window that is never over a fullscreen window is not shown while one is up on its screen",
    "call": "layerOf",
    "args": [
      "hot-corner",
      {
        "fullscreen": true,
        "wanted": true,
        "movesKeepPlace": true,
        "underModal": ""
      }
    ],
    "expect": ""
  },
  {
    "id": "LY-28",
    "why": "with no fullscreen window on its screen the same window is on its row's layer",
    "call": "layerOf",
    "args": [
      "hot-corner",
      {
        "fullscreen": false,
        "wanted": true,
        "movesKeepPlace": true,
        "underModal": ""
      }
    ],
    "expect": "overlay"
  },
  {
    "id": "LY-29",
    "why": "where a move keeps its place a window that would rise does not wait for a modal",
    "call": "layerOf",
    "args": [
      "blur-backing",
      {
        "fullscreen": true,
        "wanted": true,
        "movesKeepPlace": true,
        "underModal": "top"
      }
    ],
    "expect": "overlay"
  },
  {
    "id": "LY-30",
    "why": "a hover strip is not shown while a fullscreen window is up on its screen",
    "call": "layerOf",
    "args": [
      "edge-trigger",
      {
        "fullscreen": true,
        "wanted": true,
        "movesKeepPlace": true,
        "underModal": ""
      }
    ],
    "expect": ""
  },
  {
    "id": "LY-31",
    "why": "a hover strip stays on Top with no fullscreen window up",
    "call": "layerOf",
    "args": [
      "edge-trigger",
      {
        "fullscreen": false,
        "wanted": true,
        "movesKeepPlace": true,
        "underModal": ""
      }
    ],
    "expect": "top"
  }
];
