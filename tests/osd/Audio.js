.pragma library
// Audio's timelines: the level bars (system volume, other apps, an app,
// the microphone's) and the output and input device tiles, with the
// device-switch card ("Output", "Input", "Output and input").
//
// State by key (what AudioWatch reports):
//   master, micLevel   { level (0-1), muted }: the default output's / input's
//   other, app:<i>     { level, muted, streams }: the first stream no App bar
//                      matches / the streams bar <i> of `bars` matches;
//                      `streams` their node ids joined ("61,74"), so the set
//                      changing tells itself from a level changing
//   audio, microphone  { value, device, address, name, detail, icon, muted }:
//                      `value` the physical device last in use
//                      (AudioManager.deviceKey), kept through a gap with
//                      none (a Bluetooth profile switch replaces the node);
//                      `device` the one now ("" in a gap: the tile hides);
//                      `address` its Bluetooth address, else "";
//                      `name` / `detail` AudioManager.deviceLabel's title and
//                      profile; `icon` the device kind's, unmuted
// Settled (AudioWatch.settled): AudioManager.sinkSettled() for master,
// other, app and audio, sourceSettled() for micLevel and microphone.
//
// decided: the microphone's bar is the key `micLevel` (its mark
//   "microphone"), since the input device's tile keeps `microphone`; an App
//   bar is `app:<its index in bars>` (several may be listed); the rest keep
//   their type. Keys must be unique in `exposes`.
// decided: `exposes` lists the bars in `bars` order, then the tiles in
//   `tiles` order (the order a step's changes come in).
// decided: the tile carries `device` (the kept key, `value`) and `address`,
//   which sameChange and Bluetooth's absorbs read.
// decided: a device switch is judged by Audio's own judge(), unsettled or
//   not (a switch is always unsettled: the new node binding), as the old
//   watcher reported it whatever sinkSettled() said; a mute and a level
//   count only while settled.

var opts = {
  "bars": [{ "type": "other" }, { "type": "master" }, { "type": "microphone" }],
  "tiles": ["audio", "microphone"]
};

var speakers = { "value": "52", "device": "52", "address": "", "name": "Speakers", "detail": "Analog Stereo", "icon": "speaker", "muted": false };
var audioBox = { "value": "60", "device": "60", "address": "", "name": "AudioBox Go", "detail": "Analog Stereo", "icon": "speaker", "muted": false };
var builtInMic = { "value": "53", "device": "53", "address": "", "name": "Microphone", "detail": "Analog Stereo", "icon": "mic", "muted": false };
var headphones = { "value": "84", "device": "84", "address": "AA:BB:CC:00:00:01", "name": "WH-1000XM4", "detail": "High Fidelity Playback (A2DP Sink)", "icon": "headphones", "muted": false };
var headsetMic = { "value": "84", "device": "84", "address": "AA:BB:CC:00:00:01", "name": "WH-1000XM4", "detail": "Headset Head Unit (HSP/HFP)", "icon": "headset_mic", "muted": false };

function dev(base, extra) {
  return Object.assign({}, base, extra || {});
}

// The state at the start: every key's first reading
function start(extra) {
  return Object.assign({
    "other": { "level": 0, "muted": false, "streams": "" },
    "master": { "level": 0.5, "muted": false },
    "micLevel": { "level": 0.8, "muted": false },
    "audio": speakers,
    "microphone": builtInMic
  }, extra || {});
}

