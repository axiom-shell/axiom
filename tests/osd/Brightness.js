.pragma library
// Brightness's timelines: one bar, this screen's brightness (or every
// monitor's mean with `allMonitors`).
//
// State by key:
//   brightness  { available, level (0-1) }: `available` false while the
//               screen has no controller (the bar is left out)

var opts = { "allMonitors": false, "icon": "", "showOsd": true };

var rows = [
  {
    "name": "the first reading shows nothing",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "brightness": { "available": true, "level": 0.5 } } }
    ]
  },
  {
    "name": "a change: the bars",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "brightness": { "available": true, "level": 0.5 } } },
      { "at": 3000, "state": { "brightness": { "available": true, "level": 0.6 } },
        "expect": { "key": "brightness", "show": "level", "kind": "level", "card": null, "host": "open" } }
    ]
  },
  {
    "name": "from the Brightness module: a level, the user's",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "brightness": { "available": true, "level": 0.5 } } },
      { "at": 3000, "byUser": true, "state": { "brightness": { "available": true, "level": 0.2 } },
        "expect": { "key": "brightness", "show": "level", "byUser": true } }
    ]
  },
  {
    "name": "no controller: nothing, nor as one appears",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "brightness": { "available": false, "level": 0 } } },
      { "at": 3000, "state": { "brightness": { "available": true, "level": 0.7 } } },
      { "at": 6000, "state": { "brightness": { "available": false, "level": 0 } } }
    ]
  },
  {
    "name": "the same level read again: nothing",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "brightness": { "available": true, "level": 0.5 } } },
      { "at": 3000, "state": { "brightness": { "available": true, "level": 0.5 } } }
    ]
  },
  {
    "name": "two levels in a row: each shows, the bars kept open",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "brightness": { "available": true, "level": 0.5 } } },
      { "at": 3000, "state": { "brightness": { "available": true, "level": 0.55 } },
        "expect": { "show": "level", "host": "open" } },
      { "at": 3100, "state": { "brightness": { "available": true, "level": 0.6 } },
        "expect": { "show": "level", "host": "open" } }
    ]
  }
];
