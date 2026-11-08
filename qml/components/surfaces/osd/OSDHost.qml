pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.reusable
import qs.components.surfaces.osd.engine
import qs.components.surfaces.osd.design

// One OSD's parts, each shown for its own change and on its own time:
// the bars (a level changed; vertical bars side by side, horizontal bars
// as rows, or along its edge one line parallel to it, end to end when the
// bars run along it too), the status icons (a tile changed, the one that
// did ringed), and the card (a system's card: OSDSystemHost.card, re-read
// from the live state). Every system of the OSD's `systems` list runs in
// an OSDSystemHost (its definition and watcher, loaded by URL); their
// changes come through OSDEngine's arbitration (OSDEngine.arbitrate:
// against the card out, then the ring) and open the OSD as
// OSDSystemHost.opens says. No system is named here
// (docs/dev/features/osd.md › Engine). The parts stack out from the edge
// in one box, the bars nearest it, then the icons (`iconsPlace` inside:
// the other way round), the card last (OSDParts.partOrder; with
// `holdStill` and the pointer on it, a part coming in goes after the
// others), each sliding out from under the one before as it opens, the
// box as long as the longest, its length easing to fit. With
// `openTogether` a change to the bars or the icons brings out both. The
// bars and the icons out together share their time
// (OSDParts.sharedDeadlines), a card keeping its own; when the last ones
// end the OSD slides away whole, and what comes in meanwhile waits for it
// to be gone. Opened from its edge it brings out the bars and the icons,
// else the card a system offers as its preview (Now playing). Every part
// is built while the OSD is closed, as its systems report their own
// changes.
Item {
  id: root

  // The OSD's entry (OSDConfig.osds)
  required property var osd
  // The screen it's on (a ShellScreen), for its systems
  property var screen: null
  // The edge it slides out of runs vertically
  property bool edgeVertical: false
  // The edge is the bottom or the right one: the parts stack up or left
  property bool edgeAtEnd: false
  // The pointer is on the OSD (its surface or hover strip): the bars and
  // the icons wait (a card only with the pointer on it), and
  // with `holdStill` a part coming in goes past the others
  property bool pointerIn: false
  // Its host is showing (open, or still sliding away): parts opening then
  // slide out; closed, they're simply there as it slides in, and the
  // highlight is released only once it's gone
  property bool hostOpen: false
  // Its host is open: each watcher's opened() picks up what nothing pushes
  property bool open: false

  // A system changed; `force` when it opens the OSD
  signal poked(bool force)
  // The last part's time is up: the OSD closes, its parts going with it
  signal collapse

  // A part is out: the host's own dismiss countdown waits, the parts'
  // times close it (PopoutWrapperBase reads its content's `hovered`)
  readonly property bool hovered: root._order.some(part => root._open[part] === true)

  // ---- The systems ----

  // The systems' types, as a string: any edit to an OSD parses every OSD
  // anew (OSDConfig.osds), and a new array as the model would rebuild
  // every system, deaf while it settles; the string changes only with the
  // list's types. Each one's own settings reach it in place
  readonly property string _systemsKey: root.osd.systems.map(item => item.type).join(",")
  // The card out folds back with its system taken off the list (not as
  // its host goes: any change to the types rebuilds every host)
  on_SystemsKeyChanged: {
    if (root._cardChange && !root.osd.systems.some(item => item.type === root._cardChange.system))
      root._closePart("card");
  }
  // The OSDSystemHosts, in the list's order, as they're built
  property var _hosts: []
  function _register(host, add) {
    const hosts = root._hosts.filter(other => other !== host);
    if (add)
      hosts.push(host);
    hosts.sort((a, b) => a.index - b.index);
    root._hosts = hosts;
  }
  function _hostOf(type) {
    return root._hosts.find(host => host.type === type) ?? null;
  }
  // The definitions by system (OSDEngine.arbitrate's `defs`)
  readonly property var _defs: {
    const out = {};
    for (const host of root._hosts)
      if (host.definition)
        out[host.type] = host.definition;
    return out;
  }
  // The systems whose bars and icons show (their item's `tile` on), with
  // their definition loaded
  readonly property var _shownHosts: root._hosts.filter(host => host.definition && host.options.tile !== false)

  // A tile's id in the row: its system and key ("LockKeys/capsLock")
  function _idOf(change) {
    return change.system + "/" + change.key;
  }

  // The bars, in order: { system, entry } for each `exposes` bar
  readonly property var _levelEntries: [].concat(...root._shownHosts.map(host => host.definition.exposes.filter(e => e.part === "bar").map(e => ({
          "system": host,
          "entry": e
        }))))
  // The tiles it may show, in order (ids), their English names, and each
  // one now (OSDEngine.tileOf's, the watchers')
  readonly property var _tileIds: [].concat(...root._shownHosts.map(host => host.definition.exposes.filter(e => OSDEngine.partOf(host.definition, e.key) === "tile").map(e => host.type + "/" + e.key)))
  readonly property var _tileNames: {
    const out = {};
    for (const host of root._shownHosts)
      for (const e of host.definition.exposes)
        out[host.type + "/" + e.key] = e.label ?? "";
    return out;
  }
  readonly property var tiles: {
    const out = {};
    for (const host of root._shownHosts) {
      const own = host.tiles;
      for (const key of Object.keys(own))
        out[host.type + "/" + key] = own[key];
    }
    return out;
  }
  // The tiles a click on runs the action of (OSDSystemHost.actionOf: a
  // recording's only while it runs)
  readonly property var toggleable: root._tileIds.filter(id => root._actionOf(id) !== null)
  function _actionOf(id) {
    const at = id.indexOf("/");
    const host = root._hostOf(id.slice(0, at));
    return host ? host.actionOf(id.slice(at + 1)) : null;
  }

  // The tile that changed last ("" once the icons close), ringed, its
  // whole change (OSDEngine.arbitrate's `shown`) and when (Date.now())
  property string changed: ""
  property var _ringChange: null
  property real _changedAt: 0

  // Every icon the row has shown since the icons came out: one that
  // turns ordinary (Caps Lock off, an icon clicked) stays in its place
  // until the icons fold back
  property var _kept: []
  // ...and the change, as it comes
  readonly property var _keptNow: root.changed !== "" && !root._kept.includes(root.changed) ? root._kept.concat([root.changed]) : root._kept
  // The status icons shown (what's unusual, every one, or none, and what
  // was shown since they came out: OSDParts.rowTypes)
  readonly property var rowTypes: OSDParts.rowTypes(root._tileIds, root.tiles, root._previewAll ? "all" : root.osd.row, root._keptNow)
  // Keeps what the row shows while the icons are out: run as they open
  // and as a change rings (every change while they're out does), never
  // from a binding on the row, which it feeds. In every `row` mode: with
  // "Only the one that changed" each change joins the ones before it
  function _keepRow() {
    if (root._open.status !== true)
      return;
    const more = root.rowTypes.filter(type => !root._kept.includes(type));
    if (more.length > 0)
      root._kept = root._kept.concat(more);
  }
  // Show on the icons with none to show as they are (nothing unusual):
  // every one, not an empty row, until it closes
  property bool _previewAll: false

  // The card out: the whole change that brought it (kept past the card
  // folding back and the OSD closing, so it doesn't empty as it goes) and
  // when it came
  property var _cardChange: null
  property real _cardAt: 0
  readonly property var _cardHost: root._cardChange ? root._hostOf(root._cardChange.system) : null
  // What it shows, re-read from the live state (OSDSystemHost.card), so
  // it says what holds now
  readonly property var cardContent: root._cardHost ? root._cardHost.card(root._cardChange) : null
  // The design of its own its key names (Now playing's), or "" for the
  // shared card
  readonly property string _cardDesign: root._cardHost?.definition ? (OSDEngine.entryOf(root._cardHost.definition, root._cardChange.key).design ?? "") : ""

  // It may show a shared card: its cards on, and a system with its cards
  // on that has a card switch or a card-only key drawn by the shared card
  readonly property bool hasCards: root.osd.cardsEnabled && root._hosts.some(host => host.definition && host.options.card !== false && (host.options.card !== undefined || host.definition.exposes.some(e => e.part === "card" && !e.design)))
  // The cards drawn by a design of their system's own, as a string
  // ("<type>/<key>/<design>", Paths.osdDesignUrl's): built once each, so
  // the window keeps room for them
  readonly property string _designsKey: root.osd.cardsEnabled ? [].concat(...root._hosts.filter(host => host.definition && host.options.card !== false).map(host => host.definition.exposes.filter(e => e.design && e.part !== "bar").map(e => host.type + "/" + e.key + "/" + e.design))).join(",") : ""
  // Their Loaders, by "<type>/<key>"
  property var _designCards: ({})
  function _registerDesign(id, loader, add) {
    const next = Object.assign({}, root._designCards);
    if (add)
      next[id] = loader;
    else if (next[id] === loader)
      delete next[id];
    root._designCards = next;
  }
  readonly property var _designLoader: root._cardDesign !== "" ? (root._designCards[root._idOf(root._cardChange)] ?? null) : null
  // The card shown: a design's, else the shared one
  readonly property Item _cardItem: root._designLoader?.item ?? statusCard

  // The card an OSD with no bars or icons opens on (its hover strip, the
  // Show button): a card key its system offers as `preview` (Now
  // playing), its cards on and not quiet; null for none
  function _previewChange() {
    if (!root.osd.cardsEnabled)
      return null;
    for (const host of root._hosts) {
      if (!host.definition || host.options.card === false || host.options.quiet === true)
        continue;
      const e = host.definition.exposes.find(entry => entry.preview === true);
      if (e)
        return {
          "system": host.type,
          "key": e.key,
          "part": OSDEngine.partOf(host.definition, e.key),
          "model": "event",
          "kind": "event",
          "show": "card",
          "card": true,
          "still": false,
          "unexpected": false,
          "alert": false,
          "added": [],
          "removed": [],
          "left": [],
          "at": Date.now(),
          "byUser": false,
          "tile": null
        };
    }
    return null;
  }

  // ---- The parts ----
  // OSDParts.parts: "level" (the bars), "status" (the icons), "card"

  // The parts out (or folding back), out from the edge in order
  property var _order: []
  // Which are open, and when each one's time is up (Date.now(); 0: none)
  property var _open: ({})
  property var _deadlines: ({})
  // The deadlines' merge: parts due this close together close together
  readonly property int grace: 750
  // A part opening on a shut OSD is simply there as it slides in: only
  // one opening on an open OSD slides out
  property bool _snapping: false
  readonly property bool _animate: root.hostOpen && !root._snapping

  // How far each part is out (0-1, eased)
  property real _levelReveal: root._open.level === true ? 1 : 0
  property real _statusReveal: root._open.status === true ? 1 : 0
  property real _cardReveal: root._open.card === true ? 1 : 0
  Glide on _levelReveal {
    duration: Appearance.animNormal
    enabled: root._animate
  }
  Glide on _statusReveal {
    duration: Appearance.animNormal
    enabled: root._animate
  }
  Glide on _cardReveal {
    duration: Appearance.animNormal
    enabled: root._animate
  }
  // A part folded all the way back leaves the order
  on_LevelRevealChanged: root._folded("level", root._levelReveal)
  on_StatusRevealChanged: root._folded("status", root._statusReveal)
  on_CardRevealChanged: root._folded("card", root._cardReveal)

  function _reveal(part) {
    return part === "level" ? root._levelReveal : part === "status" ? root._statusReveal : root._cardReveal;
  }
  function _item(part) {
    return part === "level" ? grid : part === "status" ? row : root._cardItem;
  }
  function _timeout(part) {
    return part === "card" ? root.osd.cardTimeout : root.osd.timeout;
  }

  function _clearRing() {
    root.changed = "";
    root._ringChange = null;
  }

  function _folded(part, reveal) {
    if (reveal > 0 || root._open[part] === true || !root._order.includes(part))
      return;
    root._order = root._order.filter(other => other !== part);
    if (part === "status") {
      root._clearRing();
      root._kept = [];
      root._previewAll = false;
    }
  }

  function _setOpen(part, open) {
    const next = Object.assign({}, root._open);
    next[part] = open;
    root._open = next;
    root._setDeadline(part, open ? Date.now() + root._timeout(part) : 0);
  }

  // One part's time, shared (OSDParts.sharedDeadlines: the bars and the
  // icons close together, a card on its own)
  function _setDeadline(part, at) {
    const due = Object.assign({}, root._deadlines);
    due[part] = at;
    root._deadlines = OSDParts.sharedDeadlines(due);
  }

  // Closing: the last parts' time is up, until the OSD has slid away.
  // What comes in meanwhile waits for it to be gone (`_pending`)
  property bool _closing: false
  // { parts: [part], card, cardAt, ring, force } or null
  property var _pending: null

  // Whether a part opening now waits for the close (queued with `force`
  // and `extra`: the card's { card, cardAt }, the icons' { ring })
  function _queued(part, force, extra) {
    if (!root._closing)
      return false;
    const pending = root._pending ?? ({
        "parts": [],
        "force": false
      });
    if (!pending.parts.includes(part))
      pending.parts = pending.parts.concat([part]);
    if (extra)
      Object.assign(pending, extra);
    pending.force = pending.force || force;
    root._pending = pending;
    return true;
  }

  // The last parts' time is up: the OSD slides away whole
  function _close() {
    root._closing = true;
    root.collapse();
  }

  // Opens a part (or restarts its time), placed by OSDParts.partOrder.
  // The icons coming out with none to show as they are show every one,
  // not an empty row, until they close (`_previewAll`)
  function _openPart(part) {
    // Before the order changes: the eased lengths read the order, and
    // their eases must already know whether this one slides out
    root._snapping = !root.hostOpen || !root._order.some(other => other !== part && root._reveal(other) > 0);
    if (part === "status" && root._open.status !== true)
      root._previewAll = OSDParts.rowTypes(root._tileIds, root.tiles, root.osd.row, root._keptNow).length === 0;
    if (!root._order.includes(part))
      root._order = OSDParts.partOrder(root._order, part, root.osd.holdStill && root.pointerIn && root.hostOpen, root.osd.iconsPlace === "inside");
    root._setOpen(part, true);
    root._keepRow();
    root._snapping = false;
    root._schedule();
  }

  // The box's parts a change of one brings out: both, with
  // `openTogether` and an OSD showing both; else that one
  function _boxParts(part) {
    return root.osd.openTogether && root._levelEntries.length > 0 && root._tileIds.length > 0 ? ["level", "status"] : [part];
  }

  function _closePart(part) {
    if (root._open[part] === true)
      root._setOpen(part, false);
  }

  // The pointer on the OSD holds the bars and the icons; the card only
  // while it's on the card itself (its time runs while the pointer is on
  // the rest)
  function _pointerHolds(part) {
    return root.pointerIn && (part !== "card" || root.cardHovered);
  }
  // The deadlines of the parts not held
  function _running() {
    const out = {};
    Object.keys(root._deadlines).forEach(part => {
      if (!root._pointerHolds(part))
        out[part] = root._deadlines[part];
    });
    return out;
  }

  // The next time a part not held is up
  function _schedule() {
    dueTimer.stop();
    const next = OSDParts.partsDue(root._running(), Date.now(), root.grace).next;
    if (next > 0) {
      dueTimer.interval = Math.max(1, next - Date.now());
      dueTimer.start();
    }
  }

  // Parts' times up: the card, or the bars and the icons, fold back; the
  // last ones going together close the OSD, sliding away whole
  function _due() {
    const due = OSDParts.partsDue(root._running(), Date.now(), root.grace).due;
    const open = root._order.filter(part => root._open[part] === true);
    if (open.length > 0 && open.every(part => due.includes(part))) {
      root._close();
      return;
    }
    due.forEach(part => root._closePart(part));
    root._schedule();
  }

  Timer {
    id: dueTimer
    onTriggered: root._due()
  }

  // The pointer on the card (it holds the card's time)
  readonly property bool cardHovered: root._designLoader ? root._designLoader.hovered : statusCardHover.hovered

  // A part held by the pointer gets its time anew as it's let go
  function _renew(parts) {
    const due = Object.assign({}, root._deadlines);
    parts.filter(part => root._open[part] === true).forEach(part => due[part] = Date.now() + root._timeout(part));
    root._deadlines = OSDParts.sharedDeadlines(due);
  }

  // The pointer on it holds the bars and the icons (it brings them out
  // only as it opens the OSD from its edge: onHostOpenChanged); leaving,
  // they get their time anew (the card too if it was on it)
  onPointerInChanged: {
    if (!root.pointerIn)
      root._renew(root.cardHovered ? OSDParts.parts : ["level", "status"]);
    root._schedule();
  }
  onCardHoveredChanged: {
    if (!root.cardHovered)
      root._renew(["card"]);
    root._schedule();
  }

  // The bars and the icons (every icon when none would show, until they
  // close), else the card a system offers as its preview: it opening with
  // nothing out (its hover strip), the Show button
  function _expose() {
    if (root._levelEntries.length > 0)
      root._openPart("level");
    if (root._tileIds.length > 0)
      root._openPart("status");
    if (root._levelEntries.length === 0 && root._tileIds.length === 0 && root._open.card !== true) {
      const preview = root._previewChange();
      if (preview) {
        root._cardChange = preview;
        root._cardAt = Date.now();
        root._openPart("card");
      }
    }
  }

  // Open with nothing out: _expose. Gone: every part with it, then what
  // came in as it closed (`_pending`), the OSD opening again for it
  onHostOpenChanged: {
    if (root.hostOpen) {
      if (!root._order.some(part => root._open[part] === true))
        root._expose();
      return;
    }
    dueTimer.stop();
    root._snapping = true;
    root._open = ({});
    root._deadlines = ({});
    root._order = [];
    root._snapping = false;
    root._clearRing();
    root._kept = [];
    root._previewAll = false;
    root._closing = false;
    const pending = root._pending;
    root._pending = null;
    if (!pending?.force)
      return;
    if (pending.parts.includes("card") && pending.card) {
      root._cardChange = pending.card;
      root._cardAt = pending.cardAt;
    }
    if (pending.ring)
      root._ring(pending.ring);
    pending.parts.forEach(part => root._openPart(part));
    root.poked(true);
  }

  // Its systems' watchers pick up, as it opens, what nothing pushes
  onOpenChanged: {
    if (root.open)
      root._hosts.forEach(host => host.watch?.opened());
  }

  // ---- Size ----

  // An item's size across the edge, and along it
  function _depth(item) {
    return root.edgeVertical ? item.implicitWidth : item.implicitHeight;
  }
  function _length(item) {
    return root.edgeVertical ? item.implicitHeight : item.implicitWidth;
  }

  // The gap between parts: its host's padding inside its stroke
  // (EdgePopout.contentPadding less the border), so a part is as far from
  // the next as the outer ones are from the outline, and the nearest from
  // the screen edge (EdgePopout.attachExtra keeps that the same)
  property real gap: Widget.spacing * 2
  // ---- Its length ----
  // One box, attached or held off the edge, as long as its longest part:
  // a card shorter than the bars runs as long as them, a longer one makes
  // the box as long as it. The length eases to each new one
  // (`_lengthEased`): the box's ends run out to meet a longer part as it
  // slides out, and back as it folds; a jump left what was out shifting a
  // frame before the rest
  // The parts that size it: the open ones (one folding back gives its
  // room up as it goes), else, closing, every one still out
  readonly property var _sizing: {
    const open = root._order.filter(part => root._open[part] === true);
    return open.length > 0 ? open : root._order;
  }
  readonly property real _lengthTarget: Math.max(0, ...root._sizing.map(part => root._length(root._item(part))))
  property real _lengthEased: root._lengthTarget
  Glide on _lengthEased {
    duration: Appearance.animNormal
    enabled: root._animate
  }
  readonly property real _lengthNow: Math.round(root._lengthEased)

  // A part's empty margin across the edge, round what shows (a card's
  // round its picture): gaps are measured between what shows, so a
  // part's own margin doesn't add to them, nor to the padding at the
  // outline (the margin runs on into it; the host doesn't clip its
  // content). A bar's margin holds its muted highlight, which shows: its
  // edge is what shows (run on into the gap, it sat cramped)
  function _inset(part) {
    return part === "card" ? root._cardItem.inset(root.edgeVertical) : 0;
  }

  // Each part's place across the edge as it stands (its slot: its gap
  // before it, as far as both it and something before it are out, then
  // what shows with its margin each side), and the whole (what shows,
  // margins left out), in whole pixels as its outline is (a fraction
  // left the content a pixel off its outline, and its window's size
  // wobbling)
  readonly property var _layout: {
    let at = 0;
    let before = 0;
    const out = {};
    root._order.forEach(part => {
      const reveal = root._reveal(part);
      const inset = Math.round(reveal * root._inset(part));
      const gapNow = Math.round(root.gap * reveal * Math.min(1, before));
      const shows = Math.max(0, Math.round(reveal * root._depth(root._item(part))) - inset * 2);
      out[part] = {
        "at": at + gapNow - inset,
        "depth": shows + inset * 2
      };
      at += gapNow + shows;
      before += reveal;
    });
    out.total = at;
    return out;
  }
  implicitWidth: root.edgeVertical ? root._layout.total : root._lengthNow
  implicitHeight: root.edgeVertical ? root._lengthNow : root._layout.total

  // Its length along the edge for the hover strip: the parts' full
  // length (not the eased one, so its window resizes once per part, not
  // every frame), else the part it opens on while shut
  readonly property real triggerLength: Math.round(root._lengthTarget > 0 ? root._lengthTarget : root._length(root._levelEntries.length > 0 ? grid : row))

  // The OSD's largest size across its edge, every part out at once, so
  // its window keeps room for them (EdgePopout.maxContentDepth). The
  // icons' at their largest (OSDTileRow.maxDepth): they come and go
  readonly property real maxDepth: {
    // (what shows: margins run on into the padding and the gaps)
    const parts = root._tileIds.length > 0 ? [row.maxDepth] : [];
    if (root._levelEntries.length > 0)
      parts.push(root._depth(grid));
    // (a card's at its largest, as it sizes to its text: OSDCard.maxShown,
    // its widest beside a side edge, else its faint line wrapped to its
    // most; a design's own too)
    const designs = Object.keys(root._designCards).map(id => root._designCards[id].item).filter(item => item && typeof item.maxShown === "function");
    const deepest = Math.max(root.hasCards ? statusCard.maxShown(root.edgeVertical) : 0, ...designs.map(item => item.maxShown(root.edgeVertical)));
    if (deepest > 0)
      parts.push(deepest);
    return Math.ceil(parts.reduce((sum, depth) => sum + depth, 0) + root.gap * Math.max(0, parts.length - 1));
  }

  // Length of each bar along its axis; the OSD grows with the bar count in
  // the other direction
  readonly property int barLength: Widget.px(190)
  readonly property int barSpacing: Widget.padding * 2
  readonly property bool vertical: root.osd.barLayout.orientation === "vertical"

  // A system's change (OSDSystemHost.change: OSDEngine.judge's): what it
  // shows on this OSD (OSDEngine.shownAs: a card shown as its tile with
  // the cards off; a bar only with its item's `tile` on), whole for the
  // arbitration (its `system` and its tile now: a bar's its mark's,
  // OSDEngine.contextTile), and whether it opens
  // the OSD shut (OSDSystemHost.opens)
  function _onChange(host, what) {
    const def = host.definition;
    if (!def)
      return;
    const hasTile = OSDEngine.partOf(def, what.key) === "tile";
    const shown = OSDEngine.shownAs(root.osd, Object.assign({}, what, {
      "system": host.type
    }), hasTile);
    if (shown === "")
      return;
    const incoming = Object.assign({}, what, {
      "system": host.type,
      "show": shown,
      "card": shown === "card",
      "tile": OSDEngine.contextTile(def, what.key, host.snapshot)
    });
    const force = host.opens(what);
    if (shown === "card")
      root._showCard(incoming, force);
    else if (shown === "tile")
      root._showTile(incoming, force);
    else
      root._showLevel(incoming, force);
  }

  // The card out, if any, against a change (OSDEngine.arbitrate)
  function _againstCard(incoming, now) {
    if (root._open.card !== true || !root._cardChange)
      return "";
    return OSDEngine.arbitrate(root._cardChange, incoming, now - root._cardAt, root._defs);
  }

  function _ring(change) {
    root.changed = root._idOf(change);
    root._ringChange = Object.assign({}, change, {
      "card": false
    });
    root._changedAt = Date.now();
    root._keepRow();
  }

  // A card: only the card shows, the change's icon turning lit quietly
  // (ringed if the icons are out), unless the card out is the same change
  // ("keep")
  function _showCard(incoming, force) {
    // A quiet change with the OSD shut is never seen
    if (!force && !root.hostOpen)
      return;
    const now = Date.now();
    // A card already waiting for the close is judged as the card out
    // would be: kept ("keep"), the new one queues no card of its own
    const keepQueued = root._closing && root._pending?.card && OSDEngine.arbitrate(root._pending.card, incoming, now - root._pending.cardAt, root._defs) === "keep";
    if (root._queued("card", force, keepQueued ? null : {
      "card": incoming,
      "cardAt": now
    })) {
      root.poked(force);
      return;
    }
    if (root._againstCard(incoming, now) === "keep")
      return;
    root._cardChange = incoming;
    root._cardAt = now;
    root._openPart("card");
    if (root._open.status === true && root._tileIds.includes(root._idOf(incoming)))
      root._ring(incoming);
    root.poked(force);
  }

  // A tile without a card: the icons show, it ringed, unless it's a
  // knock-on of the card out ("suppress") or of the ring ("keep"); a card
  // it makes stale folds back ("retract")
  function _showTile(incoming, force) {
    if (!force && !root.hostOpen)
      return;
    const now = Date.now();
    if (root._queued("status", force, {
      "ring": incoming
    })) {
      root._boxParts("status").forEach(other => root._queued(other, force));
      root.poked(force);
      return;
    }
    const against = root._againstCard(incoming, now);
    if (against === "suppress")
      return;
    if (against === "retract")
      root._closePart("card");
    if (root._open.status === true && root._ringChange && OSDEngine.arbitrate(root._ringChange, incoming, now - root._changedAt, root._defs) === "keep")
      return;
    root._ring(incoming);
    root._boxParts("status").forEach(other => root._openPart(other));
    root.poked(force);
  }

  // A bar: the bars show, unless it's a knock-on of the card out (a
  // device's own level coming in after its switch's card: "suppress")
  function _showLevel(incoming, force) {
    if (!force && !root.hostOpen)
      return;
    if (root._queued("level", force)) {
      root._boxParts("level").forEach(other => root._queued(other, force));
      root.poked(force);
      return;
    }
    const against = root._againstCard(incoming, Date.now());
    if (against === "suppress")
      return;
    if (against === "retract")
      root._closePart("card");
    root._boxParts("level").forEach(other => root._openPart(other));
    root.poked(force);
  }

  // An icon clicked: runs its action, as its key would (it stays in
  // place: `_kept`), marked as the pointer's: this OSD is open, so it
  // shows the change, which a VPN taken down here says is expected
  function toggle(id) {
    const at = id.indexOf("/");
    const host = root._hostOf(id.slice(0, at));
    const key = id.slice(at + 1);
    const action = host ? host.actionOf(key) : null;
    if (!action)
      return;
    ShellManager.onScreen(OSDEngine.markOf(host.definition, key));
    ActionsManager.run(action.id, {
      "call": action.call
    });
  }

  // A click on a card that takes one: its system's watcher acts on it (a
  // drive's opens it)
  function _activateCard() {
    if (root._cardHost && root._cardChange)
      root._cardHost.activate(root._cardChange);
  }

  // The settings page's Show: the bars and the status icons as they are
  // (every one when none would show)
  function preview() {
    root._clearRing();
    root._expose();
  }

  // ---- Drawing ----

  // A part's slot: clipped to how far it's out, at its place out from the
  // edge (`place`, _layout's), the part held at its far end so it slides
  // out from under the one before, centred along the edge
  function _place(part) {
    return root._layout[part] ?? ({
        "at": 0,
        "depth": 0
      });
  }
  function _slotX(place) {
    return !root.edgeVertical ? 0 : root.edgeAtEnd ? root.width - place.at - place.depth : place.at;
  }
  function _slotY(place) {
    return root.edgeVertical ? 0 : root.edgeAtEnd ? root.height - place.at - place.depth : place.at;
  }
  // (centred on a whole pixel: a half one, flipping as the length eases,
  // shimmered what was out)
  function _farX(slot, item) {
    return root.edgeVertical ? (root.edgeAtEnd ? 0 : slot.width - item.implicitWidth) : Math.round((slot.width - item.implicitWidth) / 2);
  }
  function _farY(slot, item) {
    return !root.edgeVertical ? (root.edgeAtEnd ? 0 : slot.height - item.implicitHeight) : Math.round((slot.height - item.implicitHeight) / 2);
  }

  Item {
    id: levelSlot
    readonly property var place: root._place("level")
    visible: levelSlot.place.depth > 0
    clip: true
    x: root._slotX(levelSlot.place)
    y: root._slotY(levelSlot.place)
    width: root.edgeVertical ? levelSlot.place.depth : root.width
    height: root.edgeVertical ? root.height : levelSlot.place.depth

    GridLayout {
      id: grid
      readonly property bool rowFlow: root.osd.barLayout.alongEdge ? !root.edgeVertical : root.vertical
      x: root._farX(levelSlot, grid)
      y: root._farY(levelSlot, grid)
      width: implicitWidth
      height: implicitHeight
      flow: rowFlow ? GridLayout.LeftToRight : GridLayout.TopToBottom
      columnSpacing: root.barSpacing
      rowSpacing: root.barSpacing

      Repeater {
        // By count, so edits to a bar update it in place
        model: root._levelEntries.length

        delegate: OSDLevelBar {
          id: levelBar
          required property int index
          readonly property var _at: root._levelEntries[levelBar.index] ?? null

          system: levelBar._at?.system ?? null
          entry: levelBar._at?.entry ?? ({})
          vertical: root.vertical
          showPercent: root.osd.barLayout.showPercent
          Layout.preferredWidth: root.vertical ? implicitWidth : root.barLength
          Layout.preferredHeight: root.vertical ? root.barLength : implicitHeight
        }
      }
    }
  }

  Item {
    id: statusSlot
    readonly property var place: root._place("status")
    // Never hidden, only clipped and taking no pointer while folded: the
    // tiles' own visibility (OSDTileRow) changes while it's folded, and
    // under a hidden item that changes nothing their layout sees, so the
    // row stayed 0 wide and never came out
    enabled: statusSlot.place.depth > 0
    clip: true
    x: root._slotX(statusSlot.place)
    y: root._slotY(statusSlot.place)
    width: root.edgeVertical ? statusSlot.place.depth : root.width
    height: root.edgeVertical ? root.height : statusSlot.place.depth

    OSDTileRow {
      id: row
      x: root._farX(statusSlot, row)
      y: root._farY(statusSlot, row)
      allTypes: root._tileIds
      types: root.rowTypes
      tiles: root.tiles
      names: root._tileNames
      changed: root.changed
      vertical: root.edgeVertical
      toggleable: root.toggleable
      onToggled: id => root.toggle(id)
    }
  }

  Item {
    id: cardSlot
    readonly property var place: root._place("card")
    visible: cardSlot.place.depth > 0
    clip: true
    x: root._slotX(cardSlot.place)
    y: root._slotY(cardSlot.place)
    width: root.edgeVertical ? cardSlot.place.depth : root.width
    height: root.edgeVertical ? root.height : cardSlot.place.depth

    OSDCard {
      id: statusCard
      visible: root._designLoader === null
      x: root._farX(cardSlot, statusCard)
      y: root._farY(cardSlot, statusCard)
      card: root.cardContent
      change: root._cardChange

      HoverHandler {
        id: statusCardHover
      }
      // Only a card that's `clickable` takes one (a drive's, a
      // screenshot's): its system acts on it
      onClicked: root._activateCard()
    }

    // The cards drawn by a design of their system's own (loaded by URL,
    // Paths.osdDesignUrl), each built once
    Repeater {
      model: root._designsKey === "" ? [] : root._designsKey.split(",")

      delegate: Loader {
        id: designCard
        required property string modelData
        // ("<type>/<key>/<design>", the design a path that may hold more)
        readonly property var _parts: designCard.modelData.split("/")
        readonly property string cardId: designCard._parts[0] + "/" + designCard._parts[1]
        readonly property bool hovered: designHover.hovered

        visible: root._designLoader === designCard
        x: root._farX(cardSlot, designCard)
        y: root._farY(cardSlot, designCard)

        HoverHandler {
          id: designHover
        }
        Binding {
          target: designCard.item
          property: "card"
          value: root._designLoader === designCard ? root.cardContent : null
          when: designCard.item !== null
        }
        Binding {
          target: designCard.item
          property: "change"
          value: root._designLoader === designCard ? root._cardChange : null
          when: designCard.item !== null
        }
        Connections {
          target: designCard.item
          ignoreUnknownSignals: true
          function onClicked() {
            root._activateCard();
          }
        }

        Component.onCompleted: {
          designCard.source = Paths.osdDesignUrl(designCard._parts[0], designCard._parts.slice(2).join("/"));
          root._registerDesign(designCard.cardId, designCard, true);
        }
        Component.onDestruction: root._registerDesign(designCard.cardId, designCard, false)
      }
    }
  }

  // The systems (they draw nothing): each one's definition and watcher
  Repeater {
    model: root._systemsKey === "" ? [] : root._systemsKey.split(",")

    delegate: OSDSystemHost {
      id: system
      required property string modelData
      required property int index

      type: system.modelData
      options: root.osd.systems[system.index] ?? ({})
      screen: root.screen
      osdId: root.osd.id
      onChange: what => root._onChange(system, what)
      Component.onCompleted: root._register(system, true)
      Component.onDestruction: root._register(system, false)
    }
  }

  Connections {
    target: ShellManager

    function onShowOsd(id) {
      if (id === root.osd.id)
        root.preview();
    }
  }
}
