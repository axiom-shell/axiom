.pragma library
// Recording's timelines: axiom's own screen recording, lit and unusual
// while on; either way its icon (no card). A click on its tile only stops
// it (actionOf: { id: "screenRecord", call: "close" } while recording, null
// otherwise).
//
// State by key (RecordingWatch):
//   recording  { available (ScreenshotManager.hasRecorder), value
//              (ScreenshotManager.recording) }

var rows = [
  {
    "name": "no recorder: its tile hidden",
    "steps": [
      { "at": 0, "state": { "recording": { "available": false, "value": false } },
        "tiles": { "recording": { "hidden": true } } }
    ]
  },
  {
    "name": "the first reading shows nothing",
    "steps": [
      { "at": 0, "state": { "recording": { "available": true, "value": true } } }
    ]
  },
  {
    "name": "turned on: its icon, lit and unusual",
    "steps": [
      { "at": 0, "state": { "recording": { "available": true, "value": false } } },
      { "at": 3000, "state": { "recording": { "available": true, "value": true } },
        "expect": { "key": "recording", "show": "tile", "kind": "add",
          "tile": { "icon": "screen_record", "on": true, "notable": true, "hidden": false, "slash": false, "label": "" }, "card": null, "host": "ring",
          "action": { "id": "screenRecord", "call": "close" } } }
    ]
  },
  {
    "name": "turned off: the same icon, unlit, not struck through",
    "steps": [
      { "at": 0, "state": { "recording": { "available": true, "value": true } } },
      { "at": 3000, "state": { "recording": { "available": true, "value": false } },
        "expect": { "key": "recording", "show": "tile", "kind": "remove", "tile": { "icon": "screen_record", "on": false, "slash": false, "notable": false }, "action": null } }
    ]
  },
  {
    "name": "turned on from the panel: still its icon, the user's (the host keeps it shut)",
    "steps": [
      { "at": 0, "state": { "recording": { "available": true, "value": false } } },
      { "at": 3000, "byUser": true, "state": { "recording": { "available": true, "value": true } },
        "expect": { "key": "recording", "show": "tile", "byUser": true } }
    ]
  },
  {
    "name": "on, off and on again: each takes the ring",
    "steps": [
      { "at": 0, "state": { "recording": { "available": true, "value": false } } },
      { "at": 3000, "state": { "recording": { "available": true, "value": true } },
        "expect": { "key": "recording", "show": "tile", "host": "ring" } },
      { "at": 3400, "state": { "recording": { "available": true, "value": false } },
        "expect": { "key": "recording", "show": "tile", "host": "ring" } },
      { "at": 3800, "state": { "recording": { "available": true, "value": true } },
        "expect": { "key": "recording", "show": "tile", "host": "ring" } }
    ]
  },
  {
    "name": "quiet: judged the same (the host doesn't open the OSD for it)",
    "options": { "quiet": true },
    "steps": [
      { "at": 0, "state": { "recording": { "available": true, "value": false } } },
      { "at": 3000, "state": { "recording": { "available": true, "value": true } },
        "expect": { "key": "recording", "show": "tile" } }
    ]
  },
  {
    "name": "no recorder: nothing",
    "steps": [
      { "at": 0, "state": { "recording": { "available": false, "value": false } } },
      { "at": 3000, "state": { "recording": { "available": true, "value": true } } }
    ]
  }
];
