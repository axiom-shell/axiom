.pragma library
// Dnd's timelines: a plain toggle, lit and unusual while on; either way its
// icon (no card).
//
// State by key (DndWatch):
//   dnd  { value (NotificationManager.dnd) }

var rows = [
  {
    "name": "the first reading shows nothing",
    "steps": [
      { "at": 0, "state": { "dnd": { "value": true } } }
    ]
  },
  {
    "name": "turned on: its icon, lit and unusual",
    "steps": [
      { "at": 0, "state": { "dnd": { "value": false } } },
      { "at": 3000, "state": { "dnd": { "value": true } },
        "expect": { "key": "dnd", "show": "tile", "kind": "add",
          "tile": { "icon": "do_not_disturb_on", "on": true, "notable": true, "hidden": false, "slash": false, "label": "" }, "card": null, "host": "ring" } }
    ]
  },
  {
    "name": "turned off: the same icon, unlit, not struck through",
    "steps": [
      { "at": 0, "state": { "dnd": { "value": true } } },
      { "at": 3000, "state": { "dnd": { "value": false } },
        "expect": { "key": "dnd", "show": "tile", "kind": "remove", "tile": { "icon": "do_not_disturb_on", "on": false, "slash": false, "notable": false } } }
    ]
  },
  {
    "name": "turned on from the panel: still its icon, the user's (the host keeps it shut)",
    "steps": [
      { "at": 0, "state": { "dnd": { "value": false } } },
      { "at": 3000, "byUser": true, "state": { "dnd": { "value": true } },
        "expect": { "key": "dnd", "show": "tile", "byUser": true } }
    ]
  },
  {
    "name": "on, off and on again: each takes the ring",
    "steps": [
      { "at": 0, "state": { "dnd": { "value": false } } },
      { "at": 3000, "state": { "dnd": { "value": true } },
        "expect": { "key": "dnd", "show": "tile", "host": "ring" } },
      { "at": 3400, "state": { "dnd": { "value": false } },
        "expect": { "key": "dnd", "show": "tile", "host": "ring" } },
      { "at": 3800, "state": { "dnd": { "value": true } },
        "expect": { "key": "dnd", "show": "tile", "host": "ring" } }
    ]
  },
  {
    "name": "quiet: judged the same (the host doesn't open the OSD for it)",
    "options": { "quiet": true },
    "steps": [
      { "at": 0, "state": { "dnd": { "value": false } } },
      { "at": 3000, "state": { "dnd": { "value": true } },
        "expect": { "key": "dnd", "show": "tile" } }
    ]
  }
];
