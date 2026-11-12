.pragma library
// Privacy's timelines: the apps using a camera (camera), a microphone
// (micUse) or sharing the screen (screenShare). A stream starting is its
// card; one of several stopping is a "still" card naming those left; a call
// app dropping one of the camera and the microphone but keeping the other
// is a "still" card too; the last one stopping is the unlit icon. One app on
// the camera and the microphone at once is one card. A capture stopping
// under its card (a picker's preview) keeps naming the apps: the change
// carries its `members` as it saw them (the card's memory, kept by the
// host with the change while the card is out).
//
// State by key (PrivacyWatch; PrivacyManager.cameraCaptures /
// screenCaptures, AudioManager.micCaptures):
//   camera, micUse, screenShare  { members: [{ id, app }] }: the capturing
//   streams by node id (an app's name read after its stream starts isn't
//   another app: the id stays put), `app` its app's name
//   (AudioManager.appName)
// All declared (no judge()): the definition counts anyone's changes
// (`anyone`), removes with "still", names members by `ownerField: "app"`,
// groups camera and micUse (one app on both: one card; one dropped while
// the other's kept: a "still" card), and its cards come from each entry's
// `roles` (OSDEngine.cardOf).
//
// decided: a "still" card's title is the apps left (one name each, joined
//   ", "), its role "Still using the camera" / "Still using the microphone"
//   / "Still sharing the screen" (the brief's "Still using the microphone:
//   OBS" as the card's two lines).
// decided: a call app (an app on both camera and micUse) dropping one but
//   keeping the other is a "still" card on the dropped key (kind "remove",
//   still: true) naming that app, with the kept one's role ("Vesktop" /
//   "Still using the microphone") and the kept one's icon; only while the
//   OSD lists the kept kind (`shows`). The engine makes it from the group.
// decided: a "still" card against a still card of the same key within the
//   quiet window "keep"s it (several stopping one after another: one card);
//   the card out is read anew from the state (as today's card is bound to
//   the tiles), so it names those left now.
// decided: the engine's arbitration reads the incoming change's `still`
//   (the whole judged change reaches arbitrate, as tst_OSDSystems passes
//   it).
// decided: `card` for a removal with nobody left reads "Stopped …" with
//   the change's `members` (the card out re-read as its capture stops,
//   today's preview case).

var opts = { "shows": ["camera", "micUse", "screenShare"] };

function cap(members) {
  return { "members": members };
}
function m(id, app) {
  return { "id": id, "app": app };
}
var none = cap([]);

function start(extra) {
  return Object.assign({ "camera": none, "micUse": none, "screenShare": none }, extra || {});
}

