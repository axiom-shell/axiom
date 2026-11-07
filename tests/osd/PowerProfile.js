.pragma library
// PowerProfile's timelines: the power profile in use, its own icon,
// unusual off balanced. The daemon appearing or going away isn't a change.
//
// State by key (PowerProfileWatch):
//   powerProfile  { value (BatteryManager.profile: "powerSaver" |
//                 "balanced" | "performance", "" with no profiles daemon) }
//
// decided: policies onAdd "none" and onRemove "none" (the daemon answering
//   or going: today's `_last !== "" && profile !== ""`), onChange "icon".
//
// Not expressible as rows: the tile hidden with no daemon ("").

var rows = [
  {
    "name": "the first reading shows nothing",
    "steps": [
      { "at": 0, "state": { "powerProfile": { "value": "powerSaver" } } }
    ]
  },
  {
    "name": "power saver: its leaf, lit and unusual",
    "steps": [
      { "at": 0, "state": { "powerProfile": { "value": "balanced" } } },
      { "at": 3000, "state": { "powerProfile": { "value": "powerSaver" } },
        "expect": { "key": "powerProfile", "show": "tile", "kind": "change",
          "tile": { "icon": "energy_savings_leaf", "on": true, "notable": true, "hidden": false, "slash": false }, "card": null, "host": "ring" } }
    ]
  },
  {
    "name": "performance: unusual too",
    "steps": [
      { "at": 0, "state": { "powerProfile": { "value": "balanced" } } },
      { "at": 3000, "state": { "powerProfile": { "value": "performance" } },
        "expect": { "key": "powerProfile", "show": "tile", "tile": { "icon": "speed", "on": true, "notable": true } } }
    ]
  },
  {
    "name": "back to balanced: unlit, ordinary",
    "steps": [
      { "at": 0, "state": { "powerProfile": { "value": "powerSaver" } } },
      { "at": 3000, "state": { "powerProfile": { "value": "balanced" } },
        "expect": { "key": "powerProfile", "show": "tile", "tile": { "icon": "balance", "on": false, "notable": false } } }
    ]
  },
  {
    "name": "from the panel: still its icon, the user's",
    "steps": [
      { "at": 0, "state": { "powerProfile": { "value": "balanced" } } },
      { "at": 3000, "byUser": true, "state": { "powerProfile": { "value": "powerSaver" } },
        "expect": { "key": "powerProfile", "show": "tile", "byUser": true } }
    ]
  },
  {
    "name": "the daemon answering, then going away: nothing",
    "steps": [
      { "at": 0, "state": { "powerProfile": { "value": "" } } },
      { "at": 3000, "state": { "powerProfile": { "value": "balanced" } } },
      { "at": 6000, "state": { "powerProfile": { "value": "" } } }
    ]
  }
];
