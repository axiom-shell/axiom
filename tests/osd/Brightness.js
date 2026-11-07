.pragma library
// Brightness's timelines: one bar, this screen's brightness (or every
// monitor's mean with `allMonitors`).
//
// State by key:
//   brightness  { available, level (0-1), setAt (when axiom last set it:
//               Date.now() ms, 0 for never) }: `available` false while the
//               screen has no controller (the bar is left out); a level
//               counts only within 500 ms of `setAt` (`countsWithin`)

var opts = { "allMonitors": false, "icon": "" };

var rows = [
  {
    "name": "the first reading shows nothing",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "brightness": { "available": true, "level": 0.5, "setAt": 0 } } }
    ]
  },
  {
    "name": "a change: the bars",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "brightness": { "available": true, "level": 0.5, "setAt": 0 } } },
      { "at": 3000, "state": { "brightness": { "available": true, "level": 0.6, "setAt": 3000 } },
        "expect": { "key": "brightness", "show": "level", "kind": "level", "card": null, "host": "open" } }
    ]
  },
  {
    "name": "from the Brightness module: a level, the user's",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "brightness": { "available": true, "level": 0.5, "setAt": 0 } } },
      { "at": 3000, "byUser": true, "state": { "brightness": { "available": true, "level": 0.2, "setAt": 3000 } },
        "expect": { "key": "brightness", "show": "level", "byUser": true } }
    ]
  },
  {
    "name": "no controller: nothing, nor as one appears",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "brightness": { "available": false, "level": 0, "setAt": 0 } } },
      { "at": 3000, "state": { "brightness": { "available": true, "level": 0.7, "setAt": 3000 } } },
      { "at": 6000, "state": { "brightness": { "available": false, "level": 0, "setAt": 0 } } }
    ]
  },
  {
    "name": "the same level read again: nothing",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "brightness": { "available": true, "level": 0.5, "setAt": 0 } } },
      { "at": 3000, "state": { "brightness": { "available": true, "level": 0.5, "setAt": 0 } } }
    ]
  },
  {
    "name": "two levels in a row: each shows, the bars kept open",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "brightness": { "available": true, "level": 0.5, "setAt": 0 } } },
      { "at": 3000, "state": { "brightness": { "available": true, "level": 0.55, "setAt": 3000 } },
        "expect": { "show": "level", "host": "open" } },
      { "at": 3100, "state": { "brightness": { "available": true, "level": 0.6, "setAt": 3100 } },
        "expect": { "show": "level", "host": "open" } }
    ]
  },
  {
    "name": "a key press at 100%: the level unchanged, the bar opens",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "brightness": { "available": true, "level": 1, "setAt": 0 } } },
      { "at": 3000, "state": { "brightness": { "available": true, "level": 1, "setAt": 3000 } },
        "expect": { "key": "brightness", "show": "level", "kind": "level", "opens": true, "host": "open" } }
    ]
  },
  {
    "name": "a level a refresh found, or idle dimming: nothing",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "brightness": { "available": true, "level": 0.5, "setAt": 0 } } },
      { "at": 3000, "state": { "brightness": { "available": true, "level": 0.8, "setAt": 0 } } },
      { "at": 6000, "state": { "brightness": { "available": true, "level": 0.6, "setAt": 6000 } },
        "expect": { "key": "brightness", "show": "level" } },
      { "at": 6600, "state": { "brightness": { "available": true, "level": 0.3, "setAt": 6000 } } }
    ]
  }
];
