.pragma library
// KeyboardLayout's timelines: the input source in use, by its label (a
// layout's code, an input method's own あ) and its kind's icon; hidden with
// one source, unusual past the first. A changed list is a config reload; a
// change just after the focused window changed is that window's own input
// method coming back (fcitx5, shareState off), unless axiom switched then.
//
// State by key (KeyboardLayoutWatch):
//   keyboardLayout  { ids (the input sources'), value (the one in use, ""
//                   for none), label (its own short label), icon (its
//                   kind's: "keyboard", "translate"), focusedAt (when the
//                   focused window last changed, CompositorManager
//                   .activeWindowId; ms, 0 for never), switchedAt
//                   (InputSourceManager.switchedAt; ms, 0 for never) }
//
// decided: focus-follow reads timestamps (`focusedAt`, `switchedAt`)
//   against the judgement's `ctx.at` rather than ages the watcher works out
//   (the old focusAge / switchAge): the same clock (Date.now()), and the
//   state then doesn't change on every check. The window stays
//   OSDItems.focusFollowMs (1000 ms): within it is `at - focusedAt < 1000`.
//   Declared, as the rest (no judge()): `ignoreWithin: { after:
//   "focusedAt", ms: 1000, unlessAfter: "switchedAt" }`, `resetBy: ["ids"]`
//   (a reload), onAdd / onRemove "none" (the list appearing, none
//   current), `updateFields: []` (the label read again).
// decided: the tile's `on` is true always (as today): the label tells it.

var two = ["us", "mozc"];

function src(ids, value, label, icon, focusedAt, switchedAt) {
  return { "ids": ids, "value": value, "label": label, "icon": icon || "", "focusedAt": focusedAt || 0, "switchedAt": switchedAt || 0 };
}