var rows = [
  {
    "name": "nothing capturing: the tiles unlit, never hidden",
    "options": opts,
    "steps": [
      { "at": 0, "state": start(),
        "tiles": { "camera": { "on": false, "hidden": false }, "micUse": { "on": false, "hidden": false }, "screenShare": { "on": false, "hidden": false } } }
    ]
  },
  {
    "name": "the first reading shows nothing, apps already capturing",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "camera": cap([m(61, "Firefox")]) }) }
    ]
  },
  // ---- Starting ----
  {
    "name": "an app starts using the camera: its card, the tile lit",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "camera": cap([m(61, "Firefox")]) },
        "expect": { "key": "camera", "show": "card", "kind": "add", "added": [61],
          "tile": { "icon": "videocam", "on": true, "notable": true, "hidden": false, "slash": false },
          "card": { "icon": "videocam", "title": "Firefox", "role": "Using the camera", "detail": "", "clickable": false },
          "host": "open" } }
    ]
  },
  {
    "name": "an app starts using the microphone",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "micUse": cap([m(70, "OBS")]) },
        "expect": { "key": "micUse", "show": "card", "tile": { "icon": "record_voice_over" }, "card": { "title": "OBS", "role": "Using the microphone" } } }
    ]
  },
  {
    "name": "an app starts sharing the screen",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "screenShare": cap([m(80, "Firefox")]) },
        "expect": { "key": "screenShare", "show": "card", "tile": { "icon": "screen_share", "on": true }, "card": { "title": "Firefox", "role": "Sharing the screen" } } }
    ]
  },
  {
    "name": "another stream starting while one runs: its card names every app",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "camera": cap([m(61, "Firefox")]) }) },
      { "at": 3000, "state": { "camera": cap([m(61, "Firefox"), m(74, "OBS")]) },
        "expect": { "key": "camera", "show": "card", "kind": "add", "added": [74], "card": { "title": "Firefox, OBS" } } }
    ]
  },
  {
    "name": "an app's name read after its stream starts isn't another app",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "camera": cap([m(61, "")]) },
        "expect": { "key": "camera", "show": "card" } },
      { "at": 3200, "state": { "camera": cap([m(61, "Firefox")]) } }
    ]
  },
  {
    "name": "one app's two streams: named once",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "screenShare": cap([m(80, "Vesktop"), m(81, "Vesktop")]) },
        "expect": { "key": "screenShare", "show": "card", "card": { "title": "Vesktop" } } }
    ]
  },
  {
    "name": "a kind not listed changes nothing",
    "options": { "shows": ["camera"] },
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "screenShare": cap([m(80, "Firefox")]), "micUse": cap([m(70, "OBS")]) } }
    ]
  },
  // ---- Stopping ----
  {
    "name": "the last one stopping: just the unlit icon",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "camera": cap([m(61, "Firefox")]) }) },
      { "at": 3000, "state": { "camera": cap([]) },
        "expect": { "key": "camera", "show": "tile", "kind": "remove", "still": false, "unexpected": true, "removed": [61], "left": [],
          "tile": { "icon": "videocam", "on": false, "notable": false, "hidden": false, "slash": false }, "host": "ring" } }
    ]
  },
  {
    "name": "still: one of several stopping, a card naming those left",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "micUse": cap([m(70, "OBS"), m(71, "Vesktop")]) }) },
      { "at": 3000, "state": { "micUse": cap([m(70, "OBS")]) },
        "expect": { "key": "micUse", "show": "card", "kind": "remove", "still": true, "removed": [71], "left": [70],
          "tile": { "on": true, "notable": true },
          "card": { "icon": "record_voice_over", "title": "OBS", "role": "Still using the microphone" },
          "host": "open" } }
    ]
  },
  {
    "name": "still: one of several stopping sharing the screen",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "screenShare": cap([m(80, "Firefox"), m(81, "OBS")]) }) },
      { "at": 3000, "state": { "screenShare": cap([m(81, "OBS")]) },
        "expect": { "key": "screenShare", "show": "card", "still": true, "card": { "title": "OBS", "role": "Still sharing the screen" } } }
    ]
  },
  {
    "name": "still: one app's second stream stopping, the app still there",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "camera": cap([m(61, "OBS"), m(62, "OBS")]) }) },
      { "at": 3000, "state": { "camera": cap([m(61, "OBS")]) },
        "expect": { "key": "camera", "show": "card", "still": true, "card": { "title": "OBS", "role": "Still using the camera" } } }
    ]
  },
  {
    "name": "still: a call app dropping its camera but keeping the microphone",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "camera": cap([m(61, "Vesktop")]), "micUse": cap([m(70, "Vesktop")]) }) },
      { "at": 3000, "state": { "camera": cap([]) },
        "expect": { "key": "camera", "show": "card", "kind": "remove", "still": true, "left": [],
          "tile": { "on": false },
          "card": { "icon": "record_voice_over", "title": "Vesktop", "role": "Still using the microphone" },
          "host": "open" } }
    ]
  },
  {
    "name": "still: a call app dropping its microphone but keeping the camera",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "camera": cap([m(61, "Vesktop")]), "micUse": cap([m(70, "Vesktop")]) }) },
      { "at": 3000, "state": { "micUse": cap([]) },
        "expect": { "key": "micUse", "show": "card", "still": true,
          "card": { "icon": "videocam", "title": "Vesktop", "role": "Still using the camera" } } }
    ]
  },
  {
    "name": "an app dropping its camera while another app has the microphone: just the icon",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "camera": cap([m(61, "Vesktop")]), "micUse": cap([m(70, "OBS")]) }) },
      { "at": 3000, "state": { "camera": cap([]) },
        "expect": { "key": "camera", "show": "tile", "still": false } }
    ]
  },
  {
    "name": "a call app dropping its camera, the microphone's kind not listed: just the icon",
    "options": { "shows": ["camera"] },
    "steps": [
      { "at": 0, "state": start({ "camera": cap([m(61, "Vesktop")]), "micUse": cap([m(70, "Vesktop")]) }) },
      { "at": 3000, "state": { "camera": cap([]) },
        "expect": { "key": "camera", "show": "tile" } }
    ]
  },
  {
    "name": "a call ending, both at once: two icons, no card",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "camera": cap([m(61, "Vesktop")]), "micUse": cap([m(70, "Vesktop")]) }) },
      { "at": 3000, "state": { "camera": cap([]), "micUse": cap([]) },
        "expect": [
          { "key": "camera", "show": "tile", "still": false, "host": "ring" },
          { "key": "micUse", "show": "tile", "still": false, "host": "ring" }
        ] }
    ]
  },
  {
    "name": "still: several stopping within the quiet window with some left: one card, naming those left now",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "micUse": cap([m(70, "OBS"), m(71, "Vesktop"), m(72, "Firefox")]) }) },
      { "at": 3000, "state": { "micUse": cap([m(70, "OBS"), m(72, "Firefox")]) },
        "expect": { "key": "micUse", "show": "card", "still": true, "card": { "title": "OBS, Firefox" }, "host": "open" } },
      { "at": 3500, "state": { "micUse": cap([m(70, "OBS")]) },
        "expect": { "key": "micUse", "show": "card", "still": true, "card": { "title": "OBS", "role": "Still using the microphone" }, "host": "keep" } }
    ]
  },
  {
    "name": "still: several stopping at once, some left: one card",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "micUse": cap([m(70, "OBS"), m(71, "Vesktop"), m(72, "Firefox")]) }) },
      { "at": 3000, "state": { "micUse": cap([m(70, "OBS")]) },
        "expect": { "key": "micUse", "show": "card", "still": true, "removed": [71, 72], "left": [70], "card": { "title": "OBS" }, "host": "open" } }
    ]
  },
  {
    "name": "still: a later one stopping past the window is its own card",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "micUse": cap([m(70, "OBS"), m(71, "Vesktop"), m(72, "Firefox")]) }) },
      { "at": 3000, "state": { "micUse": cap([m(70, "OBS"), m(72, "Firefox")]) },
        "expect": { "key": "micUse", "show": "card", "host": "open" } },
      { "at": 6000, "state": { "micUse": cap([m(70, "OBS")]) },
        "expect": { "key": "micUse", "show": "card", "still": true, "host": "replace" } }
    ]
  },
  {
    "name": "the last one stopping just after a still card: suppressed under it",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "micUse": cap([m(70, "OBS"), m(71, "Vesktop")]) }) },
      { "at": 3000, "state": { "micUse": cap([m(70, "OBS")]) },
        "expect": { "key": "micUse", "show": "card", "still": true, "host": "open" } },
      { "at": 3500, "state": { "micUse": cap([]) },
        "expect": { "key": "micUse", "show": "tile", "still": false, "host": "suppress" } }
    ]
  },
  // ---- Under its card ----
  {
    "name": "a picker's preview stopping under its card: suppressed, the card still naming the app",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "screenShare": cap([m(80, "Vesktop")]) },
        "expect": { "key": "screenShare", "show": "card", "card": { "title": "Vesktop", "role": "Sharing the screen" }, "host": "open" } },
      { "at": 3300, "state": { "screenShare": cap([]) },
        "expect": { "key": "screenShare", "show": "tile", "kind": "remove",
          "card": { "title": "Vesktop", "role": "Stopped sharing the screen" }, "host": "suppress" } }
    ]
  },
  {
    "name": "the camera's and the microphone's stopped cards name the last apps",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "camera": cap([m(61, "Vesktop")]), "micUse": cap([m(70, "OBS")]) }) },
      { "at": 3000, "state": { "camera": cap([]), "micUse": cap([]) },
        "expect": [
          { "key": "camera", "show": "tile", "card": { "title": "Vesktop", "role": "Stopped using the camera" } },
          { "key": "micUse", "show": "tile", "card": { "title": "OBS", "role": "Stopped using the microphone" } }
        ] }
    ]
  },
  {
    "name": "sharing again by another app: the apps sharing now, not the last ones",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "screenShare": cap([]) }) },
      { "at": 3000, "state": { "screenShare": cap([m(82, "Firefox")]) },
        "expect": { "key": "screenShare", "show": "card", "card": { "title": "Firefox", "role": "Sharing the screen" } } }
    ]
  },
  {
    "name": "the same app taking the camera then the microphone: one card saying both",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "camera": cap([m(61, "Vesktop")]) },
        "expect": { "key": "camera", "show": "card", "card": { "role": "Using the camera" }, "host": "open" } },
      { "at": 3400, "state": { "micUse": cap([m(70, "Vesktop")]) },
        "expect": { "key": "micUse", "show": "card", "card": { "role": "Using the camera and microphone" }, "host": "keep" } }
    ]
  },
  {
    "name": "the microphone then the camera: either order",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "micUse": cap([m(70, "Vesktop"), m(71, "OBS")]) },
        "expect": { "key": "micUse", "show": "card", "host": "open" } },
      { "at": 3400, "state": { "camera": cap([m(61, "Vesktop")]) },
        "expect": { "key": "camera", "show": "card", "card": { "role": "Using the camera and microphone" }, "host": "keep" } }
    ]
  },
  {
    "name": "both in one reading: one card (the first key's), the other kept",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "camera": cap([m(61, "Vesktop")]), "micUse": cap([m(70, "Vesktop")]) },
        "expect": [
          { "key": "camera", "show": "card", "card": { "role": "Using the camera and microphone" }, "host": "open" },
          { "key": "micUse", "show": "card", "host": "keep" }
        ] }
    ]
  },
  {
    "name": "another app's microphone just after a camera card: it replaces",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "camera": cap([m(61, "Vesktop")]) },
        "expect": { "key": "camera", "show": "card", "host": "open" } },
      { "at": 3400, "state": { "micUse": cap([m(70, "OBS")]) },
        "expect": { "key": "micUse", "show": "card", "card": { "role": "Using the microphone" }, "host": "replace" } }
    ]
  },
  {
    "name": "the same app's microphone past the quiet window: it replaces",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "camera": cap([m(61, "Vesktop")]) },
        "expect": { "key": "camera", "show": "card", "host": "open" } },
      { "at": 5000, "state": { "micUse": cap([m(70, "Vesktop")]) },
        "expect": { "key": "micUse", "show": "card", "host": "replace" } }
    ]
  },
  {
    "name": "the microphone's kind not listed: the camera card says the camera alone",
    "options": { "shows": ["camera"] },
    "steps": [
      { "at": 0, "state": start({ "micUse": cap([m(70, "Vesktop")]) }) },
      { "at": 3000, "state": { "camera": cap([m(61, "Vesktop")]) },
        "expect": { "key": "camera", "show": "card", "card": { "role": "Using the camera" } } }
    ]
  },
  {
    "name": "another capture's card just after: it replaces",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "state": { "camera": cap([m(61, "Firefox")]) },
        "expect": { "key": "camera", "show": "card", "host": "open" } },
      { "at": 3300, "state": { "screenShare": cap([m(80, "Firefox")]) },
        "expect": { "key": "screenShare", "show": "card", "host": "replace" } }
    ]
  },
  {
    "name": "a capture stopping beside another capture's card: beside it",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "screenShare": cap([m(80, "OBS")]) }) },
      { "at": 3000, "state": { "camera": cap([m(61, "Firefox")]) },
        "expect": { "key": "camera", "show": "card", "host": "open" } },
      { "at": 3300, "state": { "screenShare": cap([]) },
        "expect": { "key": "screenShare", "show": "tile", "host": "beside" } }
    ]
  },
  {
    "name": "a capture starting while unsettled still counts (anyone's)",
    "options": opts,
    "steps": [
      { "at": 0, "state": start() },
      { "at": 3000, "settled": false, "state": { "camera": cap([m(61, "Firefox")]) },
        "expect": { "key": "camera", "show": "card" } }
    ]
  },
  {
    "name": "an app's name changing alone changes nothing",
    "options": opts,
    "steps": [
      { "at": 0, "state": start({ "camera": cap([m(61, "Firefox")]) }) },
      { "at": 3000, "state": { "camera": cap([m(61, "Firefox Nightly")]) } }
    ]
  }
];
