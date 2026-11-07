.pragma library
// Airplane's timelines: a toggle, lit and unusual while on; Wi-Fi and
// Bluetooth switching just after are its knock-on (Cross.js).
//
// State by key (AirplaneWatch):
//   airplane  { value (NetworkingManager.airplane) }

var rows = [
  {
    "name": "the first reading shows nothing",
    "steps": [
      { "at": 0, "state": { "airplane": { "value": true } } }
    ]
  },
  {
    "name": "turned on: its icon, lit and unusual",
    "steps": [
      { "at": 0, "state": { "airplane": { "value": false } } },
      { "at": 3000, "state": { "airplane": { "value": true } },
        "expect": { "key": "airplane", "show": "tile", "kind": "add",
          "tile": { "icon": "airplanemode_active", "on": true, "notable": true, "hidden": false, "slash": false }, "card": null, "host": "ring", "action": { "id": "airplane", "call": "toggle" } } }
    ]
  },
  {
    "name": "turned off: the same icon, unlit",
    "steps": [
      { "at": 0, "state": { "airplane": { "value": true } } },
      { "at": 3000, "state": { "airplane": { "value": false } },
        "expect": { "key": "airplane", "show": "tile", "kind": "remove", "tile": { "icon": "airplanemode_active", "on": false, "notable": false } } }
    ]
  },
  {
    "name": "from the panel: still its icon, the user's",
    "steps": [
      { "at": 0, "state": { "airplane": { "value": false } } },
      { "at": 3000, "byUser": true, "state": { "airplane": { "value": true } },
        "expect": { "key": "airplane", "show": "tile", "byUser": true } }
    ]
  }
];
