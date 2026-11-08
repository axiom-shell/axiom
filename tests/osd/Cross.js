.pragma library
// Timelines across systems: the host's arbitration (OSDEngine.arbitrate)
// between one system's change and another's: airplane mode's knock-ons,
// Bluetooth's card taking in Audio's switch to the device it connected
// (FROM origin/bluetooth-daemon, marked), retracting a card only by its own
// key, a message's card, and a device's late level after its card (new).
// The states are each system's (see its own file's header).

var audioOpts = {
  "bars": [{ "type": "other" }, { "type": "master" }, { "type": "microphone" }],
  "tiles": ["audio", "microphone"]
};
var speakers = { "value": "52", "address": "", "name": "Speakers", "detail": "Analog Stereo", "icon": "speaker", "muted": false };
var builtInMic = { "value": "53", "address": "", "name": "Microphone", "detail": "Analog Stereo", "icon": "mic", "muted": false };
var audioBox = { "value": "60", "address": "", "name": "AudioBox Go", "detail": "Analog Stereo", "icon": "speaker", "muted": false };
// Its Bluetooth address in lower case, as PipeWire may give it
var headphones = { "value": "84", "address": "aa:bb:cc:00:00:01", "name": "WH-1000XM4", "detail": "High Fidelity Playback (A2DP Sink)", "icon": "headphones", "muted": false };
var headsetMic = { "value": "84", "address": "AA:BB:CC:00:00:01", "name": "WH-1000XM4", "detail": "Headset Head Unit (HSP/HFP)", "icon": "headset_mic", "muted": false };

function audioStart() {
  return {
    "other": { "level": 0, "muted": false, "streams": "" },
    "master": { "level": 0.5, "muted": false, "node": "52" },
    "micLevel": { "level": 0.8, "muted": false, "node": "53" },
    "audio": speakers,
    "microphone": builtInMic
  };
}

function track(title, playing) {
  return { "value": title, "player": "Spotify", "title": title, "artist": "Artist", "playing": playing !== false, "art": "" };
}

var btHeadset = { "address": "AA:BB:CC:00:00:01", "name": "WH-1000XM4", "glyph": "headset", "battery": 80 };
function bt(kind, seq) {
  return { "available": true, "value": true, "connected": kind === "connected" ? ["WH-1000XM4"] : [], "event": kind ? { "kind": kind, "devices": [btHeadset] } : null, "seq": seq || 0 };
}

function w(on, joined, network) {
  return { "available": true, "on": on, "value": joined, "network": network || "", "signal": joined ? 72 : 0 };
}