var rows = [
  {
    "name": "the first reading shows nothing",
    "steps": [
      { "at": 0, "state": { "keyboardLayout": src(["us", "de"], "de", "DE") } }
    ]
  },
  {
    "name": "switched past the first: its label, unusual",
    "steps": [
      { "at": 0, "state": { "keyboardLayout": src(["us", "de"], "us", "US") } },
      { "at": 3000, "state": { "keyboardLayout": src(["us", "de"], "de", "DE") },
        "expect": { "key": "keyboardLayout", "show": "tile", "kind": "change",
          "tile": { "icon": "keyboard", "label": "DE", "on": true, "notable": true, "hidden": false, "slash": false },
          "card": null, "host": "ring" } }
    ]
  },
  {
    "name": "back to the first: ordinary",
    "steps": [
      { "at": 0, "state": { "keyboardLayout": src(["us", "de"], "de", "DE") } },
      { "at": 3000, "state": { "keyboardLayout": src(["us", "de"], "us", "US") },
        "expect": { "key": "keyboardLayout", "show": "tile", "tile": { "label": "US", "notable": false } } }
    ]
  },
  {
    "name": "an input method's switch: its own label and its kind's icon",
    "steps": [
      { "at": 0, "state": { "keyboardLayout": src(two, "us", "US", "keyboard") } },
      { "at": 3000, "state": { "keyboardLayout": src(two, "mozc", "あ", "translate") },
        "expect": { "key": "keyboardLayout", "show": "tile", "tile": { "label": "あ", "icon": "translate", "notable": true } } }
    ]
  },
  {
    "name": "from the KeyboardLayout widget: still shown, the user's",
    "steps": [
      { "at": 0, "state": { "keyboardLayout": src(["us", "de"], "us", "US") } },
      { "at": 3000, "byUser": true, "state": { "keyboardLayout": src(["us", "de"], "de", "DE") },
        "expect": { "key": "keyboardLayout", "show": "tile", "byUser": true } }
    ]
  },
  {
    "name": "a new list of sources is a config reload, not a switch",
    "steps": [
      { "at": 0, "state": { "keyboardLayout": src(two, "us", "US") } },
      { "at": 3000, "state": { "keyboardLayout": src(["us", "fr"], "fr", "FR") } }
    ]
  },
  {
    "name": "the list appearing (none to two) isn't a switch",
    "steps": [
      { "at": 0, "state": { "keyboardLayout": src([], "", "") } },
      { "at": 3000, "state": { "keyboardLayout": src(two, "mozc", "あ") } }
    ]
  },
  {
    "name": "one source never shows",
    "steps": [
      { "at": 0, "state": { "keyboardLayout": src(["us"], "us", "US") } },
      { "at": 3000, "state": { "keyboardLayout": src(["us"], "us", "US", "keyboard", 2500) } }
    ]
  },
  {
    "name": "none current: nothing",
    "steps": [
      { "at": 0, "state": { "keyboardLayout": src(two, "us", "US") } },
      { "at": 3000, "state": { "keyboardLayout": src(two, "", "") } }
    ]
  },
  {
    "name": "the label read again (the same source): nothing",
    "steps": [
      { "at": 0, "state": { "keyboardLayout": src(two, "us", "") } },
      { "at": 3000, "state": { "keyboardLayout": src(two, "us", "US") } }
    ]
  },
  {
    "name": "focus-follow: the focused window's own input method coming back shows nothing",
    "steps": [
      { "at": 0, "state": { "keyboardLayout": src(two, "us", "US") } },
      { "at": 2880, "state": { "keyboardLayout": src(two, "us", "US", "", 2880) } },
      { "at": 3000, "state": { "keyboardLayout": src(two, "mozc", "あ", "translate", 2880) } }
    ]
  },
  {
    "name": "focus-follow: axiom switched as the focus changed, so it shows",
    "steps": [
      { "at": 0, "state": { "keyboardLayout": src(two, "us", "US") } },
      { "at": 3000, "state": { "keyboardLayout": src(two, "mozc", "あ", "translate", 2880, 2960) },
        "expect": { "key": "keyboardLayout", "show": "tile" } }
    ]
  },
  {
    "name": "focus-follow: an old switch of axiom's doesn't count",
    "steps": [
      { "at": 0, "state": { "keyboardLayout": src(two, "us", "US") } },
      { "at": 8000, "state": { "keyboardLayout": src(two, "mozc", "あ", "translate", 8000, 3000) } }
    ]
  },
  {
    "name": "focus-follow: a focus change a full window before is past it",
    "steps": [
      { "at": 0, "state": { "keyboardLayout": src(two, "us", "US") } },
      { "at": 3000, "state": { "keyboardLayout": src(two, "mozc", "あ", "translate", 2000) },
        "expect": { "key": "keyboardLayout", "show": "tile" } }
    ]
  },
  {
    "name": "focus-follow: no focus change at all, it shows",
    "steps": [
      { "at": 0, "state": { "keyboardLayout": src(two, "us", "US") } },
      { "at": 3000, "state": { "keyboardLayout": src(two, "mozc", "あ", "translate", 0, 0) },
        "expect": { "key": "keyboardLayout", "show": "tile" } }
    ]
  },
  {
    "name": "focus changing alone changes nothing",
    "steps": [
      { "at": 0, "state": { "keyboardLayout": src(two, "us", "US") } },
      { "at": 3000, "state": { "keyboardLayout": src(two, "us", "US", "", 3000) } }
    ]
  },
  {
    "name": "two switches in a row: each takes the ring",
    "steps": [
      { "at": 0, "state": { "keyboardLayout": src(["us", "de", "fr"], "us", "US") } },
      { "at": 3000, "state": { "keyboardLayout": src(["us", "de", "fr"], "de", "DE") },
        "expect": { "show": "tile", "host": "ring" } },
      { "at": 3400, "state": { "keyboardLayout": src(["us", "de", "fr"], "fr", "FR") },
        "expect": { "show": "tile", "tile": { "label": "FR" }, "host": "ring" } }
    ]
  }
];
