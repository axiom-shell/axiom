.pragma library
// LockKeys' timelines: a tile per lock key `keys` lists (Caps Lock, Num
// Lock, Scroll Lock), lit and unusual while on; hidden without LEDs.
//
// State by key (LockKeysWatch, from LockKeysManager while held):
//   capsLock, numLock, scrollLock  { available, value (the LED on) }:
//   `available` LockKeysManager.available (false: no LEDs read yet, or
//   gone), the same for every key

var opts = { "keys": ["capsLock", "numLock"] };
var all = { "keys": ["capsLock", "numLock", "scrollLock"] };

function led(on, available) {
  return { "available": available !== false, "value": on };
}

var rows = [
  {
    "name": "no LEDs read: every tile hidden",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "capsLock": led(false, false), "numLock": led(false, false) },
        "tiles": { "capsLock": { "hidden": true }, "numLock": { "hidden": true } } }
    ]
  },
  {
    "name": "the first reading shows nothing",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "capsLock": led(true), "numLock": led(true) } }
    ]
  },
  {
    "name": "Caps Lock on: its icon, lit and unusual",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "capsLock": led(false), "numLock": led(true) } },
      { "at": 3000, "state": { "capsLock": led(true) },
        "expect": { "key": "capsLock", "show": "tile", "kind": "add",
          "tile": { "icon": "keyboard_capslock", "on": true, "slash": false, "notable": true, "hidden": false, "label": "" },
          "card": null, "host": "ring" } }
    ]
  },
  {
    "name": "Caps Lock off: the same icon, unlit, not struck through",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "capsLock": led(true), "numLock": led(true) } },
      { "at": 3000, "state": { "capsLock": led(false) },
        "expect": { "key": "capsLock", "show": "tile", "kind": "remove", "tile": { "icon": "keyboard_capslock", "on": false, "slash": false, "notable": false } } }
    ]
  },
  {
    "name": "Num Lock on is unusual too",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "capsLock": led(false), "numLock": led(false) } },
      { "at": 3000, "state": { "numLock": led(true) },
        "expect": { "key": "numLock", "show": "tile", "tile": { "icon": "dialpad", "on": true, "notable": true } } }
    ]
  },
  {
    "name": "Scroll Lock, when listed",
    "options": all,
    "steps": [
      { "at": 0, "state": { "capsLock": led(false), "numLock": led(false), "scrollLock": led(false) } },
      { "at": 3000, "state": { "scrollLock": led(true) },
        "expect": { "key": "scrollLock", "show": "tile", "tile": { "icon": "swap_vert", "on": true, "notable": true } } }
    ]
  },
  {
    "name": "a key not listed changes nothing",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "capsLock": led(false), "numLock": led(false), "scrollLock": led(false) } },
      { "at": 3000, "state": { "scrollLock": led(true) } }
    ]
  },
  {
    "name": "the LEDs appearing aren't a change",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "capsLock": led(false, false), "numLock": led(false, false) } },
      { "at": 3000, "state": { "capsLock": led(true), "numLock": led(true) } }
    ]
  },
  {
    "name": "the LEDs going away aren't a change",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "capsLock": led(true), "numLock": led(true) } },
      { "at": 3000, "state": { "capsLock": led(false, false), "numLock": led(false, false) } }
    ]
  },
  {
    "name": "two keys in one reading: both, the later one taking the ring",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "capsLock": led(false), "numLock": led(false) } },
      { "at": 3000, "state": { "capsLock": led(true), "numLock": led(true) },
        "expect": [
          { "key": "capsLock", "show": "tile", "host": "ring" },
          { "key": "numLock", "show": "tile", "host": "ring" }
        ] }
    ]
  },
  {
    "name": "Caps Lock off, then Num Lock off: each rings in turn",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "capsLock": led(true), "numLock": led(true) } },
      { "at": 3000, "state": { "capsLock": led(false) },
        "expect": { "key": "capsLock", "show": "tile", "host": "ring" } },
      { "at": 3500, "state": { "numLock": led(false) },
        "expect": { "key": "numLock", "show": "tile", "host": "ring" } }
    ]
  },
  {
    "name": "beside an unrelated card: shows beside it",
    "options": opts,
    "host": { "card": { "system": "Message", "key": "message", "at": 2800 } },
    "steps": [
      { "at": 0, "state": { "capsLock": led(false), "numLock": led(false) } },
      { "at": 3000, "state": { "capsLock": led(true) },
        "expect": { "key": "capsLock", "show": "tile", "host": "beside" } }
    ]
  },
  {
    "name": "quiet: judged the same (the host doesn't open the OSD for it)",
    "options": { "keys": ["capsLock", "numLock"], "quiet": true },
    "steps": [
      { "at": 0, "state": { "capsLock": led(false), "numLock": led(false) } },
      { "at": 3000, "state": { "capsLock": led(true) },
        "expect": { "key": "capsLock", "show": "tile" } }
    ]
  }
];
