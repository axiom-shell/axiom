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

  // The tile a change of `key` is weighed with (arbitrate's `tile`):
  // its own for a tile or a card key; a bar's its mark's (Audio's System
  // volume the output device's, which carries its Bluetooth address), so
  // another system's absorbs() can tell whose level it is; null for a
  // bar marked by itself (Brightness). `state`: the system's, by key
  function contextTile(def, key, state) {
    if (root.partOf(def, key) !== "bar")
      return root.tileOf(def, key, state?.[key]);
    const mark = root.markOf(def, key);
    return mark !== key && state?.[mark] !== undefined ? root.tileOf(def, mark, state[mark]) : null;
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
    Object.assign(t, own ?? {});
    // A key of one of `groups`: who holds it, what the group matches by
    if (root.groupOf(def, key))
      t.owners = root.ownersOf(def, key, state);
    return t;
  }

  // The group (`groups`' { keys, role }) `key` is in, or null
  function groupOf(def, key) {
    return (def?.groups ?? []).find(g => (g.keys ?? []).includes(key)) ?? null;
  }

  // Who holds `key` in `state` (its state), once each: a set's members'
  // `ownerField` (their ids without one), a scalar's value ([] empty)
  function ownersOf(def, key, state) {
    if (root.policy(def, key, "model") === "set")
      return root._owners(def, state?.members);
    const v = state?.value;
    return root._empty(v) ? [] : [v];
  }

  function _owners(def, members) {
    const field = def?.ownerField ?? "";
    return [...new Set((members ?? []).map(m => field ? m[field] : m.id))];
  }

  // The other listed keys of `key`'s group holding an owner of `owners`
  function _partners(def, key, owners, state) {
    const group = root.groupOf(def, key);
    if (!group)
      return [];
    return group.keys.filter(other => other !== key && root.entryOf(def, other).key === other && root.ownersOf(def, other, state?.[other]).some(o => owners.includes(o)));
  }

  // The card for a change: { icon (its tile's unless given), image,
  // title, role, detail, tone, clickable }, or null when the definition
  // has none for it. `state`: the system's, by key
  function cardOf(def, change, state) {
    const s = state ?? {};
    const own = !def ? null : root.entryOf(def, change.key).roles ? root._setCard(def, change, s) : def.card(change, s);
    if (!own)
      return null;
    const out = Object.assign({
      "icon": root.tileOf(def, change.key, s[change.key]).icon,
      "image": "",
      "title": "",
      "role": "",
      "detail": "",
      "tone": "",
      "clickable": false
    }, own);
    // An arrival held by an owner another key of its group holds too:
    // one card says both
    if ((change.kind === "add" || change.kind === "change") && change.still !== true) {
      const owners = root.ownersOf(def, change.key, s[change.key]);
      if (root._partners(def, change.key, owners, s).length > 0)
        out.role = root.groupOf(def, change.key).role ?? out.role;
    }
    return out;
  }

  // A set's card from its entry's `roles` ({ add, still, stopped }),
  // re-read from the state now: the owners there now (`still` for a
  // departure with some left, `add` else); with none left, those the
  // change saw (its `members`: the card's memory) with `stopped`; a
  // group's "still" card (`kept`) names the owners gone from this key
  // still on the kept one, with that key's icon and `still` role
  function _setCard(def, change, state) {
    const key = change.key;
    const roles = root.entryOf(def, key).roles;
    const now = root.ownersOf(def, key, state[key]);
    const was = root._owners(def, change.members);
    if (change.kept) {
      const kept = root.ownersOf(def, change.kept, state[change.kept]);
      const names = was.filter(o => kept.includes(o));
      if (names.length > 0)
        return {
          "icon": root.tileOf(def, change.kept, state[change.kept]).icon,
          "title": names.join(", "),
          "role": root.entryOf(def, change.kept).roles?.still ?? ""
        };
    }
    if (now.length > 0)
      return {
        "title": now.join(", "),
        "role": change.still === true ? roles.still : roles.add
      };
    return {
      "title": was.join(", "),
      "role": roles.stopped
    };
  }

  function _empty(v) {
    return v === undefined || v === null || v === "" || v === false || (Array.isArray(v) && v.length === 0);
  }

  function _ids(s) {
    return (s?.members ?? []).map(m => m.id);
  }

  // A memberState set's members as they last settled: one in transit
  // (its field neither `on` nor `off`) read as `prior` had it, left out
  // if it never settled there
  function _settledMembers(ms, prior, members) {
    const out = [];
    for (const m of members ?? []) {
      const v = m[ms.field];
      if (v === ms.on || v === ms.off) {
        out.push(m);
        continue;
      }
      const p = (prior ?? []).find(x => x.id === m.id);
      if (p)
        out.push(p);
    }
    return out;
  }

  // The ids a set is judged by, before and after: every member's, or
  // with `memberState` those `on` of the members known before and still
  // there (`left`: every one `on` after)
  function _memberSets(def, key, before, after) {
    const ms = root.policy(def, key, "memberState");
    if (!ms) {
      const now = root._ids(after);
      return {
        "was": root._ids(before),
        "now": now,
        "left": now
      };
    }
    const prior = before?.members ?? [];
    const settled = root._settledMembers(ms, prior, after?.members);
    const up = list => list.filter(m => m[ms.field] === ms.on).map(m => m.id);
    const priorIds = prior.map(m => m.id);
    const settledIds = settled.map(m => m.id);
    return {
      "was": up(prior).filter(id => settledIds.includes(id)),
      "now": up(settled).filter(id => priorIds.includes(id)),
      "left": up(settled)
    };
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

  // Whether a change of `kind` counts only while settled: every kind
  // unless `settledKinds` lists some, none with `anyone`
  function _needsSettled(def, key, kind) {
    if (root.policy(def, key, "anyone") === true)
      return false;
    const kinds = root.policy(def, key, "settledKinds");
    return !Array.isArray(kinds) || kinds.includes(kind);
  }

  // Whether `ms` (a timestamp; 0 or less: never) is within `within` ms
  // before `at`
  function _since(ms, at, within) {
    const t = Number(ms);
    return Number.isFinite(t) && t > 0 && at - t >= 0 && at - t < within;
  }

  // Why the declarations say a change is nobody's: a field of `resetBy`
  // changed with it (a reload), or it came within `ignoreWithin` of an
  // outside event (and not of the user's own); else false
  function _ignored(def, key, before, after, c) {
    const fields = root.policy(def, key, "resetBy") ?? [];
    if (fields.some(f => JSON.stringify(before?.[f]) !== JSON.stringify(after?.[f])))
      return true;
    // countsWithin: only just after the user's own set
    const own = root.policy(def, key, "countsWithin");
    if (own && !root._since(after?.[own.after], c.at, own.ms))
      return true;
    const w = root.policy(def, key, "ignoreWithin");
    return !!w && root._since(after?.[w.after], c.at, w.ms) && !(w.unlessAfter && root._since(after?.[w.unlessAfter], c.at, w.ms));
  }

  // The state a watcher judges the next one against, by key: `after`,
  // but a `keepThroughGap` scalar going empty keeps the value it had
  // (the device a headset comes back as after a profile switch isn't a
  // switch)
  function remember(def, before, after) {
    const out = Object.assign({}, after ?? {});
    for (const e of def?.exposes ?? []) {
      const was = before?.[e.key];
      const now = out[e.key];
      // A memberState set: a member in transit kept as it last settled
      const ms = root.policy(def, e.key, "memberState");
      if (now && ms && root.policy(def, e.key, "model") === "set")
        out[e.key] = Object.assign({}, now, {
          "members": root._settledMembers(ms, was?.members, now.members)
        });
      if (now && root.policy(def, e.key, "keepThroughGap") === true && root.policy(def, e.key, "model") === "scalar" && root._empty(now.value) && was && !root._empty(was.value))
        out[e.key] = Object.assign({}, now, {
          "value": was.value
        });
    }
    return out;
  }

  // The generic judgement of `key` (OSDEngine.judge without the
  // definition's own): [kind, show, extra]
  function _generic(def, key, before, after, c) {
    if (root._ignored(def, key, before, after, c))
      return null;
    // Each candidate a kind needing its watcher settled is dropped while
    // it isn't
    const counts = kind => c.settled !== false || !root._needsSettled(def, key, kind);
    if (c.part === "bar")
      return counts("level") ? ["level", "level",
        {}
      ] : null;
    const pick = name => root._show(root.policy(def, key, name));
    // An event is new by its `seq` where the state counts them (the same
    // event read again with the rest of the state, a drive's count
    // changing, isn't one)
    if (c.model === "event")
      return after?.event && (after.seq === undefined || after.seq !== before?.seq) && counts("event") ? ["event", pick("onAdd"),
        {}
      ] : null;
    if (c.model === "set") {
      const sets = root._memberSets(def, key, before, after);
      const was = sets.was;
      const now = sets.now;
      const added = now.filter(id => !was.includes(id));
      const removed = was.filter(id => !now.includes(id));
      // The members as the change saw them (the card's memory once
      // they're gone): those after an arrival, those before a departure
      const extra = {
        "added": added,
        "removed": removed,
        "left": sets.left,
        "members": added.length > 0 ? (after?.members ?? []) : (before?.members ?? [])
      };
      if (added.length > 0)
        return counts("add") ? ["add", pick("onAdd"), extra] : null;
      if (removed.length === 0 || !counts("remove"))
        return null;
      // The last of an owner leaving while it stays on another key of
      // its group
      const gone = root._owners(def, (before?.members ?? []).filter(m => removed.includes(m.id)));
      const kept = sets.left.length === 0 ? (root._partners(def, key, gone, c.after)[0] ?? "") : "";
      return root._removal(def, key, c, sets.left.length > 0, kept, extra);
    }
    // scalar: the value's own change, or its tile's look (a mute); the
    // stronger of the two shows (Wi-Fi off loses its network too)
    const b = before?.value;
    const a = after?.value;
    // A new event on a scalar that carries them: before its value
    if (root.policy(def, key, "carriesEvents") === true && after?.event && after.seq !== before?.seq && counts("event"))
      return ["event", pick("onEvent"),
        {}
      ];
    // A gap (keepThroughGap): nothing until a value comes back
    if (root.policy(def, key, "keepThroughGap") === true && !root._empty(b) && root._empty(a))
      return null;
    let out = null;
    const removed = !root._empty(b) && root._empty(a);
    if (root._empty(b) && !root._empty(a))
      out = counts("add") ? ["add", pick("onAdd"),
        {}
      ] : null;
    else if (removed)
      out = counts("remove") ? root._removal(def, key, c, false, "", {}) : null;
    else if (JSON.stringify(a) !== JSON.stringify(b))
      out = counts("change") ? ["change", pick("onChange"),
        {}
      ] : null;
    if (counts("update") && root._looks(def, key, before, after)) {
      const update = ["update", pick("onUpdate"),
        {}
      ];
      // Its look's card never outranks its value going (a player
      // quitting while it plays: the card would say nothing); its icon
      // still does (Wi-Fi turned off loses its network too)
      if ((!out || root._rank(update[1]) > root._rank(out[1])) && !(removed && update[1] === "card"))
        out = update;
    }
    return out;
  }

  function _rank(show) {
    return show === "card" ? 2 : show === "tile" ? 1 : 0;
  }

  // A departure: `left` some still there, `kept` another key of its
  // group the owner stays on. onUnexpectedRemove for one not made on
  // screen; "still" a card while some are left (here or on `kept`), else
  // the icon
  function _removal(def, key, c, left, kept, extra) {
    const unexpected = c.byUser !== true;
    const own = root.policy(def, key, "onUnexpectedRemove");
    const name = unexpected && own ? own : root.policy(def, key, "onRemove");
    const still = name === "still" && (left || kept !== "");
    const show = name === "still" ? (still ? "card" : "tile") : name === "last" ? (left || kept !== "" ? "tile" : "card") : root._show(name);
    return ["remove", show, Object.assign({
        "still": still,
        "unexpected": unexpected
      }, still && kept ? {
        "kept": kept
      } : {}, extra)];
  }

  // What `key` changing from `before` to `after` (its states) shows, by
  // the definition's model and policies: null for nothing, else { key,
  // part, model, kind ("add" | "remove" | "change" | "update" | "event" |
  // "level"), show ("card" | "tile" | "level"), card (show is "card"),
  // still, unexpected, alert (opens the OSD even after an on-screen mark:
  // only a definition's judge() sets it), added, removed, left (a set's
  // ids), members (a set's, as the change saw them), kept (a group's
  // "still" card: the key the owner stays on), at, byUser }. Never the
  // first reading (`before` missing) nor across a state that isn't
  // `available` (false); then the definition's judge() for an odd case
  // (it reads ctx.settled itself); else the declarations: nothing for a
  // `resetBy` field changing with it, within `ignoreWithin`, or a
  // `keepThroughGap` gap, and a kind `settledKinds` names (every kind
  // unless the system counts `anyone`'s) counts only while the watcher
  // calls it settled. `ctx`: { at, byUser, settled, before, after (the
  // whole states) }
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
      out = root._generic(def, key, before, after, c);
    }
    if (!out || !out[1])
      return null;
    // An event of a kind `alertKinds` lists opens the OSD even after an
    // on-screen mark (a definition's judge() may set it itself)
    const alert = out[0] === "event" && (root.policy(def, key, "alertKinds") ?? []).includes(after?.event?.kind);
    return Object.assign({
      "still": false,
      "unexpected": false,
      "alert": alert,
      "added": [],
      "removed": [],
      "left": [],
      "members": [],
      "kept": ""
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
    if (shown.card !== true || !own)
      return false;
    if (own.sameChange(shown, incoming) === true)
      return true;
    if (incoming.card !== true)
      return false;
    // A "still" card against its own key's "still" card (several leaving
    // one after another: the card out, re-read, names those left)
    if (incoming.still === true && shown.still === true && incoming.key === shown.key)
      return true;
    // A card of another key of its group, an owner in common (one app on
    // the camera and the microphone, a headset taking the output and the
    // input)
    const group = root.groupOf(own, shown.key);
    const owners = shown.tile?.owners ?? [];
    return !!group && incoming.key !== shown.key && group.keys.includes(incoming.key) && (incoming.tile?.owners ?? []).some(o => owners.includes(o));
  }

  // What a change does to what's shown, `elapsed` ms after `shown` came.
  // Both are whole judged changes (judge()'s: key, part, kind, card
  // (bool), still, unexpected, alert, added, removed, left, …) with their
  // `system` and `tile` (that key's tile now); `defs` the definitions by
  // system. Their sameChange() and absorbs() read any of it (Privacy's
  // `still`). Against a card out (`shown.card`): a card
  // "replace"s it or "keep"s it (the same change: the first card says
  // it; a `yieldsCard` system's card against another system's, at any
  // age); a change without one "retract"s it (its own tile turned off,
  // with retractsCardWhenOff: the card would say what no longer holds; at
  // any age), is "suppress"ed (its knock-on) or shows "beside" it.
  // Against the ringed tile (`shown.card` false; a tile change only):
  // "replace" (it takes the ring) or "keep" (its knock-on: nothing shows)
  function arbitrate(shown, incoming, elapsed, defs) {
    const def = defs?.[shown.system];
    if (shown.card === true && incoming.card !== true && incoming.system === shown.system && incoming.key === shown.key && def?.retractsCardWhenOff === true && incoming.tile?.on !== true)
      return "retract";
    if (shown.card === true && incoming.card === true && incoming.system !== shown.system && defs?.[incoming.system]?.yieldsCard === true)
      return "keep";
    const knockOn = elapsed < root.quietWindow && root._knockOn(shown, incoming, defs);
    if (shown.card !== true)
      return knockOn ? "keep" : "replace";
    if (incoming.card === true)
      return knockOn ? "keep" : "replace";
    return knockOn ? "suppress" : "beside";
  }

  // Whether a judged change shows during its watcher's settle window
  // (its first 1.5 s, while services settle, when a change only moves the
  // state on): an event of an `event`-model key, which its watcher pulses
  // as it happens and so is never a service's first reading (an `axiom
  // message` sent just after a start or a list edit). A `carriesEvents`
  // scalar's event is read from its service's state, which may answer
  // with its last one as it starts, so it waits like any other change.
  // A key declaring `countsWithin` gates itself (only the user's own set
  // counts: a brightness key just after a start or a list edit)
  function showsWhileSettling(def, change) {
    if (!change)
      return false;
    if (root.policy(def, change.key, "countsWithin"))
      return true;
    return change.kind === "event" && root.policy(def, change.key, "model") === "event";
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
  // not quiet (a quiet one never opens it). With `key` (the event's: a
  // low battery's `battery`), an item whose `tiles` setting picks the
  // keys it shows (Audio's, Battery's) must pick it. Where none does, an
  // event is a notification instead (cardRoute)
  function opensCard(osd, type, key) {
    if (!osd || !osd.enabled || !osd.cardsEnabled)
      return false;
    const item = root.itemOf(osd, type);
    if (item === null || item.card === false || item.quiet === true)
      return false;
    return !key || !Array.isArray(item.tiles) || item.tiles.includes(key);
  }

  // Where an event of `type` (a system: a drive's, the battery's, a
  // monitor's, a screenshot's, a message's) and `key` goes: "osd" when
  // an OSD of `osds` opens its card (opensCard), else "notification"
  // with `notify` (its section's switch), else "" (nowhere)
  function cardRoute(osds, type, notify, key) {
    if ((osds ?? []).some(osd => root.opensCard(osd, type, key)))
      return "osd";
    return notify ? "notification" : "";
  }
}
