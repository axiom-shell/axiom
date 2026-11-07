.pragma library
// Caffeine's timelines: a plain toggle, its icon either way
var rows = [
  {
    "name": "the first reading shows nothing",
    "steps": [
      { "at": 0, "state": { "caffeine": { "value": true } } }
    ]
  },
  {
    "name": "turned on: its icon, lit and unusual",
    "steps": [
      { "at": 0, "state": { "caffeine": { "value": false } } },
      { "at": 3000, "state": { "caffeine": { "value": true } },
        "expect": { "key": "caffeine", "show": "tile", "kind": "add", "tile": { "icon": "coffee", "on": true, "notable": true }, "host": "ring" } }
    ]
  },
  {
    "name": "turned off: its icon, unlit",
    "steps": [
      { "at": 0, "state": { "caffeine": { "value": true } } },
      { "at": 3000, "state": { "caffeine": { "value": false } },
        "expect": { "key": "caffeine", "show": "tile", "kind": "remove", "tile": { "on": false, "notable": false } } }
    ]
  },
  {
    "name": "turned on from the panel: still its icon (the host keeps it shut)",
    "steps": [
      { "at": 0, "state": { "caffeine": { "value": false } } },
      { "at": 3000, "byUser": true, "state": { "caffeine": { "value": true } },
        "expect": { "show": "tile", "byUser": true } }
    ]
  },
  {
    "name": "has no card",
    "steps": [
      { "at": 0, "state": { "caffeine": { "value": false } } },
      { "at": 3000, "state": { "caffeine": { "value": true } },
        "expect": { "show": "tile", "card": null } }
    ]
  }
];
