pragma ComponentBehavior: Bound
import QtQuick

// The base of an OSD system's definition (systems/<Name>/<Name>.qml): what
// it shows (its bars, tiles and cards), how its state is modelled and
// which change shows what. Pure: a definition imports only QtQuick,
// qs.components.methods and this folder, so the unit tests load it, and
// OSDEngine does the judging (docs/dev/features/osd.md › Engine).
QtObject {
  id: root

  // The system's name (its folder's), set by whoever loads it
  property string type: ""
  // Its item in the OSD's `systems` list: { type, tile, card, quiet, …its
  // own settings }
  property var options: ({})

  // What it shows, each { key, part: "bar" | "tile" | "card", icon,
  // label, group } and, overriding the system's own for this key, any of
  // `model`, the policies, `mark`, `userWindow`, `action`, `call`
  property var exposes: []

  // How its state is told apart: "scalar" ({ value, … }: added as it
  // turns non-empty, removed as it turns empty, changed between two),
  // "set" ({ members: [{ id, … }] }: added, removed by id) or "event"
  // ({ event, seq }: each new one)
  property string model: "scalar"

  // What a change shows: "card" | "icon" | "none" (onRemove also
  // "still": a card while some are left, the icon for the last).
  // onUpdate: the value the same but its tile's look changed (a mute)
  property string onAdd: "icon"
  property string onChange: "icon"
  property string onUpdate: "icon"
  property string onRemove: "icon"
  // A removal nobody made on screen: "" for onRemove's
  property string onUnexpectedRemove: ""
  // Counts changes the watcher's `settled` calls unsettled (a VPN
  // dropping, an app starting a capture): every change after the start
  property bool anyone: false
  // How long after an on-screen mark (ShellManager.onScreen) a change is
  // the pointer's, in ms
  property int userWindow: 2000
  // Its card folds back when its own tile turns off without a card (it
  // would say what no longer holds: a VPN, Wi-Fi, the charger)
  property bool retractsCardWhenOff: false
  // Systems whose change, within OSDEngine.quietWindow, makes this one's
  // its knock-on (Wi-Fi after airplane mode)
  property var knockOnOf: []

  // Its tile for `key` from that key's state: any of { icon, label,
  // tone, on, slash, notable, hidden, … } (OSDEngine.tileOf fills the
  // rest, the icon from `exposes`)
  function tile(key, state) {
    return {};
  }

  // Its card for a change (OSDEngine.judge's), from the whole state (by
  // key): any of { icon, image, title, role, detail, tone, clickable },
  // English (the view translates; declare its strings in a comment as I18n.tr calls),
  // or null for none
  function card(change, state) {
    return null;
  }

  // An odd case's own judgement of one key's change: undefined to leave
  // it to OSDEngine, null for nothing, else { kind, show, … } (filled
  // like OSDEngine.judge's). `ctx`: { key, part, model, at, byUser,
  // settled, before, after (the whole states) }
  function judge(before, after, ctx) {
    return undefined;
  }

  // Whether `incoming` (a change of this system) is the same change as
  // `shown` (this system's card out): kept beside it rather than taking
  // its place (both { system, key, part, card, tile })
  function sameChange(shown, incoming) {
    return incoming.card !== true && shown.key === incoming.key;
  }

  // Whether `own` (this system's card or ring) takes in `other`, another
  // system's change: that one's own knock-on
  function absorbs(own, other) {
    return false;
  }

  // The action a click on `key`'s tile runs, { id, call } for
  // ActionsManager.run, or null: `exposes`' `action` (and `call`,
  // "toggle" unless given) by default
  function actionOf(key, state) {
    const entry = root.exposes.find(e => e.key === key);
    return entry?.action ? {
      "id": entry.action,
      "call": entry.call ?? "toggle"
    } : null;
  }

  // A click on a clickable card: an ActionsManager id to run, or "" to
  // hand it to the watcher's activate(change)
  function activate(change) {
    return "";
  }
}
