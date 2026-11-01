pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.ui
import qs.services.system
import qs.components.methods
import qs.components.reusable

// One OSD's parts, each shown for its own change and on its own time:
// the bars (a level changed; vertical bars side by side, horizontal bars
// as rows, or along its edge one line parallel to it, end to end when the
// bars run along it too), the status icons (a status changed, the one
// that did ringed), and the card (a status's card, OSDItems.card: an
// audio device switched, a VPN came up, an app started a capture, the
// charger was plugged in, Wi-Fi joined a network, a drive event, a
// message; or the now playing card). They stack out from the edge, the
// longest nearest it (OSDItems.partOrder), each sliding out from under
// the one before as it opens and folding back as its time runs out;
// times ending close together end together (OSDItems.partsDue), the
// outer parts folding in before the OSD slides away. Every part is built
// while the OSD is closed, as its items report their own changes.
Item {
  id: root

  // The OSD's entry (OSDConfig.osds)
  required property var osd
  required property string screenName
  // The edge it slides out of runs vertically
  property bool edgeVertical: false
  // The edge is the bottom or the right one: the parts stack up or left
  property bool edgeAtEnd: false
  // The pointer is on the OSD (its surface or hover strip): every part's
  // time waits, so nothing leaves from under it, and with `holdStill` a
  // part coming in goes past the others
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
  readonly property bool hasMedia: osd.media.enabled

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
  // The icon last clicked: it stays in the row while the OSD stays open,
  // though it turned back to ordinary
  property string _held: ""
  // The status icons shown (what's unusual, every one, or none, and the
  // change)
  readonly property var rowTypes: OSDItems.rowTypes(root.statusTypes, root.tiles, root._previewAll ? "all" : root.osd.statuses.row, root.changed !== "" ? root.changed : root._held)
  // Show on the icons with none to show as they are (nothing unusual):
  // every one, not an empty row, until it closes
  property bool _previewAll: false

  // The OSD shows a status's card (OSDItems.cardTypes): an audio device's
  // as it switches, a VPN's as it comes up, an app's as it starts using
  // the camera or sharing the screen, the battery's as it's plugged in, a
  // network's as Wi-Fi joins it, a drive's (unless its cards are off:
  // then the icons), and a message's always
  readonly property bool cards: root.osd.statuses.cards
  // It may show a message (it lists Messages, or one was sent to it by id)
  readonly property bool _hasMessages: root.statusTypes.includes("message") || root._cardType === "message"
  readonly property bool hasCards: (root.cards && OSDItems.cardTypes.some(type => root.statusTypes.includes(type))) || root._hasMessages
  // What the status card shows (OSDItems.card), its role translated
  // I18n.tr("Output") I18n.tr("Input") I18n.tr("Output and input") I18n.tr("Connected") I18n.tr("Using the camera") I18n.tr("Using the microphone") I18n.tr("Using the camera and microphone") I18n.tr("Sharing the screen") I18n.tr("Stopped using the camera") I18n.tr("Stopped using the microphone") I18n.tr("Stopped sharing the screen") I18n.tr("Charging") I18n.tr("Fully charged") I18n.tr("Plugged in") I18n.tr("Mounted") I18n.tr("Safe to remove") I18n.tr("Unmounted") I18n.tr("Disconnected") I18n.tr("Unplugged without ejecting") I18n.tr("In use: close what's using it") I18n.tr("Couldn't eject") I18n.tr("Encrypted: click to unlock")
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
  // Lengths within this of each other are a tie (OSDItems.partOrder)
  readonly property real snap: Appearance.borderRadius * 2
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
    return part === "card" ? root.osd.statuses.cardTimeout : root.osd.timeout;
  }

  function _folded(part, reveal) {
    if (reveal > 0 || root._open[part] === true || !root._order.includes(part))
      return;
    root._order = root._order.filter(other => other !== part);
    if (part === "status") {
      root.changed = "";
      root._held = "";
      root._previewAll = false;
    }
  }

  function _setOpen(part, open) {
    const next = Object.assign({}, root._open);
    next[part] = open;
    root._open = next;
    const due = Object.assign({}, root._deadlines);
    due[part] = open ? Date.now() + root._timeout(part) : 0;
    root._deadlines = due;
  }

  // Opens a part (or restarts its time), placed by OSDItems.partOrder
  function _openPart(part) {
    cascadeTimer.stop();
    if (!root._order.includes(part)) {
      const lengths = {};
      OSDItems.parts.forEach(other => lengths[other] = root._length(root._item(other)));
      root._order = OSDItems.partOrder(root._order, part, lengths, root.snap, root.osd.holdStill && root.pointerIn && root.hostOpen);
    }
    root._snapping = !root.hostOpen || !root._order.some(other => other !== part && root._reveal(other) > 0);
    root._setOpen(part, true);
    root._snapping = false;
    root._schedule();
  }

  function _closePart(part) {
    if (root._open[part] === true)
      root._setOpen(part, false);
  }

  // The next part's time, unless the pointer holds them
  function _schedule() {
    dueTimer.stop();
    if (root.pointerIn)
      return;
    const next = OSDItems.partsDue(root._deadlines, Date.now(), root.grace).next;
    if (next > 0) {
      dueTimer.interval = Math.max(1, next - Date.now());
      dueTimer.start();
    }
  }

  // Parts' times up: they fold back; the last ones going together close
  // the OSD, the outer ones folding in first
  function _due() {
    const due = OSDItems.partsDue(root._deadlines, Date.now(), root.grace).due;
    const open = root._order.filter(part => root._open[part] === true);
    if (open.length > 0 && open.every(part => due.includes(part))) {
      open.slice(1).forEach(part => root._closePart(part));
      if (open.length > 1)
        cascadeTimer.start();
      else
        root.collapse();
      return;
    }
    due.forEach(part => root._closePart(part));
    root._schedule();
  }

  Timer {
    id: dueTimer
    onTriggered: root._due()
  }

  // The outer parts folding in before the OSD slides away
  Timer {
    id: cascadeTimer
    interval: Appearance.animFast
    onTriggered: root.collapse()
  }

  // The pointer on it holds every part; leaving, each gets its time anew
  onPointerInChanged: {
    if (root.pointerIn) {
      dueTimer.stop();
      return;
    }
    const due = Object.assign({}, root._deadlines);
    root._order.filter(part => root._open[part] === true).forEach(part => due[part] = Date.now() + root._timeout(part));
    root._deadlines = due;
    root._schedule();
  }

  // Open with nothing out (its hover strip, the Show button): the bars,
  // else the icons, else the now playing card. Gone: every part with it
  onHostOpenChanged: {
    if (root.hostOpen) {
      if (!root._order.some(part => root._open[part] === true))
        root._openPart(root.levelItems.length > 0 ? "level" : root.statusTypes.length > 0 || !root.hasMedia ? "status" : "card");
      return;
    }
    dueTimer.stop();
    cascadeTimer.stop();
    root._snapping = true;
    root._open = ({});
    root._deadlines = ({});
    root._order = [];
    root._snapping = false;
    root.changed = "";
    root._held = "";
    root._previewAll = false;
  }

  // ---- Size ----

  // An item's size across the edge, and along it
  function _depth(item) {
    return root.edgeVertical ? item.implicitWidth : item.implicitHeight;
  }
  function _length(item) {
    return root.edgeVertical ? item.implicitHeight : item.implicitWidth;
  }

  readonly property real gap: Widget.spacing * 2
  // Its host's padding inside the outline (EdgePopout.contentPadding):
  // where a part steps in, the gap before it holds the face between them,
  // padded each side as the box is
  property real padding: 0

  // The OSD draws its parts stepped (OSDEntry.shape, attached only)
  readonly property bool _stepShape: root.osd.shape === "stepped" && !root.osd.detached
  // The parts out, and whether each steps in from the one before: a part
  // is drawn as long as the longest from it out (a pyramid, the longest
  // by the edge), and steps in where that's shorter than the one before's
  // by more than `snap`. Judged by their full lengths, so a part's gap
  // doesn't jump as it eases out
  readonly property var _shownParts: root._order.filter(part => root._reveal(part) > 0)
  readonly property var _fullAlong: root._suffixMax(root._shownParts.map(part => root._length(root._item(part))))
  readonly property var _steps: root._shownParts.map((part, i) => root._stepShape && i > 0 && root._fullAlong[i - 1] - root._fullAlong[i] > root.snap)

  function _suffixMax(lengths) {
    const out = lengths.slice();
    for (let i = out.length - 2; i >= 0; i--)
      out[i] = Math.max(out[i], out[i + 1]);
    return out;
  }

  // Each part's place across the edge as it stands (its gap before it,
  // as far as both it and something before it are out), and the whole
  readonly property var _layout: {
    let at = 0;
    let before = 0;
    const out = {};
    root._order.forEach(part => {
      const reveal = root._reveal(part);
      const i = root._shownParts.indexOf(part);
      const gapNow = (i >= 0 && root._steps[i] ? root.padding * 2 : root.gap) * reveal * Math.min(1, before);
      const depth = reveal * root._depth(root._item(part));
      out[part] = {
        "at": at + gapNow,
        "depth": depth
      };
      at += gapNow + depth;
      before += reveal;
    });
    out.total = at;
    return out;
  }
  readonly property real _lengthNow: Math.max(0, ...root._order.map(part => root._reveal(part) * root._length(root._item(part))))

  // The parts' segments for a stepped outline (EdgePopout's `segments`:
  // each one's length and far side): the first as long as the OSD; one
  // stepping in narrows from the one before to its own as it eases out;
  // one that doesn't carries the one before's on. None drawn as one box
  readonly property var segments: {
    if (!root._stepShape)
      return [];
    const out = [];
    root._shownParts.forEach((part, i) => {
      // (while the order and the layout catch up with each other)
      const place = root._layout[part];
      if (!place)
        return;
      let along = root._lengthNow;
      if (out.length > 0) {
        const last = out[out.length - 1].along;
        along = root._steps[i] ? Math.min(last, last + (root._fullAlong[i] - last) * root._reveal(part)) : last;
      }
      out.push({
        "along": along,
        "far": place.at + place.depth
      });
    });
    return out;
  }
  implicitWidth: root.edgeVertical ? root._layout.total : root._lengthNow
  implicitHeight: root.edgeVertical ? root._lengthNow : root._layout.total

  // Its length along the edge for the hover strip: the part it opens on
  // while shut
  readonly property real triggerLength: root._lengthNow > 0 ? root._lengthNow : root._length(root.levelItems.length > 0 ? grid : row)

  // The OSD's largest size across its edge, every part out at once, so
  // its window keeps room for them (EdgePopout.maxContentDepth). The
  // icons' at their largest (OSDStatusRow.maxDepth): they come and go
  readonly property real maxDepth: {
    const parts = [row.maxDepth];
    if (root.levelItems.length > 0)
      parts.push(root._depth(grid));
    const cardDepth = Math.max(root.hasCards ? root._depth(statusCard) : 0, root.hasMedia ? root._depth(mediaCard) : 0);
    if (cardDepth > 0)
      parts.push(cardDepth);
    return parts.reduce((sum, depth) => sum + depth, 0) + (root._stepShape ? Math.max(root.gap, root.padding * 2) : root.gap) * (parts.length - 1);
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

  // An icon clicked: flips it, held in place
  function toggle(type) {
    const source = root._sources[type];
    if (!source)
      return;
    root._held = type;
    source.toggle();
  }

  function _ring(type) {
    root.changed = type;
    root._changedAt = Date.now();
  }

  // A status changed; `force` opens the OSD. With its card (`withCard`,
  // OSDItems.cardTypes', unless the OSD's cards are off; a message's
  // always) only the card shows, the icon turning lit quietly (ringed if
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
    if (withCard === true && (root.cards || OSDItems.alwaysCard(type))) {
      if (cardOut && !OSDItems.replaces(root._cardType, type, now - root._cardAt, root.tiles, true, true))
        return;
      root._cardKind = "status";
      root._cardType = type;
      root._cardAt = now;
      root._openPart("card");
      if (root._open.status === true && type !== "message")
        root._ring(type);
    } else {
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
      root._openPart("status");
    }
    root.poked(force);
  }

  // The settings page's Show: the bars and the status icons as they are
  // (every one when none would show)
  function preview() {
    root.changed = "";
    root._previewAll = OSDItems.rowTypes(root.statusTypes, root.tiles, root.osd.statuses.row, "").length === 0;
    if (root.levelItems.length > 0)
      root._openPart("level");
    if (root.statusTypes.length > 0)
      root._openPart("status");
    if (root.levelItems.length === 0 && root.statusTypes.length === 0 && root.hasMedia) {
      root._cardKind = "media";
      root._openPart("card");
    }
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
  function _farX(slot, item) {
    return root.edgeVertical ? (root.edgeAtEnd ? 0 : slot.width - item.implicitWidth) : (slot.width - item.implicitWidth) / 2;
  }
  function _farY(slot, item) {
    return !root.edgeVertical ? (root.edgeAtEnd ? 0 : slot.height - item.implicitHeight) : (slot.height - item.implicitHeight) / 2;
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
            root._openPart("level");
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
      // Only a drive's card takes a click (OSDItems.card's clickable)
      onClicked: DrivesManager.activate(DrivesManager.lastEvent)
    }

    OSDMediaCard {
      id: mediaCard
      visible: root._cardKind === "media"
      x: root._farX(cardSlot, mediaCard)
      y: root._farY(cardSlot, mediaCard)
    }
  }

  // The types watched, as a string: any edit to an OSD parses every OSD
  // anew (OSDConfig.osds), and a new array as the model would rebuild
  // every watcher, deaf while it settles; the string changes only with
  // the types
  readonly property string _watchKey: root.statusTypes.concat(root.hasMedia ? ["media"] : []).join(",")

  // The statuses' and the card's watchers (they draw nothing)
  Repeater {
    model: root._watchKey === "" ? [] : root._watchKey.split(",")

    delegate: OSDStatusSource {
      id: watcher
      required property string modelData

      type: watcher.modelData
      mediaOptions: root.osd.media
      onTileChanged: root._setTile(watcher.type, watcher.tile)
      Component.onCompleted: {
        root._setTile(watcher.type, watcher.tile);
        root._register(watcher, true);
      }
      Component.onDestruction: root._register(watcher, false)
      onFired: card => {
        if (watcher.type === "media") {
          root._cardKind = "media";
          root._openPart("card");
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
      root.showStatus("message", !root.osd.statuses.quiet.includes("message"), true);
    }

    function onShowOsd(id) {
      if (id === root.osd.id)
        root.preview();
    }
  }
}
