.pragma library
// Screenshot's timelines: a screenshot taken (not one opened in the
// annotator, nor one taken for a caller), only ever its card (no tile):
// the picture in place of the icon, what happened, Copied to the clipboard
// and the folder. Its card takes a click (the watcher's activate:
// ScreenshotManager.open opens the picture).
//
// State by key (ScreenshotWatch):
//   screenshot  { event (ScreenshotManager.lastShot: { path, title (what
//               happened, translated by the service), folder (where it was
//               saved, shortened; "" for copy only), serial }, or null), seq }
//
// decided: the card's `title` is the event's own `title`, already
//   translated by ScreenshotManager (as today): the view must not translate
//   it again.

function shot(path, title, folder, seq) {
  return { "event": { "path": path, "title": title, "folder": folder, "serial": seq }, "seq": seq };
}

var rows = [
  {
    "name": "the first reading shows nothing",
    "steps": [
      { "at": 0, "state": { "screenshot": shot("/home/u/Pictures/Screenshots/a.png", "Screenshot saved", "~/Pictures/Screenshots", 1) } }
    ]
  },
  {
    "name": "taken: its card, the picture, the folder, and a click opens it",
    "steps": [
      { "at": 0, "state": { "screenshot": { "event": null, "seq": 0 } } },
      { "at": 3000, "state": { "screenshot": shot("/home/u/Pictures/Screenshots/a.png", "Screenshot saved", "~/Pictures/Screenshots", 1) },
        "expect": { "key": "screenshot", "show": "card", "kind": "event",
          "card": { "icon": "screenshot_monitor", "image": "file:///home/u/Pictures/Screenshots/a.png", "title": "Screenshot saved", "role": "Copied to the clipboard", "detail": "~/Pictures/Screenshots", "tone": "", "clickable": true },
          "host": "open" } }
    ]
  },
  {
    "name": "copied only: no folder",
    "steps": [
      { "at": 0, "state": { "screenshot": { "event": null, "seq": 0 } } },
      { "at": 3000, "state": { "screenshot": shot("/tmp/axiom-shot.png", "Screenshot copied", "", 1) },
        "expect": { "key": "screenshot", "show": "card", "card": { "title": "Screenshot copied", "detail": "" } } }
    ]
  },
  {
    "name": "another just after: its card replaces",
    "steps": [
      { "at": 0, "state": { "screenshot": { "event": null, "seq": 0 } } },
      { "at": 3000, "state": { "screenshot": shot("/home/u/Pictures/Screenshots/a.png", "Screenshot saved", "~/Pictures/Screenshots", 1) },
        "expect": { "key": "screenshot", "show": "card", "host": "open" } },
      { "at": 3800, "state": { "screenshot": shot("/home/u/Pictures/Screenshots/b.png", "Screenshot saved", "~/Pictures/Screenshots", 2) },
        "expect": { "key": "screenshot", "show": "card", "card": { "image": "file:///home/u/Pictures/Screenshots/b.png" }, "host": "replace" } }
    ]
  },
  {
    "name": "the event cleared: nothing",
    "steps": [
      { "at": 0, "state": { "screenshot": shot("/home/u/a.png", "Screenshot saved", "~", 1) } },
      { "at": 3000, "state": { "screenshot": { "event": null, "seq": 1 } } }
    ]
  }
];
