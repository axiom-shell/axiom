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
  // label, group }, `opens: false` for one whose change never opens a shut
  // OSD (an Audio bar's showOsd off), `design` (its view of its own, a
  // file of its design/ folder: Paths.osdDesignUrl), `roles` (a set's
  // card made by the engine: { add, still, stopped }, OSDEngine.cardOf),
  // and, overriding the system's own for this key, any of `model`, the
  // policies, `updateFields`, `mark`, `userWindow`, `action`, `call`
  property var exposes: []

  // How its state is told apart: "scalar" ({ value, … }: added as it
  // turns non-empty, removed as it turns empty, changed between two),
  // "set" ({ members: [{ id, … }] }: added, removed by id) or "event"
  // ({ event, seq }: each new one)
  property string model: "scalar"

  // What a change shows: "card" | "icon" | "none" (onRemove and
  // onUnexpectedRemove also "still": a card while some are left, the
  // icon for the last; and "last": the icon while some are left, a card
  // for the last: a VPN dropping with none left up).
  // onUpdate: the value the same but its tile's look changed (a mute)
  property string onAdd: "icon"
  property string onChange: "icon"
  property string onUpdate: "icon"
  property string onRemove: "icon"
  // A removal nobody made on screen: "" for onRemove's
  property string onUnexpectedRemove: ""
  // A scalar whose state also carries events ({ event, seq }, besides
  // its `value`): a new `seq` with an event is an "event" change shown by
  // `onEvent`, before the value's own (Bluetooth: the radio and its
  // devices' events on one key, so its card folds back as the radio
  // turns off and the radio coming on under it is its own knock-on)
  property bool carriesEvents: false
  property string onEvent: "card"
  // The event kinds (an event's `kind`) that are alerts: they open the
  // OSD even just after an on-screen mark (a Bluetooth device's battery
  // "low", "critical"; OSDEngine.opens)
  property var alertKinds: []
  // A set judged by one member field: { field, on, off } (a VPN's
  // { field: "state", on: "on", off: "off" }). The members whose field is
  // `on` are the set; only one known before (settled at `on` or `off`)
  // and still there counts, added as it turns `on`, removed as it turns
  // `off`. Any other value is a member in transit (connecting), judged as
  // it last settled (OSDEngine.remember keeps that reading); one
  // appearing (a service's first answer) or going isn't a change. null:
  // the set is every member, by id
  property var memberState: null
  // Counts changes the watcher's `settled` calls unsettled (a VPN
  // dropping, an app starting a capture): every change after the start
  property bool anyone: false
  // How long after an on-screen mark (ShellManager.onScreen) a change is
  // the pointer's, in ms
  property int userWindow: 2000
  // Besides `on` and `slash`, the tile fields whose change with the value
  // the same is an update (onUpdate): Audio's leaves the icon out, which
  // a Bluetooth profile switch changes
  property var updateFields: ["icon", "label"]
  // Its card folds back when its own tile turns off without a card (it
  // would say what no longer holds: a VPN, Wi-Fi, the charger)
  property bool retractsCardWhenOff: false
  // Its cards are the lowest: one never replaces another system's card
  // out, at any age (Now playing's pause, as a device switch pauses the
  // music, doesn't cover the device's card)
  property bool yieldsCard: false
  // Systems whose change, within OSDEngine.quietWindow, makes this one's
  // its knock-on (Wi-Fi after airplane mode)
  property var knockOnOf: []

  // The change kinds ("add", "remove", "change", "update", "event",
  // "level") that count only while the watcher calls them settled; null
  // for every kind. Audio's ["update", "level"]: a device switch counts
  // as its new node binds, a mute or a level only once it has. `anyone`
  // makes it none
  property var settledKinds: null
  // State fields whose change makes a change of the key nobody's (a
  // reload, not a switch: KeyboardLayout's list of sources; Audio's
  // stream bars' set of streams): nothing shows
  property var resetBy: []
  // A change just after an outside event the state timestamps isn't the
  // user's: { after: field, ms, unlessAfter: field } (KeyboardLayout's
  // focus-follow: { after: "focusedAt", ms: 1000, unlessAfter:
  // "switchedAt" }), each field a time in ms (Date.now(); 0 for never),
  // compared with the change's `at`; null for none
  property var ignoreWithin: null
  // A change counts only just after the user's own set the state
  // timestamps: { after: field, ms }, the field a time in ms (Date.now();
  // 0 for never) compared with the change's `at` (Brightness: { after:
  // "setAt", ms: 500 }, so a refresh or idle dimming shows nothing, and a
  // set at its limit, the level unchanged, still does as its time moves
  // on). Such a key gates itself, so its watcher's start settle doesn't
  // hold it (showsWhileSettling); null for none
  property var countsWithin: null
  // A scalar's value going empty is a gap, not a removal, and the value
  // before it is the one the next is judged against (Audio: a Bluetooth
  // headset's profile switch replaces its node, often with none between;
  // the device it comes back as isn't a switch)
  property bool keepThroughGap: false
  // What changes without a card its card out takes in within the quiet
  // window (sameChange's default): "key", its own key's (a capture
  // stopping as it starts); "system", any of its keys' (a new device's
  // mute, its level arriving late)
  property string takesIn: "key"
  // A set's member field naming who it belongs to ("app"): what a set's
  // card (an entry's `roles`) names, and what keys in one of `groups`
  // match by. A scalar is matched by its value
  property string ownerField: ""
  // Keys whose changes of one owner make one card: [{ keys, role }]. A
  // card of one of them coming within the quiet window of another's card
  // out, an owner in common, is kept (the card out says both); a card of
  // an arrival ("add", "change") with an owner in common with another
  // listed key of the group says the group's `role` ("Output and input",
  // "Using the camera and microphone"); a set's last member of one
  // owner leaving while the owner stays on another listed key of the
  // group is a "still" card under onRemove "still" ("Vesktop / Still
  // using the microphone"; the change's `kept` names that key)
  property var groups: []

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
  // `shown` (this system's card out): its knock-on, kept or suppressed
  // rather than taking its place (both { system, key, part, card, tile }).
  // By default a change without a card of what `takesIn` says; the engine
  // adds `groups`' and a "still" card of the same key
  function sameChange(shown, incoming) {
    return incoming.card !== true && (root.takesIn === "system" || shown.key === incoming.key);
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
