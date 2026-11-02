pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.reusable

// One OSD's parts, each shown for its own change and on its own time:
// the bars (a level changed; vertical bars side by side, horizontal bars
// as rows, or along its edge one line parallel to it, end to end when the
// bars run along it too), the status icons (a status changed, the one
// that did ringed), and the card (a status's card, OSDItems.card: an
// audio device switched, a VPN came up, an app started a capture, the
// charger was plugged in, Wi-Fi joined a network, a drive event, a
// message; or the now playing card). They stack out from the edge in
// one box, the bars nearest it, then the icons (`iconsPlace` inside:
// the other way round), the card last
// (OSDItems.partOrder; with `holdStill` and the pointer on it, a part
// coming in goes after the others), each sliding out from under the one before
// as it opens, the box as long as the longest, its length easing to fit.
// With `openTogether` a change to the bars or the icons brings out both.
// The bars and the icons out together share their time
// (OSDItems.sharedDeadlines), a card keeping its own; when the last ones
// end the OSD slides away whole, and what comes in meanwhile waits for it
// to be gone. Opened from its edge it brings out the bars
// and the icons. Every part is built while the OSD is closed, as its items
// report their own changes.
Item {
  id: root

  // The OSD's entry (OSDConfig.osds)
  required property var osd
  required property string screenName
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

  // An item changed; `force` when it opens the OSD
  signal poked(bool force)
  // The last part's time is up: the OSD closes, its parts going with it
  signal collapse

  // A part is out: the host's own dismiss countdown waits, the parts'
  // times close it (PopoutWrapperBase reads its content's `hovered`)
  readonly property bool hovered: root._order.some(part => root._open[part] === true)

  readonly property var levelItems: osd.bars.items
  readonly property var statusTypes: osd.statuses.items
  // Its cards on (`cards.enabled`), and the card-only types it picks
  // (`cards.items`: OSDItems.cardOnlyTypes, and "media", Now playing)
  readonly property bool cards: root.osd.cards.enabled
  readonly property var _cardOnly: root.cards ? root.osd.cards.items.filter(type => type !== "media") : []
  readonly property bool hasMedia: root.cards && root.osd.cards.items.includes("media")

  // The status that changed last ("" once the icons close), ringed, and
  // when (Date.now(), for OSDItems.replaces)
  property string changed: ""
  property real _changedAt: 0

  // Every status's tile (OSDItems.tile) by type, as its source reports it;
  // a message's from the last one (shown as its card, never in the row)
  property var tiles: ({})
  // The sources by type, and the types a click on their icon flips (a
  // recording's only while it runs)
  property var _sources: ({})
  readonly property var toggleable: Object.keys(root._sources).filter(type => root._sources[type]?.canToggle === true)
  // Every icon the row has shown since the icons came out: one that
  // turns ordinary (Caps Lock off, an icon clicked) stays in its place
  // until the icons fold back
  property var _kept: []
  // ...and the change, as it comes
  readonly property var _keptNow: root.changed !== "" && !root._kept.includes(root.changed) ? root._kept.concat([root.changed]) : root._kept
  // The status icons shown (what's unusual, every one, or none, and what
  // was shown since they came out: OSDItems.rowTypes)
  readonly property var rowTypes: OSDItems.rowTypes(root.statusTypes, root.tiles, root._previewAll ? "all" : root.osd.statuses.row, root._keptNow)
  // Keeps what the row shows while the icons are out: run as they open
  // and as a change rings (every change while they're out does), never
  // from a binding on the row, which it feeds
  // ("Only the one that changed" keeps none: it shows just the latest)
  function _keepRow() {
    if (root._open.status !== true || root.osd.statuses.row === "changed")
      return;
    const more = root.rowTypes.filter(type => !root._kept.includes(type));
    if (more.length > 0)
      root._kept = root._kept.concat(more);
  }
  // Show on the icons with none to show as they are (nothing unusual):
  // every one, not an empty row, until it closes
  property bool _previewAll: false

  // It may show a status's card: its cards on, for a status icon with one
  // (OSDItems.cardTypes; with its cards off the change shows as its icon)
  // or a card-only type it picks
  readonly property bool hasCards: root.cards && (OSDItems.cardTypes.some(type => root.statusTypes.includes(type)) || root._cardOnly.length > 0)
  // What the status card shows (OSDItems.card), its role translated
  // I18n.tr("Output") I18n.tr("Input") I18n.tr("Output and input") I18n.tr("Connected") I18n.tr("Using the camera") I18n.tr("Using the microphone") I18n.tr("Using the camera and microphone") I18n.tr("Sharing the screen") I18n.tr("Stopped using the camera") I18n.tr("Stopped using the microphone") I18n.tr("Stopped sharing the screen") I18n.tr("Charging") I18n.tr("Fully charged") I18n.tr("Plugged in") I18n.tr("Mounted") I18n.tr("Safe to remove") I18n.tr("Unmounted") I18n.tr("Disconnected") I18n.tr("Unplugged without ejecting") I18n.tr("In use: close what's using it") I18n.tr("Couldn't eject") I18n.tr("Encrypted: click to unlock") I18n.tr("Battery low") I18n.tr("Battery critically low") I18n.tr("Copied to the clipboard")
  readonly property var cardContent: {
    const card = OSDItems.card(root._cardType, root.tiles, root.statusTypes);
    return card ? Object.assign(card, {
      "role": card.role !== "" ? I18n.tr(card.role) : ""
    }) : null;
  }
  // The card part's card: a status's ("status") or now playing ("media")
  property string _cardKind: "status"
  // The status the card shows (its type), and when it came: kept past
  // the card folding back and the OSD closing, so it doesn't empty as it
  // goes
  property string _cardType: ""
  property real _cardAt: 0

  // ---- The parts ----
  // OSDItems.parts: "level" (the bars), "status" (the icons), "card"

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
    return part === "level" ? grid : part === "status" ? row : root._cardKind === "media" ? mediaCard : statusCard;
  }
  function _timeout(part) {
    return part === "card" ? root.osd.cards.timeout : root.osd.timeout;
  }

  function _folded(part, reveal) {
    if (reveal > 0 || root._open[part] === true || !root._order.includes(part))
      return;
    root._order = root._order.filter(other => other !== part);
    if (part === "status") {
      root.changed = "";
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

  // One part's time, shared (OSDItems.sharedDeadlines: the bars and the
  // icons close together, a card on its own)
  function _setDeadline(part, at) {
    const due = Object.assign({}, root._deadlines);
    due[part] = at;
    root._deadlines = OSDItems.sharedDeadlines(due);
  }

  // Closing: the last parts' time is up, until the OSD has slid away.
  // What comes in meanwhile waits for it to be gone (`_pending`)
  property bool _closing: false
  // { parts: [part], kind, type, at, ring, force } or null
  property var _pending: null

  // Whether a part opening now waits for the close (queued with `force`
  // and `extra`: the card's { kind, type, at }, the icons' { ring })
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

  // Opens a part (or restarts its time), placed by OSDItems.partOrder.
  // The icons coming out with none to show as they are show every one,
  // not an empty row, until they close (`_previewAll`)
  function _openPart(part) {
    // Before the order changes: the eased lengths read the order, and
    // their eases must already know whether this one slides out
    root._snapping = !root.hostOpen || !root._order.some(other => other !== part && root._reveal(other) > 0);
    if (part === "status" && root._open.status !== true)
      root._previewAll = OSDItems.rowTypes(root.statusTypes, root.tiles, root.osd.statuses.row, root._keptNow).length === 0;
    if (!root._order.includes(part))
      root._order = OSDItems.partOrder(root._order, part, root.osd.holdStill && root.pointerIn && root.hostOpen, root.osd.iconsPlace === "inside");
    root._setOpen(part, true);
    root._keepRow();
    root._snapping = false;
    root._schedule();
  }

  // The box's parts a change of one brings out: both, with
  // `openTogether` and an OSD showing both; else that one
  function _boxParts(part) {
    return root.osd.openTogether && root.levelItems.length > 0 && root.statusTypes.length > 0 ? ["level", "status"] : [part];
  }
  // A bar changed: its box parts wait for the close, or come out
  function _openBox(part, force) {
    const parts = root._boxParts(part);
    if (root._queued(part, force)) {
      parts.forEach(other => root._queued(other, force));
      return true;
    }
    parts.forEach(other => root._openPart(other));
    return false;
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
    const next = OSDItems.partsDue(root._running(), Date.now(), root.grace).next;
    if (next > 0) {
      dueTimer.interval = Math.max(1, next - Date.now());
      dueTimer.start();
    }
  }

  // Parts' times up: the card, or the bars and the icons, fold back; the
  // last ones going together close the OSD, sliding away whole
  function _due() {
    const due = OSDItems.partsDue(root._running(), Date.now(), root.grace).due;
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
  readonly property bool cardHovered: root._cardKind === "media" ? mediaCardHover.hovered : statusCardHover.hovered

  // A part held by the pointer gets its time anew as it's let go
  function _renew(parts) {
    const due = Object.assign({}, root._deadlines);
    parts.filter(part => root._open[part] === true).forEach(part => due[part] = Date.now() + root._timeout(part));
    root._deadlines = OSDItems.sharedDeadlines(due);
  }

  // The pointer on it holds the bars and the icons (it brings them out
  // only as it opens the OSD from its edge: onHostOpenChanged); leaving,
  // they get their time anew (the card too if it was on it)
  onPointerInChanged: {
    if (!root.pointerIn)
      root._renew(root.cardHovered ? OSDItems.parts : ["level", "status"]);
    root._schedule();
  }
  onCardHoveredChanged: {
    if (!root.cardHovered)
      root._renew(["card"]);
    root._schedule();
  }

  // The bars and the icons (every icon when none would show, until they
  // close), else the now playing card: it opening with nothing out (its
  // hover strip), the Show button
  function _expose() {
    if (root.levelItems.length > 0)
      root._openPart("level");
    if (root.statusTypes.length > 0)
      root._openPart("status");
    if (root.levelItems.length === 0 && root.statusTypes.length === 0 && root.hasMedia && root._open.card !== true) {
      root._cardKind = "media";
      root._openPart("card");
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
    root.changed = "";
    root._kept = [];
    root._previewAll = false;
    root._closing = false;
    const pending = root._pending;
    root._pending = null;
    if (!pending?.force)
      return;
    if (pending.parts.includes("card")) {
      root._cardKind = pending.kind;
      // (a now playing card queues no status)
      if (pending.kind === "status") {
        root._cardType = pending.type;
        root._cardAt = pending.at;
      }
    }
    if (pending.ring)
      root._ring(pending.ring);
    pending.parts.forEach(part => root._openPart(part));
    root.poked(true);
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
    return part === "card" ? root._item("card").inset(root.edgeVertical) : 0;
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
  readonly property real triggerLength: Math.round(root._lengthTarget > 0 ? root._lengthTarget : root._length(root.levelItems.length > 0 ? grid : row))

  // The OSD's largest size across its edge, every part out at once, so
  // its window keeps room for them (EdgePopout.maxContentDepth). The
  // icons' at their largest (OSDStatusRow.maxDepth): they come and go
  readonly property real maxDepth: {
    // (what shows: margins run on into the padding and the gaps)
    const parts = root.statusTypes.length > 0 ? [row.maxDepth] : [];
    if (root.levelItems.length > 0)
      parts.push(root._depth(grid));
    // (beside a side edge a card's width is its depth: the widest it
    // may be, OSDCard.maxWidth, as it sizes to its text)
    const cardDepth = card => (root.edgeVertical ? card.maxWidth : root._depth(card)) - card.inset(root.edgeVertical) * 2;
    const deepest = Math.max(root.hasCards ? cardDepth(statusCard) : 0, root.hasMedia ? cardDepth(mediaCard) : 0);
    if (deepest > 0)
      parts.push(deepest);
    return Math.ceil(parts.reduce((sum, depth) => sum + depth, 0) + root.gap * Math.max(0, parts.length - 1));
  }

  // Length of each bar along its axis; the OSD grows with the bar count in
  // the other direction
  readonly property int barLength: Widget.px(190)
  readonly property int barSpacing: Widget.padding * 2
  readonly property bool vertical: osd.bars.orientation === "vertical"
  // What a delegate past the end reads when the bar count drops (a restored
  // or applied config), until the Repeater removes it: no bar, rather than
  // undefined for every binding in OSDBar to guard against
  readonly property var noBar: ({
      "type": "",
      "apps": [],
      "icon": "",
      "showOsd": false
    })

  function _setTile(type, tile) {
    const next = Object.assign({}, root.tiles);
    next[type] = tile;
    root.tiles = next;
  }

  function _register(source, add) {
    const sources = Object.assign({}, root._sources);
    if (add)
      sources[source.type] = source;
    else if (sources[source.type] === source)
      delete sources[source.type];
    root._sources = sources;
  }

  // A change of a bar or status type may open the OSD: not one the
  // pointer made in axiom's own bar or panels (ShellManager.fromScreen),
  // unless OSD.onScreenChanges. It still updates an open OSD
  function opensFor(type) {
    return OSDConfig.onScreenChanges || !ShellManager.fromScreen(type);
  }

  // An icon clicked: flips it (it stays in place: `_kept`)
  function toggle(type) {
    const source = root._sources[type];
    if (!source)
      return;
    source.toggle();
  }

  function _ring(type) {
    root.changed = type;
    root._changedAt = Date.now();
    root._keepRow();
  }

  // A status changed; `force` opens the OSD. With its card (`withCard`,
  // OSDItems.cardTypes', unless the OSD's cards are off) only the card
  // shows, the icon turning lit quietly (ringed if
  // the icons are out), unless the card out mustn't give way to it
  // (OSDItems.replaces). Without one the icons show, it ringed, unless
  // it's a knock-on of the card's change or of the change ringed
  // (OSDItems.besideCard, replaces); a card it makes stale folds back
  function showStatus(type, force, withCard) {
    // A quiet change with the OSD shut is never seen
    if (!force && !root.hostOpen)
      return;
    const now = Date.now();
    const cardOut = root._open.card === true && root._cardKind === "status";
    if (withCard === true && root.cards) {
      if (root._queued("card", force, {
        "kind": "status",
        "type": type,
        "at": now
      })) {
        root.poked(force);
        return;
      }
      if (cardOut && !OSDItems.replaces(root._cardType, type, now - root._cardAt, root.tiles, true, true))
        return;
      root._cardKind = "status";
      root._cardType = type;
      root._cardAt = now;
      root._openPart("card");
      if (root._open.status === true && type !== "message")
        root._ring(type);
    } else {
      if (root._queued("status", force, {
        "ring": type
      })) {
        root._boxParts("status").forEach(other => root._queued(other, force));
        root.poked(force);
        return;
      }
      if (cardOut) {
        const beside = OSDItems.besideCard(root._cardType, type, now - root._cardAt, root.tiles);
        if (beside === "suppress")
          return;
        if (beside === "retract")
          root._closePart("card");
      }
      if (root._open.status === true && root.changed !== "" && !OSDItems.replaces(root.changed, type, now - root._changedAt, root.tiles, false, false))
        return;
      root._ring(type);
      root._boxParts("status").forEach(other => root._openPart(other));
    }
    root.poked(force);
  }

  // The settings page's Show: the bars and the status icons as they are
  // (every one when none would show)
  function preview() {
    root.changed = "";
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
      readonly property bool rowFlow: root.osd.bars.alongEdge ? !root.edgeVertical : root.vertical
      x: root._farX(levelSlot, grid)
      y: root._farY(levelSlot, grid)
      width: implicitWidth
      height: implicitHeight
      flow: rowFlow ? GridLayout.LeftToRight : GridLayout.TopToBottom
      columnSpacing: root.barSpacing
      rowSpacing: root.barSpacing

      Repeater {
        // By count, so edits to a bar update it in place
        model: root.levelItems.length

        delegate: OSDBar {
          required property int index

          entry: root.levelItems[index] ?? root.noBar
          screenName: root.screenName
          vertical: root.vertical
          showPercent: root.osd.bars.showPercent
          Layout.preferredWidth: root.vertical ? implicitWidth : root.barLength
          Layout.preferredHeight: root.vertical ? root.barLength : implicitHeight
          onPoked: {
            const force = entry.showOsd && root.opensFor(entry.type);
            if (!force && !root.hostOpen)
              return;
            root._openBox("level", force);
            root.poked(force);
          }
        }
      }
    }
  }

  Item {
    id: statusSlot
    readonly property var place: root._place("status")
    visible: statusSlot.place.depth > 0
    clip: true
    x: root._slotX(statusSlot.place)
    y: root._slotY(statusSlot.place)
    width: root.edgeVertical ? statusSlot.place.depth : root.width
    height: root.edgeVertical ? root.height : statusSlot.place.depth

    OSDStatusRow {
      id: row
      x: root._farX(statusSlot, row)
      y: root._farY(statusSlot, row)
      allTypes: root.statusTypes
      types: root.rowTypes
      tiles: root.tiles
      changed: root.changed
      vertical: root.edgeVertical
      toggleable: root.toggleable
      onToggled: type => root.toggle(type)
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

    OSDStatusCard {
      id: statusCard
      visible: root._cardKind === "status"
      x: root._farX(cardSlot, statusCard)
      y: root._farY(cardSlot, statusCard)
      card: root.cardContent ?? ({})

      HoverHandler {
        id: statusCardHover
      }
      // Only a drive's and a screenshot's cards take a click
      // (OSDItems.card's clickable): their source acts on it
      onClicked: {
        const source = root._sources[root._cardType];
        if (source)
          source.activate();
      }
    }

    OSDMediaCard {
      id: mediaCard
      visible: root._cardKind === "media"
      x: root._farX(cardSlot, mediaCard)
      y: root._farY(cardSlot, mediaCard)

      HoverHandler {
        id: mediaCardHover
      }
    }
  }

  // The types watched, as a string: any edit to an OSD parses every OSD
  // anew (OSDConfig.osds), and a new array as the model would rebuild
  // every watcher, deaf while it settles; the string changes only with
  // the types
  // (a message has none: ShellManager.osdMessage brings it)
  readonly property string _watchKey: root.statusTypes.concat(root._cardOnly.filter(type => type !== "message"), root.hasMedia ? ["media"] : []).join(",")

  // The statuses' and the card's watchers (they draw nothing)
  Repeater {
    model: root._watchKey === "" ? [] : root._watchKey.split(",")

    delegate: OSDStatusSource {
      id: watcher
      required property string modelData

      type: watcher.modelData
      mediaOptions: root.osd.cards
      onTileChanged: root._setTile(watcher.type, watcher.tile)
      Component.onCompleted: {
        root._setTile(watcher.type, watcher.tile);
        root._register(watcher, true);
      }
      Component.onDestruction: root._register(watcher, false)
      onFired: card => {
        if (watcher.type === "media") {
          if (!root._queued("card", true, {
            "kind": "media"
          })) {
            root._cardKind = "media";
            root._openPart("card");
          }
          root.poked(true);
        } else {
          root.showStatus(watcher.type, !root.osd.statuses.quiet.includes(watcher.type) && root.opensFor(watcher.type), card);
        }
      }
    }
  }

  Connections {
    target: ShellManager

    function onOsdMessage(id, icon, text, detail, tone) {
      if (id !== root.osd.id)
        return;
      root._setTile("message", OSDItems.tile("message", {
        "icon": icon,
        "text": text,
        "detail": detail,
        "tone": tone
      }));
      // (sent only to an OSD that picks Messages: OSDConfig.messageOsd)
      root.showStatus("message", true, true);
    }

    function onShowOsd(id) {
      if (id === root.osd.id)
        root.preview();
    }
  }
}
