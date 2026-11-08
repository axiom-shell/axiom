.pragma library
// Message's timelines: what `axiom message <icon> <text>`,
// ShellManager.confirm and ShellManager.refuse send, only ever its card (no
// tile): its icon, the text as the title, the detail as the faint line; a
// refusal's picture on the warning colour. It shows beside whatever else is
// out and gives way within the quiet window only to another card (Cross.js).
//
// State by key (MessageWatch, listening to ShellManager.osdMessage for this
// OSD's id):
//   message  { event ({ icon, text, detail, tone ("warning" for a refusal,
//            else "") }, or null), seq (counting each message, so the same
//            text twice shows twice) }
//
// decided: a message's text is shown as sent (the sender translates it;
//   a refusal's title and detail come from ShellManager.refuse's callers,
//   already translated).
// decided: the watcher has no first reading to skip: it starts at
//   `{ event: null, seq: 0 }`, so the first message counts.

function msg(icon, text, detail, tone, seq) {
  return { "event": { "icon": icon, "text": text, "detail": detail || "", "tone": tone || "" }, "seq": seq };
}
var empty = { "event": null, "seq": 0 };

var rows = [
  {
    "name": "a message: its card, its icon and text",
    "steps": [
      { "at": 0, "state": { "message": empty } },
      { "at": 3000, "state": { "message": msg("save", "Saved", "", "", 1) },
        "expect": { "key": "message", "show": "card", "kind": "event",
          "card": { "icon": "save", "title": "Saved", "role": "", "detail": "", "tone": "", "clickable": false, "image": "" },
          "host": "open" } }
    ]
  },
  {
    "name": "no icon: the chat bubble",
    "steps": [
      { "at": 0, "state": { "message": empty } },
      { "at": 3000, "state": { "message": msg("", "Saved", "", "", 1) },
        "expect": { "key": "message", "show": "card", "card": { "icon": "chat", "title": "Saved" } } }
    ]
  },
  {
    "name": "a refusal: its two lines, on the warning colour",
    "steps": [
      { "at": 0, "state": { "message": empty } },
      { "at": 3000, "state": { "message": msg("nightlight", "Night light", "Not available here", "warning", 1) },
        "expect": { "key": "message", "show": "card",
          "card": { "icon": "nightlight", "title": "Night light", "role": "", "detail": "Not available here", "tone": "warning" } } }
    ]
  },
  {
    "name": "the same text again: shown again",
    "steps": [
      { "at": 0, "state": { "message": empty } },
      { "at": 3000, "state": { "message": msg("save", "Saved", "", "", 1) },
        "expect": { "key": "message", "show": "card", "host": "open" } },
      { "at": 6000, "state": { "message": msg("save", "Saved", "", "", 2) },
        "expect": { "key": "message", "show": "card", "host": "replace" } }
    ]
  },
  {
    "name": "another message just after: it replaces",
    "steps": [
      { "at": 0, "state": { "message": empty } },
      { "at": 3000, "state": { "message": msg("save", "Saved", "", "", 1) },
        "expect": { "key": "message", "show": "card", "host": "open" } },
      { "at": 3300, "state": { "message": msg("event", "Added Lunch", "Tomorrow 12:00", "", 2) },
        "expect": { "key": "message", "show": "card", "card": { "title": "Added Lunch", "detail": "Tomorrow 12:00" }, "host": "replace" } }
    ]
  }
];