var rows = [
  {
    "name": "an unrelated toggle shows beside a card out",
    "systems": ["Caffeine"],
    "host": { "card": { "system": "Vpn", "key": "vpn", "at": 0 } },
    "steps": [
      { "system": "Caffeine", "at": 0, "state": { "caffeine": { "value": false } } },
      { "system": "Caffeine", "at": 300, "state": { "caffeine": { "value": true } },
        "expect": { "show": "tile", "host": "beside" } }
    ]
  },
  // ---- Airplane mode's knock-ons ----
  {
    "name": "airplane mode's knock-on keeps the ring",
    "systems": ["Airplane", "Wifi"],
    "steps": [
      { "system": "Airplane", "at": 0, "state": { "airplane": { "value": false } } },
      { "system": "Wifi", "at": 0, "state": { "wifi": w(true, false) } },
      { "system": "Airplane", "at": 3000, "state": { "airplane": { "value": true } },
        "expect": { "show": "tile", "host": "ring" } },
      { "system": "Wifi", "at": 3300, "state": { "wifi": w(false, false) },
        "expect": { "show": "tile", "host": "keep" } }
    ]
  },
  {
    "name": "airplane mode switching Bluetooth: its knock-on, the ring kept",
    "systems": ["Airplane", "Bluetooth"],
    "steps": [
      { "system": "Airplane", "at": 0, "state": { "airplane": { "value": false } } },
      { "system": "Bluetooth", "at": 0, "state": { "bluetooth": bt(null) } },
      { "system": "Airplane", "at": 3000, "state": { "airplane": { "value": true } },
        "expect": { "key": "airplane", "show": "tile", "host": "ring" } },
      { "system": "Bluetooth", "at": 4999, "state": { "bluetooth": { "available": true, "value": false, "connected": [], "event": null, "seq": 0 } },
        "expect": { "key": "bluetooth", "show": "tile", "host": "keep" } }
    ]
  },
  {
    "name": "airplane mode off, Wi-Fi and Bluetooth coming back on: both kept",
    "systems": ["Airplane", "Wifi", "Bluetooth"],
    "steps": [
      { "system": "Airplane", "at": 0, "state": { "airplane": { "value": true } } },
      { "system": "Wifi", "at": 0, "state": { "wifi": w(false, false) } },
      { "system": "Bluetooth", "at": 0, "state": { "bluetooth": { "available": true, "value": false, "connected": [], "event": null, "seq": 0 } } },
      { "system": "Airplane", "at": 3000, "state": { "airplane": { "value": false } },
        "expect": { "show": "tile", "host": "ring" } },
      { "system": "Wifi", "at": 3400, "state": { "wifi": w(true, false) },
        "expect": { "show": "tile", "host": "keep" } },
      { "system": "Bluetooth", "at": 3600, "state": { "bluetooth": bt(null) },
        "expect": { "show": "tile", "host": "keep" } }
    ]
  },
  {
    "name": "the user's own Wi-Fi toggle past the quiet window takes the ring",
    "systems": ["Airplane", "Wifi"],
    "steps": [
      { "system": "Airplane", "at": 0, "state": { "airplane": { "value": false } } },
      { "system": "Wifi", "at": 0, "state": { "wifi": w(true, false) } },
      { "system": "Airplane", "at": 3000, "state": { "airplane": { "value": true } },
        "expect": { "show": "tile", "host": "ring" } },
      { "system": "Wifi", "at": 5000, "state": { "wifi": w(false, false) },
        "expect": { "show": "tile", "host": "ring" } }
    ]
  },
  {
    "name": "airplane mode just after Wi-Fi: airplane mode always shows",
    "systems": ["Airplane", "Wifi"],
    "steps": [
      { "system": "Airplane", "at": 0, "state": { "airplane": { "value": false } } },
      { "system": "Wifi", "at": 0, "state": { "wifi": w(true, false) } },
      { "system": "Wifi", "at": 3000, "state": { "wifi": w(false, false) },
        "expect": { "show": "tile", "host": "ring" } },
      { "system": "Airplane", "at": 3000, "state": { "airplane": { "value": true } },
        "expect": { "show": "tile", "host": "ring" } }
    ]
  },
  {
    "name": "airplane mode ringed, then an unrelated key: it takes the ring",
    "systems": ["Airplane", "LockKeys"],
    "options": { "LockKeys": { "keys": ["capsLock", "numLock"] }, "Airplane": {} },
    "steps": [
      { "system": "Airplane", "at": 0, "state": { "airplane": { "value": false } } },
      { "system": "LockKeys", "at": 0, "state": { "capsLock": { "available": true, "value": false }, "numLock": { "available": true, "value": true } } },
      { "system": "Airplane", "at": 3000, "state": { "airplane": { "value": true } },
        "expect": { "show": "tile", "host": "ring" } },
      { "system": "LockKeys", "at": 3000, "state": { "capsLock": { "available": true, "value": true } },
        "expect": { "key": "capsLock", "show": "tile", "host": "ring" } }
    ]
  },
  {
    "name": "a network's card out, airplane mode on: beside it; then Wi-Fi off folds it back (the ring kept)",
    "systems": ["Airplane", "Wifi"],
    "steps": [
      { "system": "Airplane", "at": 0, "state": { "airplane": { "value": false } } },
      { "system": "Wifi", "at": 0, "state": { "wifi": w(true, false) } },
      { "system": "Wifi", "at": 3000, "state": { "wifi": w(true, true, "Home") },
        "expect": { "show": "card", "host": "open" } },
      { "system": "Airplane", "at": 3500, "state": { "airplane": { "value": true } },
        "expect": { "show": "tile", "host": "beside" } },
      { "system": "Wifi", "at": 3700, "state": { "wifi": w(false, false) },
        "expect": { "show": "tile", "host": "retract" } }
    ]
  },
  // ---- Retracting is by the card's own key ----
  {
    "name": "Wi-Fi off beside a VPN's card: beside it, the card stays",
    "systems": ["Vpn", "Wifi"],
    "steps": [
      { "system": "Vpn", "at": 0, "state": { "vpn": { "available": true, "members": [{ "id": "home", "name": "Home", "state": "off" }], "address": "" } } },
      { "system": "Wifi", "at": 0, "state": { "wifi": w(true, true, "Home") } },
      { "system": "Vpn", "at": 3000, "state": { "vpn": { "available": true, "members": [{ "id": "home", "name": "Home", "state": "on" }], "address": "10.0.0.2" } },
        "expect": { "show": "card", "host": "open" } },
      { "system": "Wifi", "at": 3300, "state": { "wifi": w(false, false) },
        "expect": { "show": "tile", "host": "beside" } }
    ]
  },
  {
    "name": "an unrelated toggle beside the charger's card",
    "systems": ["Battery", "Caffeine"],
    "options": { "Battery": { "tiles": ["charger", "battery"] }, "Caffeine": {} },
    "steps": [
      { "system": "Battery", "at": 0, "state": { "charger": { "available": true, "value": false, "percent": 50, "charging": false, "full": false, "untilFull": "" } } },
      { "system": "Caffeine", "at": 0, "state": { "caffeine": { "value": false } } },
      { "system": "Battery", "at": 3000, "state": { "charger": { "available": true, "value": true, "percent": 50, "charging": true, "full": false, "untilFull": "2h" } },
        "expect": { "show": "card", "host": "open" } },
      { "system": "Caffeine", "at": 3200, "state": { "caffeine": { "value": true } },
        "expect": { "show": "tile", "host": "beside" } }
    ]
  },
  // ---- A device's late level (new) ----
  {
    "name": "a device's own level arriving late after its card: no bars beside it",
    "systems": ["Audio"],
    "options": { "Audio": audioOpts },
    "steps": [
      { "at": 0, "state": audioStart() },
      { "at": 3000, "settled": false, "state": { "audio": audioBox, "master": { "level": 0.5, "muted": false, "node": "" } },
        "expect": { "key": "audio", "show": "card", "card": { "title": "AudioBox Go" }, "host": "open" } },
      // (its node binding, its volume in: resetBy)
      { "at": 3300, "state": { "master": { "level": 0.35, "muted": false, "node": "60" } } },
      { "at": 3600, "state": { "master": { "level": 0.4, "muted": false, "node": "60" } },
        "expect": { "key": "master", "show": "level", "host": "suppress" } }
    ]
  },
  {
    "name": "the input's late level after its card: suppressed too",
    "systems": ["Audio"],
    "options": { "Audio": audioOpts },
    "steps": [
      { "at": 0, "state": audioStart() },
      { "at": 3000, "settled": false, "state": { "microphone": headsetMic, "micLevel": { "level": 0.8, "muted": false, "node": "" } },
        "expect": { "key": "microphone", "show": "card", "host": "open" } },
      { "at": 3300, "state": { "micLevel": { "level": 0.6, "muted": false, "node": "84" } } },
      { "at": 3500, "state": { "micLevel": { "level": 0.55, "muted": false, "node": "84" } },
        "expect": { "key": "micLevel", "show": "level", "host": "suppress" } }
    ]
  },
  {
    "name": "the volume changed past the quiet window: the bars beside the card",
    "systems": ["Audio"],
    "options": { "Audio": audioOpts },
    "steps": [
      { "at": 0, "state": audioStart() },
      { "at": 3000, "settled": false, "state": { "audio": audioBox, "master": { "level": 0.5, "muted": false, "node": "" } },
        "expect": { "key": "audio", "show": "card", "host": "open" } },
      { "at": 3300, "state": { "master": { "level": 0.35, "muted": false, "node": "60" } } },
      { "at": 5500, "state": { "master": { "level": 0.4, "muted": false, "node": "60" } },
        "expect": { "key": "master", "show": "level", "host": "beside" } }
    ]
  },
  {
    "name": "another system's bar beside a device card: beside it",
    "systems": ["Audio", "Brightness"],
    "options": { "Audio": audioOpts, "Brightness": { "allMonitors": false, "icon": "" } },
    "steps": [
      { "system": "Audio", "at": 0, "state": audioStart() },
      { "system": "Brightness", "at": 0, "state": { "brightness": { "available": true, "level": 0.5, "setAt": 0 } } },
      { "system": "Audio", "at": 3000, "settled": false, "state": { "audio": audioBox },
        "expect": { "key": "audio", "show": "card", "host": "open" } },
      { "system": "Brightness", "at": 3300, "state": { "brightness": { "available": true, "level": 0.6, "setAt": 3300 } },
        "expect": { "key": "brightness", "show": "level", "host": "beside" } }
    ]
  },
  {
    "name": "the system volume beside a capture's card: beside it",
    "systems": ["Privacy", "Audio"],
    "options": { "Audio": audioOpts, "Privacy": { "kinds": ["camera", "micUse", "screenShare"] } },
    "steps": [
      { "system": "Privacy", "at": 0, "state": { "camera": { "members": [] }, "micUse": { "members": [] }, "screenShare": { "members": [] } } },
      { "system": "Audio", "at": 0, "state": audioStart() },
      { "system": "Privacy", "at": 3000, "state": { "camera": { "members": [{ "id": 61, "app": "Firefox" }] } },
        "expect": { "key": "camera", "show": "card", "host": "open" } },
      { "system": "Audio", "at": 3300, "state": { "master": { "level": 0.6, "muted": false, "node": "52" } },
        "expect": { "key": "master", "show": "level", "host": "beside" } }
    ]
  },
  // ---- Captures and devices ----
  {
    "name": "a microphone mute beside a capture's card: not a device switch, beside it",
    "systems": ["Privacy", "Audio"],
    "options": { "Audio": { "bars": [], "tiles": ["audio", "microphone"] }, "Privacy": { "kinds": ["camera", "micUse", "screenShare"] } },
    "steps": [
      { "system": "Privacy", "at": 0, "state": { "camera": { "members": [] }, "micUse": { "members": [] }, "screenShare": { "members": [] } } },
      { "system": "Audio", "at": 0, "state": audioStart() },
      { "system": "Privacy", "at": 3000, "state": { "camera": { "members": [{ "id": 61, "app": "Vesktop" }] } },
        "expect": { "key": "camera", "show": "card", "host": "open" } },
      { "system": "Audio", "at": 3300, "state": { "microphone": Object.assign({}, builtInMic, { "muted": true }) },
        "expect": { "key": "microphone", "show": "tile", "host": "beside" } }
    ]
  },
  {
    "name": "an input switch just after an app's microphone card: it replaces",
    "systems": ["Privacy", "Audio"],
    "options": { "Audio": { "bars": [], "tiles": ["audio", "microphone"] }, "Privacy": { "kinds": ["camera", "micUse", "screenShare"] } },
    "steps": [
      { "system": "Privacy", "at": 0, "state": { "camera": { "members": [] }, "micUse": { "members": [] }, "screenShare": { "members": [] } } },
      { "system": "Audio", "at": 0, "state": audioStart() },
      { "system": "Privacy", "at": 3000, "state": { "micUse": { "members": [{ "id": 70, "app": "OBS" }] } },
        "expect": { "key": "micUse", "show": "card", "host": "open" } },
      { "system": "Audio", "at": 3300, "settled": false, "state": { "microphone": headsetMic },
        "expect": { "key": "microphone", "show": "card", "host": "replace" } }
    ]
  },
  // ---- Bluetooth takes in Audio's switch (origin/bluetooth-daemon) ----
  {
    "name": "[bluetooth-daemon] a headset connecting, then the output switching to it: its card says it",
    "systems": ["Bluetooth", "Audio"],
    "options": { "Audio": audioOpts, "Bluetooth": {} },
    "steps": [
      { "system": "Bluetooth", "at": 0, "state": { "bluetooth": bt(null) } },
      { "system": "Audio", "at": 0, "state": audioStart() },
      { "system": "Bluetooth", "at": 3000, "state": { "bluetooth": bt("connected", 1) },
        "expect": { "key": "bluetooth", "show": "card", "host": "open" } },
      { "system": "Audio", "at": 3800, "settled": false, "state": { "audio": headphones },
        "expect": { "key": "audio", "show": "card", "host": "keep" } },
      { "system": "Audio", "at": 4200, "settled": false, "state": { "microphone": headsetMic },
        "expect": { "key": "microphone", "show": "card", "host": "keep" } }
    ]
  },
  {
    "name": "[bluetooth-daemon] the output switching to it past the quiet window: the user's own, it replaces",
    "systems": ["Bluetooth", "Audio"],
    "options": { "Audio": audioOpts, "Bluetooth": {} },
    "steps": [
      { "system": "Bluetooth", "at": 0, "state": { "bluetooth": bt(null) } },
      { "system": "Audio", "at": 0, "state": audioStart() },
      { "system": "Bluetooth", "at": 3000, "state": { "bluetooth": bt("connected", 1) },
        "expect": { "key": "bluetooth", "show": "card", "host": "open" } },
      { "system": "Audio", "at": 5000, "settled": false, "state": { "audio": headphones },
        "expect": { "key": "audio", "show": "card", "host": "replace" } }
    ]
  },
  {
    "name": "[bluetooth-daemon] the output switching to another device (not Bluetooth): it replaces",
    "systems": ["Bluetooth", "Audio"],
    "options": { "Audio": audioOpts, "Bluetooth": {} },
    "steps": [
      { "system": "Bluetooth", "at": 0, "state": { "bluetooth": bt(null) } },
      { "system": "Audio", "at": 0, "state": audioStart() },
      { "system": "Bluetooth", "at": 3000, "state": { "bluetooth": bt("connected", 1) },
        "expect": { "key": "bluetooth", "show": "card", "host": "open" } },
      { "system": "Audio", "at": 3800, "settled": false, "state": { "audio": audioBox },
        "expect": { "key": "audio", "show": "card", "host": "replace" } }
    ]
  },
  {
    "name": "[bluetooth-daemon] the output leaving a headset just disconnected: it shows",
    "systems": ["Bluetooth", "Audio"],
    "options": { "Audio": audioOpts, "Bluetooth": {} },
    "steps": [
      { "system": "Bluetooth", "at": 0, "state": { "bluetooth": bt("connected", 1) } },
      { "system": "Audio", "at": 0, "state": Object.assign(audioStart(), { "audio": headphones }) },
      { "system": "Bluetooth", "at": 3000, "state": { "bluetooth": bt("disconnected", 2) },
        "expect": { "key": "bluetooth", "show": "card", "card": { "role": "Disconnected" }, "host": "open" } },
      { "system": "Audio", "at": 3500, "settled": false, "state": { "audio": speakers },
        "expect": { "key": "audio", "show": "card", "host": "replace" } }
    ]
  },
  {
    "name": "[bluetooth-daemon] the output's card first, then the headset's: it says more, it replaces",
    "systems": ["Bluetooth", "Audio"],
    "options": { "Audio": audioOpts, "Bluetooth": {} },
    "steps": [
      { "system": "Bluetooth", "at": 0, "state": { "bluetooth": bt(null) } },
      { "system": "Audio", "at": 0, "state": audioStart() },
      { "system": "Audio", "at": 3000, "settled": false, "state": { "audio": headphones },
        "expect": { "key": "audio", "show": "card", "host": "open" } },
      { "system": "Bluetooth", "at": 3400, "state": { "bluetooth": bt("connected", 1) },
        "expect": { "key": "bluetooth", "show": "card", "host": "replace" } }
    ]
  },
  {
    "name": "[bluetooth-daemon] the headset's own mute just after its card: beside it (only a switch is taken in)",
    "systems": ["Bluetooth", "Audio"],
    "options": { "Audio": { "bars": [], "tiles": ["audio", "microphone"] }, "Bluetooth": {} },
    "steps": [
      { "system": "Bluetooth", "at": 0, "state": { "bluetooth": bt(null) } },
      { "system": "Audio", "at": 0, "state": Object.assign(audioStart(), { "audio": headphones }) },
      { "system": "Bluetooth", "at": 3000, "state": { "bluetooth": bt("connected", 1) },
        "expect": { "key": "bluetooth", "show": "card", "host": "open" } },
      { "system": "Audio", "at": 3500, "state": { "audio": Object.assign({}, headphones, { "muted": true }) },
        "expect": { "key": "audio", "show": "tile", "host": "beside" } }
    ]
  },
  {
    "name": "a headset's late level after the Bluetooth card: suppressed",
    "systems": ["Bluetooth", "Audio"],
    "options": { "Audio": audioOpts, "Bluetooth": {} },
    "steps": [
      { "system": "Bluetooth", "at": 0, "state": { "bluetooth": bt(null) } },
      { "system": "Audio", "at": 0, "state": audioStart() },
      { "system": "Bluetooth", "at": 3000, "state": { "bluetooth": bt("connected", 1) },
        "expect": { "key": "bluetooth", "show": "card", "host": "open" } },
      { "system": "Audio", "at": 3800, "settled": false, "state": { "audio": headphones, "master": { "level": 0.5, "muted": false, "node": "" } },
        "expect": { "key": "audio", "show": "card", "host": "keep" } },
      { "system": "Audio", "at": 4100, "state": { "master": { "level": 0.35, "muted": false, "node": "84" } } },
      { "system": "Audio", "at": 4400, "state": { "master": { "level": 0.3, "muted": false, "node": "84" } },
        "expect": { "key": "master", "show": "level", "host": "suppress" } }
    ]
  },
  {
    "name": "another device's level after the Bluetooth card: beside it",
    "systems": ["Bluetooth", "Audio"],
    "options": { "Audio": audioOpts, "Bluetooth": {} },
    "steps": [
      { "system": "Bluetooth", "at": 0, "state": { "bluetooth": bt(null) } },
      { "system": "Audio", "at": 0, "state": audioStart() },
      { "system": "Bluetooth", "at": 3000, "state": { "bluetooth": bt("connected", 1) },
        "expect": { "key": "bluetooth", "show": "card", "host": "open" } },
      { "system": "Audio", "at": 3400, "state": { "master": { "level": 0.35, "muted": false, "node": "52" } },
        "expect": { "key": "master", "show": "level", "host": "beside" } }
    ]
  },
  // ---- A message's card ----
  {
    "name": "a message's card: a tile shows beside it, even just after",
    "systems": ["Message", "LockKeys"],
    "options": { "LockKeys": { "keys": ["capsLock", "numLock"] }, "Message": {} },
    "steps": [
      { "system": "Message", "at": 0, "state": { "message": { "event": null, "seq": 0 } } },
      { "system": "LockKeys", "at": 0, "state": { "capsLock": { "available": true, "value": false }, "numLock": { "available": true, "value": true } } },
      { "system": "Message", "at": 3000, "state": { "message": { "event": { "icon": "save", "text": "Saved", "detail": "", "tone": "" }, "seq": 1 } },
        "expect": { "key": "message", "show": "card", "host": "open" } },
      { "system": "LockKeys", "at": 3300, "state": { "capsLock": { "available": true, "value": true } },
        "expect": { "key": "capsLock", "show": "tile", "host": "beside" } }
    ]
  },
  {
    "name": "a message's card gives way to another card",
    "systems": ["Message", "Wifi"],
    "steps": [
      { "system": "Message", "at": 0, "state": { "message": { "event": null, "seq": 0 } } },
      { "system": "Wifi", "at": 0, "state": { "wifi": w(true, false) } },
      { "system": "Message", "at": 3000, "state": { "message": { "event": { "icon": "save", "text": "Saved", "detail": "", "tone": "" }, "seq": 1 } },
        "expect": { "key": "message", "show": "card", "host": "open" } },
      { "system": "Wifi", "at": 3300, "state": { "wifi": w(true, true, "Home") },
        "expect": { "key": "wifi", "show": "card", "host": "replace" } }
    ]
  },
  {
    "name": "a card out, then a message: the message replaces it",
    "systems": ["Wifi", "Message"],
    "steps": [
      { "system": "Message", "at": 0, "state": { "message": { "event": null, "seq": 0 } } },
      { "system": "Wifi", "at": 0, "state": { "wifi": w(true, false) } },
      { "system": "Wifi", "at": 3000, "state": { "wifi": w(true, true, "Home") },
        "expect": { "key": "wifi", "show": "card", "host": "open" } },
      { "system": "Message", "at": 3300, "state": { "message": { "event": { "icon": "nightlight", "text": "Night light", "detail": "Not available here", "tone": "warning" }, "seq": 1 } },
        "expect": { "key": "message", "show": "card", "host": "replace" } }
    ]
  },
  {
    "name": "a card replaces the ring's place without asking it",
    "systems": ["Airplane", "Wifi"],
    "steps": [
      { "system": "Airplane", "at": 0, "state": { "airplane": { "value": true } } },
      { "system": "Wifi", "at": 0, "state": { "wifi": w(false, false) } },
      { "system": "Airplane", "at": 3000, "state": { "airplane": { "value": false } },
        "expect": { "show": "tile", "host": "ring" } },
      { "system": "Wifi", "at": 3300, "state": { "wifi": w(true, true, "Home") },
        "expect": { "key": "wifi", "show": "card", "host": "open" } }
    ]
  },
  // ---- Now playing's card yields ----
  {
    "name": "a device switch pausing the music: the device's card stays out",
    "systems": ["Audio", "Media"],
    "options": { "Audio": audioOpts, "Media": { "onTrackChange": true, "onPlayPause": true } },
    "steps": [
      { "system": "Audio", "at": 0, "state": audioStart() },
      { "system": "Media", "at": 0, "state": { "media": track("Song A") } },
      { "system": "Audio", "at": 3000, "settled": false, "state": { "audio": audioBox },
        "expect": { "key": "audio", "show": "card", "host": "open" } },
      { "system": "Media", "at": 3300, "state": { "media": track("Song A", false) },
        "expect": { "key": "media", "show": "card", "host": "keep" } },
      // Past the quiet window too: its card never covers another's
      { "system": "Media", "at": 8000, "state": { "media": track("Song B") },
        "expect": { "key": "media", "show": "card", "host": "keep" } }
    ]
  },
  {
    "name": "Now playing's card still replaces its own, and gives way to another's",
    "systems": ["Media", "Wifi"],
    "options": { "Media": { "onTrackChange": true, "onPlayPause": false }, "Wifi": {} },
    "steps": [
      { "system": "Media", "at": 0, "state": { "media": track("Song A") } },
      { "system": "Wifi", "at": 0, "state": { "wifi": w(true, false) } },
      { "system": "Media", "at": 3000, "state": { "media": track("Song B") },
        "expect": { "key": "media", "show": "card", "host": "open" } },
      { "system": "Media", "at": 6000, "state": { "media": track("Song C") },
        "expect": { "key": "media", "show": "card", "host": "replace" } },
      { "system": "Wifi", "at": 6300, "state": { "wifi": w(true, true, "Home") },
        "expect": { "key": "wifi", "show": "card", "host": "replace" } }
    ]
  }
];
