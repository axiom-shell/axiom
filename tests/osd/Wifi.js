.pragma library
// Wifi's timelines: the radio's tile (unusual while off) and a network
// joined, its card (the network's name, Connected and its signal). Leaving a
// network shows nothing (another one is reached through disconnected, so
// it's a card too). Its card folds back as Wi-Fi turns off.
//
// State by key (WifiWatch):
//   wifi  { available (NetworkingManager.available), on (wifiEnabled),
//         value (joined: wifiDevice.connected, steadier than the scanned
//         list), network (the network joined's name, "" until the list
//         catches up), signal (0-100) }
//
// decided: `value` is whether the Wi-Fi device has joined a network (a
//   bool), not the network's name: the card comes as it joins, the name and
//   signal fill in after (today's), and a name arriving late isn't a change.
//   (Cross.js' first airplane row used `"value": ""`; it's `false` now.)
// decided: policies onAdd "card" (joined), onRemove "none" (left: today
//   nothing), onUpdate "icon" (the radio on or off: its `on`); Wi-Fi off
//   while joined is both, the icon wins (OSDEngine's stronger show).
//
// Not expressible as rows: the tile hidden with no NetworkManager (nothing
// is judged across `available: false`).

function w(on, joined, network, signal) {
  return { "available": true, "on": on, "value": joined, "network": network || "", "signal": signal || 0 };
}

var rows = [
  {
    "name": "the first reading shows nothing, a network already joined",
    "steps": [
      { "at": 0, "state": { "wifi": w(true, true, "Home", 72) } }
    ]
  },
  {
    "name": "turned off: its icon unlit, unusual",
    "steps": [
      { "at": 0, "state": { "wifi": w(true, false) } },
      { "at": 3000, "state": { "wifi": w(false, false) },
        "expect": { "key": "wifi", "show": "tile", "kind": "update", "tile": { "icon": "wifi", "on": false, "notable": true, "hidden": false, "slash": false }, "card": null, "host": "ring", "action": { "id": "wifi", "call": "toggle" } } }
    ]
  },
  {
    "name": "turned on: lit, ordinary",
    "steps": [
      { "at": 0, "state": { "wifi": w(false, false) } },
      { "at": 3000, "state": { "wifi": w(true, false) },
        "expect": { "key": "wifi", "show": "tile", "tile": { "on": true, "notable": false } } }
    ]
  },
  {
    "name": "turned off while joined: the icon (not a card)",
    "steps": [
      { "at": 0, "state": { "wifi": w(true, true, "Home", 72) } },
      { "at": 3000, "state": { "wifi": w(false, false) },
        "expect": { "key": "wifi", "show": "tile", "tile": { "on": false, "notable": true } } }
    ]
  },
  {
    "name": "a network joined: its card, its name and signal",
    "steps": [
      { "at": 0, "state": { "wifi": w(true, false) } },
      { "at": 3000, "state": { "wifi": w(true, true, "Home", 72) },
        "expect": { "key": "wifi", "show": "card", "kind": "add",
          "tile": { "on": true, "name": "Home", "signal": 72 },
          "card": { "icon": "wifi", "title": "Home", "role": "Connected", "detail": "72%", "clickable": false },
          "host": "open" } }
    ]
  },
  {
    "name": "joined before its name is in: the card, no signal; the name filling in changes nothing",
    "steps": [
      { "at": 0, "state": { "wifi": w(true, false) } },
      { "at": 3000, "state": { "wifi": w(true, true, "", 0) },
        "expect": { "key": "wifi", "show": "card", "card": { "title": "", "detail": "" } } },
      { "at": 3400, "state": { "wifi": w(true, true, "Home", 72) } }
    ]
  },
  {
    "name": "joined from the WifiNetworks module: still its card, the user's",
    "steps": [
      { "at": 0, "state": { "wifi": w(true, false) } },
      { "at": 3000, "byUser": true, "state": { "wifi": w(true, true, "Home", 72) },
        "expect": { "key": "wifi", "show": "card", "byUser": true } }
    ]
  },
  {
    "name": "leaving a network: nothing",
    "steps": [
      { "at": 0, "state": { "wifi": w(true, true, "Home", 72) } },
      { "at": 3000, "state": { "wifi": w(true, false) } }
    ]
  },
  {
    "name": "another network, through disconnected: its card",
    "steps": [
      { "at": 0, "state": { "wifi": w(true, true, "Home", 72) } },
      { "at": 3000, "state": { "wifi": w(true, false) } },
      { "at": 3600, "state": { "wifi": w(true, true, "Office", 54) },
        "expect": { "key": "wifi", "show": "card", "card": { "title": "Office", "detail": "54%" } } }
    ]
  },
  {
    "name": "the signal changing: nothing",
    "steps": [
      { "at": 0, "state": { "wifi": w(true, true, "Home", 72) } },
      { "at": 3000, "state": { "wifi": w(true, true, "Home", 40) } }
    ]
  },
  {
    "name": "never while off: no name on its tile",
    "steps": [
      { "at": 0, "state": { "wifi": { "available": true, "on": true, "value": false, "network": "Home", "signal": 72 } } },
      { "at": 3000, "state": { "wifi": { "available": true, "on": false, "value": false, "network": "Home", "signal": 72 } },
        "expect": { "key": "wifi", "show": "tile", "tile": { "on": false } } }
    ]
  },
  {
    "name": "no NetworkManager: nothing, nor as it answers",
    "steps": [
      { "at": 0, "state": { "wifi": { "available": false, "on": false, "value": false, "network": "", "signal": 0 } } },
      { "at": 3000, "state": { "wifi": w(true, true, "Home", 72) } }
    ]
  },
  {
    "name": "off just after joining: the card folds back, the icon shows",
    "steps": [
      { "at": 0, "state": { "wifi": w(true, false) } },
      { "at": 3000, "state": { "wifi": w(true, true, "Home", 72) },
        "expect": { "key": "wifi", "show": "card", "host": "open" } },
      { "at": 3300, "state": { "wifi": w(false, false) },
        "expect": { "key": "wifi", "show": "tile", "host": "retract" } }
    ]
  },
  {
    "name": "off long after joining: the card, still out, folds back too",
    "steps": [
      { "at": 0, "state": { "wifi": w(true, false) } },
      { "at": 3000, "state": { "wifi": w(true, true, "Home", 72) },
        "expect": { "key": "wifi", "show": "card", "host": "open" } },
      { "at": 8000, "state": { "wifi": w(false, false) },
        "expect": { "key": "wifi", "show": "tile", "host": "retract" } }
    ]
  },
  {
    "name": "Wi-Fi turned on under its card (still on): suppressed",
    "host": { "card": { "system": "Wifi", "key": "wifi", "at": 2800 } },
    "steps": [
      { "at": 0, "state": { "wifi": w(false, false) } },
      { "at": 3000, "state": { "wifi": w(true, false) },
        "expect": { "key": "wifi", "show": "tile", "host": "suppress" } }
    ]
  }
];
