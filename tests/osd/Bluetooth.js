.pragma library
// Bluetooth's timelines: the radio's tile (never unusual; the connected
// devices name it) and the devices' card: connecting, disconnecting, a
// device's battery low or critical.
//
// FROM origin/bluetooth-daemon: every row below that has an event (the
// per-device card, battery low / critical, its `alert`, and Cross.js's
// absorbing of Audio's switch by address) comes from that unmerged branch,
// which merges before this rewrite.
// Only the radio's on/off rows are today's main.
//
// State by key (BluetoothWatch):
//   bluetooth  { available, value (the radio on), connected (the connected
//              devices' names, BluetoothManager.deviceLabel), event
//              (BluetoothManager.lastEvent: { kind: "connected" |
//              "disconnected" | "low" | "critical", devices: [{ address,
//              name, glyph, battery (0-100, -1 none) }] }, or null), seq
//              (counting each event, so one like the last still counts) }
//
// decided: one key, `bluetooth`, holds both the radio (`value`, judged as a
//   scalar: its icon) and the devices' events (its card): the card must
//   fold back as the radio turns off (retract is by system and key), and
//   the radio coming on under the card is its own knock-on (sameChange by
//   key). Declared, no judge(): `carriesEvents` (a new `seq` with an event
//   is an "event", its card by `onEvent`; the radio's `value` the engine's
//   scalar).
// decided: a battery low / critical card carries `alert: true`
//   (`alertKinds: ["low", "critical"]`): it opens the OSD even just after
//   a click marked `bluetooth` (OSDEngine.opens).
// decided: the tile carries `event` and `devices` (the last event's), which
//   absorbs() reads against Audio's tile `address`.

function radio(on, connected) {
  return { "available": true, "value": on, "connected": connected || [], "event": null, "seq": 0 };
}
function dev(address, name, glyph, battery) {
  return { "address": address, "name": name, "glyph": glyph, "battery": battery };
}
var headset = dev("AA:BB:CC:00:00:01", "WH-1000XM4", "headset", 80);
var mouse = dev("AA:BB:CC:00:00:02", "MX Master", "mouse", -1);

function ev(kind, devices, seq, connected) {
  return { "available": true, "value": true, "connected": connected || devices.map(d => d.name), "event": { "kind": kind, "devices": devices }, "seq": seq };
}