var rows = [
  {
    "name": "the first reading shows nothing",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() }
    ]
  },
  // ---- Mutes ----
  {
    "name": "the output muted: the bar, and its device's icon struck through",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "master": { "level": 0.5, "muted": true }, "audio": dev(speakers, { "muted": true }) },
        "expect": [
          { "key": "master", "show": "level", "kind": "level", "host": "open" },
          { "key": "audio", "show": "tile", "kind": "update", "tile": { "icon": "speaker", "on": false, "slash": true, "notable": true, "hidden": false }, "host": "ring" }
        ] }
    ]
  },
  {
    "name": "the output unmuted: lit, ordinary",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "master": { "level": 0.5, "muted": true }, "audio": dev(speakers, { "muted": true }) }) },
      { "at": 3000, "state": { "master": { "level": 0.5, "muted": false }, "audio": speakers },
        "expect": [
          { "key": "master", "show": "level" },
          { "key": "audio", "show": "tile", "kind": "update", "tile": { "on": true, "slash": false, "notable": false } }
        ] }
    ]
  },
  {
    "name": "the microphone muted: its bar and its tile, the base icon struck through",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "microphone": dev(builtInMic, { "icon": "" }) }) },
      { "at": 3000, "state": { "micLevel": { "level": 0.8, "muted": true }, "microphone": dev(builtInMic, { "icon": "", "muted": true }) },
        "expect": [
          { "key": "micLevel", "show": "level", "host": "open" },
          { "key": "microphone", "show": "tile", "kind": "update", "tile": { "icon": "mic", "on": false, "slash": true, "notable": true }, "host": "ring" }
        ] }
    ]
  },
  {
    "name": "an output without its own icon: the speaker",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "audio": dev(speakers, { "icon": "" }) }) },
      { "at": 3000, "state": { "audio": dev(speakers, { "icon": "", "muted": true }) },
        "expect": [{ "key": "audio", "show": "tile", "tile": { "icon": "volume_up" } }] }
    ]
  },
  {
    "name": "a mute while the device isn't settled is the device's: nothing",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "settled": false, "state": { "master": { "level": 0.5, "muted": true }, "audio": dev(speakers, { "muted": true }) } }
    ]
  },
  {
    "name": "muted from the panel: still shown (the host keeps a shut OSD shut)",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "byUser": true, "state": { "audio": dev(speakers, { "muted": true }) },
        "expect": [{ "key": "audio", "show": "tile", "byUser": true }] }
    ]
  },
  {
    "name": "the output muted, then the input: each takes the ring",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "audio": dev(speakers, { "muted": true }) },
        "expect": [{ "key": "audio", "show": "tile", "host": "ring" }] },
      { "at": 3300, "state": { "microphone": dev(builtInMic, { "muted": true }) },
        "expect": [{ "key": "microphone", "show": "tile", "host": "ring" }] }
    ]
  },
  // ---- Levels ----
  {
    "name": "the system volume: the bars",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "master": { "level": 0.6, "muted": false } },
        "expect": { "key": "master", "show": "level", "kind": "level", "card": null, "host": "open" } }
    ]
  },
  {
    "name": "the system volume from the Volume widget: still a level, the user's",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "byUser": true, "state": { "master": { "level": 0.6, "muted": false } },
        "expect": { "key": "master", "show": "level", "byUser": true } }
    ]
  },
  {
    "name": "the volume cleared to 0 as a removed node goes: not settled, nothing",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "settled": false, "state": { "master": { "level": 0, "muted": false } } }
    ]
  },
  {
    "name": "the microphone's level",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "micLevel": { "level": 0.4, "muted": false } },
        "expect": { "key": "micLevel", "show": "level", "host": "open" } }
    ]
  },
  {
    "name": "other apps: a stream's level shows, the set of streams changing doesn't",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "other": { "level": 0.7, "muted": false, "streams": "61" } } },
      { "at": 6000, "state": { "other": { "level": 0.5, "muted": false, "streams": "61" } },
        "expect": { "key": "other", "show": "level" } },
      { "at": 9000, "state": { "other": { "level": 0.9, "muted": false, "streams": "74" } } },
      { "at": 12000, "state": { "other": { "level": 0.9, "muted": true, "streams": "74" } },
        "expect": { "key": "other", "show": "level" } }
    ]
  },
  {
    "name": "an App bar: its streams' level, keyed by its place in bars",
    "options": { "bars": [{ "type": "master" }, { "type": "app", "apps": ["firefox"] }], "tiles": ["audio", "microphone"] },
    "steps": [
      { "at": 0, "state": start({ "app:1": { "level": 0.3, "muted": false, "streams": "88" } }) },
      { "at": 3000, "state": { "app:1": { "level": 0.35, "muted": false, "streams": "88" } },
        "expect": { "key": "app:1", "show": "level", "host": "open" } },
      { "at": 6000, "state": { "app:1": { "level": 0.35, "muted": false, "streams": "88,90" } } }
    ]
  },
  {
    "name": "a bar not listed changes nothing",
    "options": { "bars": [{ "type": "master" }], "tiles": ["audio", "microphone"] },
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "micLevel": { "level": 0.1, "muted": false }, "other": { "level": 0.2, "muted": false, "streams": "" } } }
    ]
  },
  // ---- Device switches ----
  {
    "name": "the output switched to another device: its card",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "settled": false, "state": { "audio": audioBox, "master": { "level": 0.3, "muted": false } },
        "expect": { "key": "audio", "show": "card", "kind": "change",
          "tile": { "icon": "speaker", "on": true, "slash": false, "notable": false, "hidden": false, "device": "60" },
          "card": { "icon": "speaker", "title": "AudioBox Go", "role": "Output", "detail": "Analog Stereo", "tone": "", "clickable": false },
          "host": "open" } }
    ]
  },
  {
    "name": "the input switched: its card says Input",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "settled": false, "state": { "microphone": dev(audioBox, { "icon": "mic", "value": "61", "device": "61" }) },
        "expect": { "key": "microphone", "show": "card", "card": { "title": "AudioBox Go", "role": "Input", "icon": "mic" } } }
    ]
  },
  {
    "name": "switched from the AudioMixer: still its card, the user's",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "byUser": true, "settled": false, "state": { "audio": audioBox },
        "expect": { "key": "audio", "show": "card", "byUser": true } }
    ]
  },
  {
    "name": "the first device appearing isn't a switch",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "audio": { "value": "", "device": "", "address": "", "name": "", "detail": "", "icon": "", "muted": false } }) },
      { "at": 3000, "settled": false, "state": { "audio": speakers } }
    ]
  },
  {
    "name": "a Bluetooth headset's profile switch keeps its device: nothing",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "audio": headphones }) },
      { "at": 3000, "settled": false, "state": { "audio": dev(headphones, { "device": "", "name": "", "detail": "", "icon": "" }) } },
      { "at": 3200, "settled": false, "state": { "audio": dev(headphones, { "detail": "Headset Head Unit (HSP/HFP)", "icon": "headset" }) } }
    ]
  },
  {
    "name": "a gap with no device, then another one: its card",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "settled": false, "state": { "audio": dev(speakers, { "device": "", "name": "", "detail": "", "icon": "" }) } },
      { "at": 3500, "settled": false, "state": { "audio": audioBox },
        "expect": { "key": "audio", "show": "card", "card": { "title": "AudioBox Go", "role": "Output" } } }
    ]
  },
  {
    "name": "a switch with its level in the same step: only the card",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "settled": { "master": false, "audio": false }, "state": { "audio": audioBox, "master": { "level": 0.2, "muted": false } },
        "expect": { "key": "audio", "show": "card" } }
    ]
  },
  {
    "name": "a switch and a mute in one step: the card",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "settled": false, "state": { "audio": dev(audioBox, { "muted": true }) },
        "expect": { "key": "audio", "show": "card", "tile": { "slash": true } } }
    ]
  },
  {
    "name": "a headset taking the output then the input: one change, one card saying both",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "settled": false, "state": { "audio": headphones },
        "expect": { "key": "audio", "show": "card", "card": { "title": "WH-1000XM4", "role": "Output" }, "host": "open" } },
      { "at": 3400, "settled": false, "state": { "microphone": headsetMic },
        "expect": { "key": "microphone", "show": "card", "card": { "role": "Output and input", "detail": "Headset Head Unit (HSP/HFP)" }, "host": "keep" } }
    ]
  },
  {
    "name": "a headset taking the input then the output: either order",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "settled": false, "state": { "microphone": headsetMic },
        "expect": { "key": "microphone", "show": "card", "card": { "role": "Input" }, "host": "open" } },
      { "at": 3400, "settled": false, "state": { "audio": headphones },
        "expect": { "key": "audio", "show": "card", "card": { "role": "Output and input" }, "host": "keep" } }
    ]
  },
  {
    "name": "the input following the output past the quiet window: the user's own, it replaces",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "settled": false, "state": { "audio": headphones },
        "expect": { "key": "audio", "show": "card", "host": "open" } },
      { "at": 5000, "settled": false, "state": { "microphone": headsetMic },
        "expect": { "key": "microphone", "show": "card", "host": "replace" } }
    ]
  },
  {
    "name": "the input switching to another device just after: it replaces",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "settled": false, "state": { "audio": audioBox },
        "expect": { "key": "audio", "show": "card", "host": "open" } },
      { "at": 3300, "settled": false, "state": { "microphone": headsetMic },
        "expect": { "key": "microphone", "show": "card", "card": { "role": "Input" }, "host": "replace" } }
    ]
  },
  {
    "name": "the output switching again just after: it replaces",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "settled": false, "state": { "audio": audioBox },
        "expect": { "key": "audio", "show": "card", "host": "open" } },
      { "at": 3300, "settled": false, "state": { "audio": headphones },
        "expect": { "key": "audio", "show": "card", "card": { "title": "WH-1000XM4" }, "host": "replace" } }
    ]
  },
  {
    "name": "the microphone's tile not listed: the card says Output though the input holds the same device",
    "options": { "bars": [{ "type": "master" }], "tiles": ["audio"] },
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "settled": false, "state": { "audio": headphones, "microphone": headsetMic },
        "expect": { "key": "audio", "show": "card", "card": { "role": "Output" } } }
    ]
  },
  {
    "name": "the new device's mute coming in just after its card: suppressed",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "settled": false, "state": { "microphone": headsetMic },
        "expect": { "key": "microphone", "show": "card", "host": "open" } },
      { "at": 3300, "state": { "microphone": dev(headsetMic, { "muted": true }), "micLevel": { "level": 0.8, "muted": true } },
        "expect": [
          { "key": "micLevel", "show": "level", "host": "suppress" },
          { "key": "microphone", "show": "tile", "host": "suppress" }
        ] }
    ]
  },
  {
    "name": "the other key's mute just after a device card: suppressed too (any of Audio's keys)",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "settled": false, "state": { "audio": headphones },
        "expect": { "key": "audio", "show": "card", "host": "open" } },
      { "at": 3300, "state": { "microphone": dev(builtInMic, { "muted": true }) },
        "expect": { "key": "microphone", "show": "tile", "host": "suppress" } }
    ]
  },
  {
    "name": "the user's own mute past the quiet window: beside the card",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "settled": false, "state": { "microphone": headsetMic },
        "expect": { "key": "microphone", "show": "card", "host": "open" } },
      { "at": 5000, "state": { "microphone": dev(headsetMic, { "muted": true }) },
        "expect": { "key": "microphone", "show": "tile", "host": "beside" } }
    ]
  },
  {
    "name": "a switch just after a mute was ringed: the card opens",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "microphone": dev(builtInMic, { "muted": true }) },
        "expect": { "key": "microphone", "show": "tile", "host": "ring" } },
      { "at": 3300, "settled": false, "state": { "microphone": dev(headsetMic, { "muted": true }) },
        "expect": { "key": "microphone", "show": "card", "host": "open" } }
    ]
  },
  {
    "name": "quiet: judged the same (the host doesn't open the OSD for it)",
    "options": { "bars": opts.bars, "tiles": opts.tiles, "quiet": true },
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "settled": false, "state": { "audio": audioBox },
        "expect": { "key": "audio", "show": "card" } }
    ]
  }
];
