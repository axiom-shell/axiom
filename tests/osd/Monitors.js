.pragma library
// Monitors' timelines: a monitor connected or removed, only ever its card
// (no tile): its description (else its connector), Connected or
// Disconnected, and the connector and resolution. Never what's there at
// the start.
//
// State by key (MonitorsWatch):
//   monitor  { event (MonitorManager.lastEvent: { kind: "added" |
//            "removed", name (the connector), description, width, height,
//            serial }, or null), seq }

function mon(kind, name, description, width, height, seq) {
  return { "event": { "kind": kind, "name": name, "description": description, "width": width, "height": height, "serial": seq }, "seq": seq };
}

var rows = [
  {
    "name": "the first reading shows nothing",
    "steps": [
      { "at": 0, "state": { "monitor": mon("added", "DP-1", "Dell U2720Q", 3840, 2160, 1) } }
    ]
  },
  {
    "name": "connected: its card, its description, the connector and resolution",
    "steps": [
      { "at": 0, "state": { "monitor": { "event": null, "seq": 0 } } },
      { "at": 3000, "state": { "monitor": mon("added", "DP-1", "Dell U2720Q", 3840, 2160, 1) },
        "expect": { "key": "monitor", "show": "card", "kind": "event",
          "card": { "icon": "monitor", "title": "Dell U2720Q", "role": "Connected", "detail": "DP-1 · 3840×2160", "tone": "", "clickable": false },
          "host": "open" } }
    ]
  },
  {
    "name": "removed with no description: named by its connector, once",
    "steps": [
      { "at": 0, "state": { "monitor": { "event": null, "seq": 0 } } },
      { "at": 3000, "state": { "monitor": mon("removed", "HDMI-A-1", "", 1920, 1080, 1) },
        "expect": { "key": "monitor", "show": "card",
          "card": { "icon": "desktop_access_disabled", "title": "HDMI-A-1", "role": "Disconnected", "detail": "1920×1080" } } }
    ]
  },
  {
    "name": "no size known: the connector alone",
    "steps": [
      { "at": 0, "state": { "monitor": { "event": null, "seq": 0 } } },
      { "at": 3000, "state": { "monitor": mon("added", "DP-2", "LG 27GL850", 0, 0, 1) },
        "expect": { "key": "monitor", "show": "card", "card": { "title": "LG 27GL850", "detail": "DP-2" } } }
    ]
  },
  {
    "name": "the same event again (a new seq): its card again",
    "steps": [
      { "at": 0, "state": { "monitor": mon("added", "DP-1", "Dell U2720Q", 3840, 2160, 1) } },
      { "at": 3000, "state": { "monitor": mon("added", "DP-1", "Dell U2720Q", 3840, 2160, 2) },
        "expect": { "key": "monitor", "show": "card" } }
    ]
  },
  {
    "name": "the event cleared: nothing",
    "steps": [
      { "at": 0, "state": { "monitor": mon("added", "DP-1", "Dell U2720Q", 3840, 2160, 1) } },
      { "at": 3000, "state": { "monitor": { "event": null, "seq": 1 } } }
    ]
  },
  {
    "name": "one unplugged, another plugged just after: the second card replaces",
    "steps": [
      { "at": 0, "state": { "monitor": { "event": null, "seq": 0 } } },
      { "at": 3000, "state": { "monitor": mon("removed", "DP-1", "Dell U2720Q", 3840, 2160, 1) },
        "expect": { "key": "monitor", "show": "card", "host": "open" } },
      { "at": 3500, "state": { "monitor": mon("added", "HDMI-A-1", "", 1920, 1080, 2) },
        "expect": { "key": "monitor", "show": "card", "card": { "role": "Connected" }, "host": "replace" } }
    ]
  }
];