var rows = [
  {
    "name": "the first reading shows nothing, an event already there too",
    "steps": [
      { "at": 0, "state": { "bluetooth": ev("connected", [headset], 3) } }
    ]
  },
  // ---- The radio (today's main) ----
  {
    "name": "turned on: its icon, lit, never unusual",
    "steps": [
      { "at": 0, "state": { "bluetooth": radio(false) } },
      { "at": 3000, "state": { "bluetooth": radio(true) },
        "expect": { "key": "bluetooth", "show": "tile", "tile": { "icon": "bluetooth", "on": true, "notable": false, "hidden": false, "slash": false }, "card": null, "host": "ring", "action": { "id": "bluetooth", "call": "toggle" } } }
    ]
  },
  {
    "name": "turned off: its icon unlit, still ordinary",
    "steps": [
      { "at": 0, "state": { "bluetooth": radio(true, ["WH-1000XM4"]) } },
      { "at": 3000, "state": { "bluetooth": radio(false) },
        "expect": { "key": "bluetooth", "show": "tile", "tile": { "on": false, "notable": false, "name": "" } } }
    ]
  },
  {
    "name": "turned on from the panel: still its icon, the user's",
    "steps": [
      { "at": 0, "state": { "bluetooth": radio(false) } },
      { "at": 3000, "byUser": true, "state": { "bluetooth": radio(true) },
        "expect": { "key": "bluetooth", "show": "tile", "byUser": true } }
    ]
  },
  {
    "name": "no adapter: nothing, nor as one appears",
    "steps": [
      { "at": 0, "state": { "bluetooth": { "available": false, "value": false, "connected": [], "event": null, "seq": 0 } } },
      { "at": 3000, "state": { "bluetooth": radio(true) } }
    ]
  },
  {
    "name": "the connected devices' names changing alone: nothing",
    "steps": [
      { "at": 0, "state": { "bluetooth": radio(true, []) } },
      { "at": 3000, "state": { "bluetooth": radio(true, ["MX Master"]) } }
    ]
  },
  // ---- Devices (origin/bluetooth-daemon) ----
  {
    "name": "[bluetooth-daemon] a device connected: its card, its icon, name and battery; the tile naming the connected",
    "steps": [
      { "at": 0, "state": { "bluetooth": radio(true) } },
      { "at": 3000, "state": { "bluetooth": ev("connected", [headset], 1, ["WH-1000XM4", "MX Master"]) },
        "expect": { "key": "bluetooth", "show": "card", "kind": "event",
          "tile": { "icon": "bluetooth", "on": true, "notable": false, "name": "WH-1000XM4, MX Master", "event": "connected" },
          "card": { "icon": "headset", "title": "WH-1000XM4", "role": "Connected", "detail": "80%", "tone": "", "clickable": false },
          "host": "open" } }
    ]
  },
  {
    "name": "[bluetooth-daemon] a device with no battery: no detail",
    "steps": [
      { "at": 0, "state": { "bluetooth": radio(true) } },
      { "at": 3000, "state": { "bluetooth": ev("connected", [mouse], 1) },
        "expect": { "key": "bluetooth", "show": "card", "card": { "icon": "mouse", "title": "MX Master", "detail": "" } } }
    ]
  },
  {
    "name": "[bluetooth-daemon] several connected together: their names, Bluetooth's icon",
    "steps": [
      { "at": 0, "state": { "bluetooth": radio(true) } },
      { "at": 3000, "state": { "bluetooth": ev("connected", [headset, mouse], 1) },
        "expect": { "key": "bluetooth", "show": "card", "card": { "icon": "bluetooth", "title": "WH-1000XM4, MX Master", "role": "Connected", "detail": "" } } }
    ]
  },
  {
    "name": "[bluetooth-daemon] a device disconnected: its card",
    "steps": [
      { "at": 0, "state": { "bluetooth": radio(true, ["WH-1000XM4"]) } },
      { "at": 3000, "state": { "bluetooth": ev("disconnected", [headset], 1, []) },
        "expect": { "key": "bluetooth", "show": "card", "card": { "icon": "bluetooth_disabled", "title": "WH-1000XM4", "role": "Disconnected", "detail": "" } } }
    ]
  },
  {
    "name": "[bluetooth-daemon] a device's battery low: its card, alert",
    "steps": [
      { "at": 0, "state": { "bluetooth": radio(true, ["MX Master"]) } },
      { "at": 3000, "state": { "bluetooth": ev("low", [dev("AA:BB:CC:00:00:02", "MX Master", "mouse", 18)], 1) },
        "expect": { "key": "bluetooth", "show": "card", "alert": true,
          "card": { "icon": "battery_low", "title": "MX Master", "role": "Battery low", "detail": "18%", "tone": "" } } }
    ]
  },
  {
    "name": "[bluetooth-daemon] critical: on the warning colour, alert",
    "steps": [
      { "at": 0, "state": { "bluetooth": radio(true, ["MX Master"]) } },
      { "at": 3000, "state": { "bluetooth": ev("critical", [dev("AA:BB:CC:00:00:02", "MX Master", "mouse", 4)], 1) },
        "expect": { "key": "bluetooth", "show": "card", "alert": true,
          "card": { "icon": "battery_alert", "role": "Battery critically low", "detail": "4%", "tone": "warning" } } }
    ]
  },
  {
    "name": "[bluetooth-daemon] a battery low just after a click on Bluetooth: alert still (it opens the OSD)",
    "steps": [
      { "at": 0, "state": { "bluetooth": radio(true, ["MX Master"]) } },
      { "at": 3000, "byUser": true, "state": { "bluetooth": ev("low", [dev("AA:BB:CC:00:00:02", "MX Master", "mouse", 18)], 1) },
        "expect": { "key": "bluetooth", "show": "card", "alert": true, "byUser": true, "opens": true } }
    ]
  },
  {
    "name": "[bluetooth-daemon] a connect or disconnect is no alert (it may be the click's)",
    "steps": [
      { "at": 0, "state": { "bluetooth": radio(true) } },
      { "at": 3000, "byUser": true, "state": { "bluetooth": ev("connected", [headset], 1) },
        "expect": { "key": "bluetooth", "show": "card", "byUser": true, "alert": false, "opens": false } },
      { "at": 6000, "byUser": true, "state": { "bluetooth": ev("disconnected", [headset], 2, []) },
        "expect": { "key": "bluetooth", "show": "card", "byUser": true } }
    ]
  },
  {
    "name": "[bluetooth-daemon] the same event again (a new seq): its card again",
    "steps": [
      { "at": 0, "state": { "bluetooth": ev("connected", [headset], 1) } },
      { "at": 3000, "state": { "bluetooth": ev("connected", [headset], 2) },
        "expect": { "key": "bluetooth", "show": "card" } }
    ]
  },
  {
    "name": "[bluetooth-daemon] the event cleared: nothing",
    "steps": [
      { "at": 0, "state": { "bluetooth": ev("connected", [headset], 1) } },
      { "at": 3000, "state": { "bluetooth": { "available": true, "value": true, "connected": ["WH-1000XM4"], "event": null, "seq": 1 } } }
    ]
  },
  {
    "name": "[bluetooth-daemon] the radio off just after a connect: the card folds back, its icon shows",
    "steps": [
      { "at": 0, "state": { "bluetooth": radio(true) } },
      { "at": 3000, "state": { "bluetooth": ev("connected", [headset], 1) },
        "expect": { "key": "bluetooth", "show": "card", "host": "open" } },
      { "at": 3300, "state": { "bluetooth": { "available": true, "value": false, "connected": [], "event": { "kind": "connected", "devices": [headset] }, "seq": 1 } },
        "expect": { "key": "bluetooth", "show": "tile", "tile": { "on": false }, "host": "retract" } }
    ]
  },
  {
    "name": "[bluetooth-daemon] the radio off long after a connect: the card folds back too",
    "steps": [
      { "at": 0, "state": { "bluetooth": radio(true) } },
      { "at": 3000, "state": { "bluetooth": ev("connected", [headset], 1) },
        "expect": { "key": "bluetooth", "show": "card", "host": "open" } },
      { "at": 9000, "state": { "bluetooth": { "available": true, "value": false, "connected": [], "event": { "kind": "connected", "devices": [headset] }, "seq": 1 } },
        "expect": { "key": "bluetooth", "show": "tile", "host": "retract" } }
    ]
  },
  {
    "name": "[bluetooth-daemon] the radio on with its devices' card out: suppressed",
    "host": { "card": { "system": "Bluetooth", "key": "bluetooth", "at": 2800 } },
    "steps": [
      { "at": 0, "state": { "bluetooth": { "available": true, "value": false, "connected": [], "event": { "kind": "connected", "devices": [headset] }, "seq": 1 } } },
      { "at": 3000, "state": { "bluetooth": ev("connected", [headset], 1) },
        "expect": { "key": "bluetooth", "show": "tile", "host": "suppress" } }
    ]
  },
  {
    "name": "[bluetooth-daemon] another device just after: its card replaces",
    "steps": [
      { "at": 0, "state": { "bluetooth": radio(true) } },
      { "at": 3000, "state": { "bluetooth": ev("connected", [headset], 1) },
        "expect": { "key": "bluetooth", "show": "card", "host": "open" } },
      { "at": 3500, "state": { "bluetooth": ev("connected", [mouse], 2) },
        "expect": { "key": "bluetooth", "show": "card", "card": { "title": "MX Master" }, "host": "replace" } }
    ]
  }
];
