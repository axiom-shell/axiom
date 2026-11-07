pragma Singleton
import QtQuick

// The OSD's judgement, for every system alike (surfaces/osd/systems/,
// docs/dev/features/osd.md › Engine): what one state changing to the next
// shows by a system's declared model and policies (judge), its tile and
// card filled out (tileOf, cardOf), which change gives way to which across
// systems (arbitrate), and where an event goes (opensCard, cardRoute).
// A definition (OSDSystem) is passed in; nothing here names a system.
QtObject {
  id: root

  // How long after a change its own knock-on changes (airplane mode
  // switching the radios, a headset taking the output then the input, a
  // new device's mute) don't take its place, in ms
  readonly property int quietWindow: 2000

  // `key`'s entry in a definition's `exposes` ({} for none)
  function entryOf(def, key) {
    return (def?.exposes ?? []).find(e => e.key === key) ?? {};
  }

  // A setting of `key`: its `exposes` entry's own, else the system's
  // (model, the policies, userWindow, …)
  function policy(def, key, name) {
    const own = root.entryOf(def, key)[name];
    return own !== undefined ? own : def?.[name];
  }

  // `key`'s part: "bar", "tile" or "card"
  function partOf(def, key) {
    return root.entryOf(def, key).part ?? "tile";
  }

  // The on-screen mark (ShellManager.onScreen's kind) a change of `key`
  // is judged by: its entry's `mark`, else the key
  function markOf(def, key) {
    return root.entryOf(def, key).mark ?? key;
  }

  // Whether a change `elapsed` ms after its mark (negative or missing:
  // never marked) is the pointer's, by `key`'s userWindow
  function byUser(def, key, elapsed) {
    const ms = Number(elapsed);
    return Number.isFinite(ms) && ms >= 0 && ms < root.policy(def, key, "userWindow");
  }

  // `key`'s tile from its state: { icon, label, tone, on, slash, notable,
  // hidden } and whatever else the definition's tile() adds; the icon
  // `exposes`' unless it gives one
  function tileOf(def, key, state) {
    const t = {
      "icon": root.entryOf(def, key).icon ?? "",
      "label": "",
      "tone": "",
      "on": false,
      "slash": false,
      "notable": false,
      "hidden": false
    };
    const own = def ? def.tile(key, state ?? {}) : null;
    return Object.assign(t, own ?? {});
  }

  // The card for a change: { icon (its tile's unless given), image,
  // title, role, detail, tone, clickable }, or null when the definition
  // has none for it. `state`: the system's, by key
  function cardOf(def, change, state) {
    const own = def ? def.card(change, state ?? {}) : null;
    if (!own)
      return null;
    return Object.assign({
      "icon": root.tileOf(def, change.key, (state ?? {})[change.key]).icon,
      "image": "",
      "title": "",
      "role": "",
      "detail": "",
      "tone": "",
      "clickable": false
    }, own);
  }

  function _empty(v) {
    return v === undefined || v === null || v === "" || v === false || (Array.isArray(v) && v.length === 0);
  }

  function _ids(s) {
    return (s?.members ?? []).map(m => m.id);
  }

  // Whether two states of a key are the same (nothing to judge): an
  // event's by the event itself and its `seq`, any other by value
  function same(model, before, after) {
    if (model === "event")
      return (before?.event ?? null) === (after?.event ?? null) && before?.seq === after?.seq;
    return JSON.stringify(before) === JSON.stringify(after);
  }

  // What each policy shows: "card", "tile" or nothing
  function _show(policyName) {
    return policyName === "card" ? "card" : policyName === "icon" ? "tile" : "";
  }

  // The tile's look changing with its value the same (a mute, Wi-Fi
  // turned off): what tells it from a name or a signal changing. `on`
  // and `slash` always count, and the fields `updateFields` lists (by
  // default its icon and label; Audio's leaves the icon out, which a
  // Bluetooth profile switch changes)
  function _looks(def, key, before, after) {
    const a = root.tileOf(def, key, before);
    const b = root.tileOf(def, key, after);
    const fields = ["on", "slash"].concat(root.policy(def, key, "updateFields") ?? []);
    return fields.some(field => JSON.stringify(a[field]) !== JSON.stringify(b[field]));
  }

  // The generic judgement of `key` (OSDEngine.judge without the
  // definition's own): [kind, show, extra]
  function _generic(def, key, before, after, c) {
    if (c.part === "bar")
      return ["level", "level",
        {}
      ];
    const pick = name => root._show(root.policy(def, key, name));
    if (c.model === "event")
      return after?.event ? ["event", pick("onAdd"),
        {}
      ] : null;
    if (c.model === "set") {
      const was = root._ids(before);
      const now = root._ids(after);
      const added = now.filter(id => !was.includes(id));
      const removed = was.filter(id => !now.includes(id));
      const extra = {
        "added": added,
        "removed": removed,
        "left": now
      };
      if (added.length > 0)
        return ["add", pick("onAdd"), extra];
      if (removed.length === 0)
        return null;
      return root._removal(def, key, c, now.length > 0, extra);
    }
    // scalar: the value's own change, or its tile's look (a mute); the
    // stronger of the two shows (Wi-Fi off loses its network too)
    const b = before?.value;
    const a = after?.value;
    let out = null;
    if (root._empty(b) && !root._empty(a))
      out = ["add", pick("onAdd"),
        {}
      ];
    else if (!root._empty(b) && root._empty(a))
      out = root._removal(def, key, c, false, {});
    else if (JSON.stringify(a) !== JSON.stringify(b))
      out = ["change", pick("onChange"),
        {}
      ];
    if (root._looks(def, key, before, after)) {
      const update = ["update", pick("onUpdate"),
        {}
      ];
      if (!out || root._rank(update[1]) > root._rank(out[1]))
        out = update;
    }
    return out;
  }

  function _rank(show) {
    return show === "card" ? 2 : show === "tile" ? 1 : 0;
  }

  // A departure: `left` some still there. onUnexpectedRemove for one not
  // made on screen; "still" a card while some are left, else the icon
  function _removal(def, key, c, left, extra) {
    const unexpected = c.byUser !== true;
    const own = root.policy(def, key, "onUnexpectedRemove");
    const name = unexpected && own ? own : root.policy(def, key, "onRemove");
    const show = name === "still" ? (left ? "card" : "tile") : root._show(name);
    return ["remove", show, Object.assign({
        "still": name === "still" && left,
        "unexpected": unexpected
      }, extra)];
  }

  // What `key` changing from `before` to `after` (its states) shows, by
  // the definition's model and policies: null for nothing, else { key,
  // part, model, kind ("add" | "remove" | "change" | "update" | "event" |
  // "level"), show ("card" | "tile" | "level"), card (show is "card"),
  // still, unexpected, alert (opens the OSD even after an on-screen mark:
  // only a definition's judge() sets it), added, removed, left (a set's
  // ids), at, byUser }. Never the first reading (`before` missing) nor
  // across a state that isn't `available` (false); then the definition's
  // judge() for an odd case (it reads ctx.settled itself); else, unless
  // the system counts `anyone`'s, nothing while the watcher calls it
  // unsettled. `ctx`: { at, byUser, settled, before, after (the whole
  // states) }
  function judge(def, key, before, after, ctx) {
    const c = Object.assign({
      "at": 0,
      "byUser": false,
      "settled": true
    }, ctx ?? {}, {
      "key": key,
      "part": root.partOf(def, key),
      "model": root.policy(def, key, "model")
    });
    if (root.same(c.model, before, after))
      return null;
    if (before === undefined || before === null)
      return null;
    if (before.available === false || after?.available === false)
      return null;
    const custom = def ? def.judge(before, after, c) : undefined;
    let out;
    if (custom !== undefined) {
      if (!custom)
        return null;
      out = [custom.kind ?? "change", custom.show ?? "", custom];
    } else {
      if (c.settled === false && root.policy(def, key, "anyone") !== true)
        return null;
      out = root._generic(def, key, before, after, c);
    }
    if (!out || !out[1])
      return null;
    return Object.assign({
      "still": false,
      "unexpected": false,
      "alert": false,
      "added": [],
      "removed": [],
      "left": []
    }, out[2], {
      "key": key,
      "part": c.part,
      "model": c.model,
      "kind": out[0],
      "show": out[1],
      "card": out[1] === "card",
      "at": c.at,
      "byUser": c.byUser
    });
  }

  // Whether `incoming` is a knock-on of `shown` (both { system, key,
  // part, card, tile }; `defs` the definitions by system) within the
  // quiet window: its system lists shown's in `knockOnOf`, shown's system
  // absorbs it, or (against a card) shown's system calls it the same
  // change
  function _knockOn(shown, incoming, defs) {
    const own = defs?.[shown.system];
    const other = defs?.[incoming.system];
    if ((other?.knockOnOf ?? []).includes(shown.system))
      return true;
    if (shown.system !== incoming.system)
      return own ? own.absorbs(shown, incoming) === true : false;
    return shown.card === true && own ? own.sameChange(shown, incoming) === true : false;
  }

  // What a change does to what's shown, `elapsed` ms after `shown` came.
  // Both are whole judged changes (judge()'s: key, part, kind, card
  // (bool), still, unexpected, alert, added, removed, left, …) with their
  // `system` and `tile` (that key's tile now); `defs` the definitions by
  // system. Their sameChange() and absorbs() read any of it (Privacy's
  // `still`). Against a card out (`shown.card`): a card
  // "replace"s it or "keep"s it (the same change: the first card says
  // it); a change without one "retract"s it (its own tile turned off,
  // with retractsCardWhenOff: the card would say what no longer holds; at
  // any age), is "suppress"ed (its knock-on) or shows "beside" it.
  // Against the ringed tile (`shown.card` false; a tile change only):
  // "replace" (it takes the ring) or "keep" (its knock-on: nothing shows)
  function arbitrate(shown, incoming, elapsed, defs) {
    const def = defs?.[shown.system];
    if (shown.card === true && incoming.card !== true && incoming.system === shown.system && incoming.key === shown.key && def?.retractsCardWhenOff === true && incoming.tile?.on !== true)
      return "retract";
    const knockOn = elapsed < root.quietWindow && root._knockOn(shown, incoming, defs);
    if (shown.card !== true)
      return knockOn ? "keep" : "replace";
    if (incoming.card === true)
      return knockOn ? "keep" : "replace";
    return knockOn ? "suppress" : "beside";
  }

  // Whether a change opens a shut OSD: not when its system's item is
  // `quiet` or its key's `exposes` entry says `opens: false` (an Audio
  // bar's or Brightness's showOsd off); else unless made on screen
  // (`byUser`), which `onScreenChanges` (OSD.onScreenChanges) or the
  // change's own `alert` (a headset's battery low) overrides. A change
  // that doesn't open it still shows on an open one. `item`: the
  // system's item ({ quiet, … }; its definition's `options`)
  function opens(item, def, change, onScreenChanges) {
    if (item?.quiet === true || root.entryOf(def, change.key).opens === false)
      return false;
    return change.alert === true || change.byUser !== true || onScreenChanges === true;
  }

  // `osd`'s item of a system (its `systems` entry), or null
  function itemOf(osd, type) {
    return (osd?.systems ?? []).find(item => item.type === type) ?? null;
  }

  // What a change shows on `osd` (an OSD entry: { cardsEnabled, systems
  // }): its own show, a card shown as its tile where the OSD's cards or
  // the item's are off (nothing for a key with no tile, or the item's
  // tiles off), "" for nothing
  function shownAs(osd, change, hasTile) {
    const item = root.itemOf(osd, change.system ?? "") ?? {};
    const tile = hasTile === true && item.tile !== false ? "tile" : "";
    if (change.show === "card")
      return osd?.cardsEnabled === true && item.card !== false ? "card" : tile;
    if (change.show === "tile")
      return tile;
    return change.show ?? "";
  }

  // Whether `osd` shows `type`'s change as its card the moment it comes:
  // enabled, its cards on, and the system listed with its cards on and
  // not quiet (a quiet one never opens it). Where none does, an event is
  // a notification instead (cardRoute)
  function opensCard(osd, type) {
    if (!osd || !osd.enabled || !osd.cardsEnabled)
      return false;
    const item = root.itemOf(osd, type);
    return item !== null && item.card !== false && item.quiet !== true;
  }

  // Where an event of `type` goes (a drive, the battery, a monitor, a
  // screenshot, a message): "osd" when an OSD of `osds` opens its card
  // (opensCard), else "notification" with `notify` (its section's
  // switch), else "" (nowhere)
  function cardRoute(osds, type, notify) {
    if ((osds ?? []).some(osd => root.opensCard(osd, type)))
      return "osd";
    return notify ? "notification" : "";
  }
}
