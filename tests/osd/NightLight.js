.pragma library
// NightLight's timelines: a plain toggle, lit and unusual while on; either way its
// icon (no card).
//
// State by key (NightLightWatch):
//   nightLight  { value (NightLightManager.active) }

var rows = [
  {
    "name": "the first reading shows nothing",
    "steps": [
      { "at": 0, "state": { "nightLight": { "value": true } } }
    ]
  },
  {
    "name": "turned on: its icon, lit and unusual",
    "steps": [
      { "at": 0, "state": { "nightLight": { "value": false } } },
      { "at": 3000, "state": { "nightLight": { "value": true } },
        "expect": { "key": "nightLight", "show": "tile", "kind": "add",
          "tile": { "icon": "nightlight", "on": true, "notable": true, "hidden": false, "slash": false, "label": "" }, "card": null, "host": "ring" } }
    ]
  },
  {
    "name": "turned off: the same icon, unlit, not struck through",
    "steps": [
      { "at": 0, "state": { "nightLight": { "value": true } } },
      { "at": 3000, "state": { "nightLight": { "value": false } },
        "expect": { "key": "nightLight", "show": "tile", "kind": "remove", "tile": { "icon": "nightlight", "on": false, "slash": false, "notable": false } } }
    ]
  },
  {
    "name": "turned on from the panel: still its icon, the user's (the host keeps it shut)",
    "steps": [
      { "at": 0, "state": { "nightLight": { "value": false } } },
      { "at": 3000, "byUser": true, "state": { "nightLight": { "value": true } },
        "expect": { "key": "nightLight", "show": "tile", "byUser": true } }
    ]
  },
  {
    "name": "on, off and on again: each takes the ring",
    "steps": [
      { "at": 0, "state": { "nightLight": { "value": false } } },
      { "at": 3000, "state": { "nightLight": { "value": true } },
        "expect": { "key": "nightLight", "show": "tile", "host": "ring" } },
      { "at": 3400, "state": { "nightLight": { "value": false } },
        "expect": { "key": "nightLight", "show": "tile", "host": "ring" } },
      { "at": 3800, "state": { "nightLight": { "value": true } },
        "expect": { "key": "nightLight", "show": "tile", "host": "ring" } }
    ]
  },
  {
    "name": "quiet: judged the same (the host doesn't open the OSD for it)",
    "options": { "quiet": true },
    "steps": [
      { "at": 0, "state": { "nightLight": { "value": false } } },
      { "at": 3000, "state": { "nightLight": { "value": true } },
        "expect": { "key": "nightLight", "show": "tile" } }
    ]
  }
];
