pragma Singleton
import QtQuick
import Quickshell.Wayland

import qs.components.methods
import qs.components.methods.layer
import qs.config
import qs.services.core

/**
 * The layer service: where axiom's layer-shell windows stand, on every
 * compositor (docs/dev/compositor/layer-arrangement.md). A window states
 * its place as intents: its row in LayerStack (layer, order, overFullscreen,
 * modal) and its LayerSlot (wanted, held); this service answers each slot
 * with whether it shows and which layer it is on now (`slotOf`), and each
 * window's rect (`rectOf`). The mechanisms differ by compositor and live in
 * its parts: the backends' `supports` facts (`layerOrder`: the compositor
 * keeps axiom's order itself, as Hyprland does while the daemon's order
 * rules are in; `layerRestack`: a window moved to another layer lands on
 * top of it) and the daemon's writer of the rules; nothing outside this
 * service reads them. Without the rules the windows map one stage at a time
 * in LayerStack order and map again when they land out of place, so the
 * map order is the order: the fallback.
 * Each window that needs to know, or that reserves space others are placed
 * against, states how it asks to be laid out (hosts/window/LayerOrigin,
 * `setLayerSpec`): anchors, margins, size, zone, and when it mapped. Where
 * the compositor can list its layers (Hyprland: CompositorManager.
 * withLayerRects), each window's rect is corrected by how far the
 * compositor's own differs, sampled once they've settled: what axiom doesn't
 * arrange (another app's layers, a monitor's reserved space) moves its
 * windows too. Each difference is logged (console.log, "LayerManager:"),
 * and each layer move too (`LayerManager: … moves from … to …`).
 * The windows with a fixed place in the stack (bars, the border, docks,
 * integrated edge menus, the overlay, the popouts, the prompts:
 * hosts/window/LayerSlot, `setSlot`) are mapped in LayerStack order, one
 * stage at a time.
 * The owners of both are the host items themselves; a pass takes its input
 * as plain data (a KeptList of entries by index, never an item) and gives
 * each owner its answer back through the same indexes, and again when only
 * the owners changed (`_followOwners`).
 */
QtObject {
  id: root

  // Every window's layout request, by owner (the LayerOrigin): the spec is
  // { outputName, namespace, layer, anchors, margins, width, height, zone,
  // mapped }
  property OwnerRegistry _specs: OwnerRegistry {
    onEntriesChanged: Qt.callLater(root._followOwners)
  }
  property int _lastSeq: 0
  // Each mapped window's map sequence number, by owner (dropped as it unmaps,
  // so a remap goes to the end)
  property var _seqs: new Map()

  readonly property bool _restacks: CompositorManager.supports.layerRestack === true
  // The compositor keeps axiom's order itself (Hyprland, its rules in)
  readonly property bool _ordered: CompositorManager.supports.layerOrder === true
  // A window moved to another layer keeps its place in the order: the
  // compositor orders by itself, or never lands a moved window on top
  readonly property bool _movesKeepPlace: root._ordered || !root._restacks
  on_OrderedChanged: {
    console.log(root._ordered ? "LayerManager: the compositor keeps the order (rules in)" : "LayerManager: map order (rules not in)");
  }

  // A WlrLayershell.layer as LayerArrange.layerNames names it
  function layerName(layer) {
    switch (layer) {
    case WlrLayer.Overlay:
      return "overlay";
    case WlrLayer.Bottom:
      return "bottom";
    case WlrLayer.Background:
      return "background";
    }
    return "top";
  }

  // A layer name as a WlrLayershell.layer
  function wlrLayerOf(name) {
    switch (name) {
    case "overlay":
      return WlrLayer.Overlay;
    case "bottom":
      return WlrLayer.Bottom;
    case "background":
      return WlrLayer.Background;
    }
    return WlrLayer.Top;
  }

  // Every window's rect by output, as LayerArrange.arrange gives it
  // ({ [outputName]: { width, height, layers: [{ id, namespace, x, y, width,
  // height, rule }], reserved: { top, right, bottom, left } } }, a layer's
  // id the index of its owner in `_arrangedOwners`); replaced only when
  // something moved
  property var rects: ({})
  // The owners the pass that made `rects` gave its ids to (id = index)
  property var _arrangedOwners: []

  // A window's layout, again whenever it changes
  function setLayerSpec(owner, spec) {
    root._specs.set(owner, spec);
    // Mapped from now on: arranged after everything mapped before it
    if (spec.mapped && !root._seqs.has(owner))
      root._seqs = Utils.withEntry(root._seqs, owner, ++root._lastSeq);
    else if (!spec.mapped)
      root._forget("_seqs", owner);
  }

  // A window that's gone
  function dropLayerSpec(owner) {
    root._specs.drop(owner);
    root._forget("_seqs", owner);
    root._forget("_corrections", owner);
  }

  // The per-owner memory `name` (a Map) without `owner`, reassigned whole
  // only when it held it
  function _forget(name, owner) {
    if (!root[name].has(owner))
      return;
    root[name] = Utils.withEntry(root[name], owner, undefined);
  }

  // Where window `owner` is on its output ({ x, y, width, height }), or null
  // when it isn't laid out (no output, or reserving space and not mapped): as
  // computed, plus its correction from the compositor's list
  function rectOf(owner) {
    const id = root._arrangedOwners.indexOf(owner);
    if (id < 0)
      return null;
    for (const name in root.rects) {
      const rect = root.rects[name].layers.find(l => l.id === id);
      if (!rect)
        continue;
      const c = root._corrections.get(owner);
      return c ? {
        "x": rect.x + c.dx,
        "y": rect.y + c.dy,
        "width": rect.width + c.dw,
        "height": rect.height + c.dh
      } : {
        "x": rect.x,
        "y": rect.y,
        "width": rect.width,
        "height": rect.height
      };
    }
    return null;
  }

  // The arrangement's whole input as plain data: each spec by its index in
  // `_specs` (with the owner's seq, none while unmapped), and each output's
  // size beside the compositor's order. Kept once per event turn, so a burst
  // of changes (a window resizing on every frame of an animation) reaches one
  // pass, and equal content reaches none.
  property KeptList _keptSpecs: KeptList {
    fresh: root._specs.entries.map((e, i) => Object.assign({
        "id": i
      }, e.value, {
        "seq": root._seqs.get(e.owner)
      })).concat(General.outputs.map(screen => ({
          "id": "output:" + screen.name,
          "width": screen.width,
          "height": screen.height
        })), [
      {
        "id": "pass",
        "ordered": root._ordered
      }
    ])
    oncePerTurn: true
    onItemsChanged: root._arrange()
  }

  // The arrangement pass: the windows LayerArrange places are every mapped
  // one, and those not yet mapped that reserve nothing (so nothing else
  // moves), where they'd go if they mapped now
  function _arrange() {
    const items = root._keptSpecs.items;
    const outputs = {};
    for (const item of items.filter(i => typeof i.id === "string" && i.id.startsWith("output:")))
      outputs[item.id.slice("output:".length)] = {
        "width": item.width,
        "height": item.height
      };
    const surfaces = [];
    for (const item of items.filter(i => typeof i.id === "number")) {
      if (item.seq === undefined && LayerArrange.reserves(item))
        continue;
      surfaces.push(Object.assign({}, item, {
        "seq": item.seq ?? root._lastSeq + 1
      }));
    }
    const next = LayerArrange.arrange({
      "outputs": outputs,
      "surfaces": surfaces,
      "ordered": items.find(i => i.id === "pass")?.ordered ?? false
    });
    root._arrangedOwners = root._specs.entries.map(e => e.owner);
    if (JSON.stringify(next) !== JSON.stringify(root.rects)) {
      root.rects = next;
      root._check.restart();
    }
  }

  // Queued on either registry's `entries` change: keeps both lists now (a
  // changed one runs its pass, which takes the owners), then reruns a pass
  // whose owners changed while its plain data did not (a window remade with
  // an equal spec): the same result by index, given to the new owners
  function _followOwners() {
    root._keptSpecs.keep();
    root._keptSlots.keep();
    const same = (a, b) => a.length === b.length && a.every((o, i) => o === b[i]);
    if (!same(root._arrangedOwners, root._specs.entries.map(e => e.owner)))
      root._arrange();
    if (!same(Array.from(root._answers.slots.keys()), root._slots.entries.map(e => e.owner)))
      root._sequence();
  }

  // --- Corrections from the compositor's own list ---

  // owner -> { dx, dy, dw, dh, rule }: how far the compositor's rect of each
  // mapped window differs from the computed one (LayerArrange.correctionsOf),
  // sampled only once they've settled (a window resizing gets there a moment
  // later), so a window animating keeps its last one. Kept while a window is
  // unmapped (it most likely maps back where it was), dropped when mapped with
  // no rect of its own reported.
  property var _corrections: new Map()
  property string _lastMismatch: ""
  property Timer _check: Timer {
    interval: 600
    onTriggered: CompositorManager.withLayerRects(reported => {
      if (!reported)
        return;
      // The ids of `rects` are indexes of the pass that made them
      const owners = root._arrangedOwners;
      const current = {};
      for (const [owner, correction] of root._corrections)
        if (owners.includes(owner))
          current[owners.indexOf(owner)] = correction;
      const result = LayerArrange.correctionsOf({
        "computed": root.rects,
        "reported": reported,
        "mappedIds": owners.map((o, i) => i).filter(i => root._seqs.has(owners[i])),
        "liveIds": owners.map((o, i) => i).filter(i => root._specs.valueOf(owners[i]) !== undefined),
        "current": current
      });
      const corrections = new Map();
      for (const id in result.corrections)
        corrections.set(owners[Number(id)], result.corrections[id]);
      if (!Utils.deepEqual(Array.from(corrections), Array.from(root._corrections)))
        root._corrections = corrections;
      const rectText = r => `${r.x},${r.y} ${r.width}x${r.height}`;
      const text = result.misses.map(m => `${m.namespace} on ${m.outputName} computed ${rectText(m.computed)}; reported ${m.reported ? rectText(m.reported) : "none"}`).sort().join("\n");
      if (text !== root._lastMismatch && text !== "")
        console.log("LayerManager: corrected from the compositor:\n" + text);
      root._lastMismatch = text;
    })
  }
  property Connections _layerEvents: Connections {
    target: CompositorManager
    function onLayersChanged() {
      root._check.restart();
    }
  }

  // --- Mapping in order (LayerSlot) ---

  // Every slot's state, by owner (the LayerSlot): { outputName, namespace,
  // rank, rankGroup, wanted, held, mapped }
  property OwnerRegistry _slots: OwnerRegistry {
    onEntriesChanged: Qt.callLater(root._followOwners)
  }
  // Each mapped slot's map sequence number, by owner
  property var _slotSeqs: new Map()
  // Slots mapped long enough for the compositor to have mapped them (owner ->
  // true)
  property var _slotSettled: new Map()
  // Slots unmapped to map again in their place, until they've unmapped
  // (owner -> true)
  property var _remapping: new Map()
  // The pass's answers, published in one assignment (so a reader sees the
  // layers and the fullscreen state of one pass, never one of each): `slots`
  // (owner -> { shown, layer }), read by `slotOf` and, as the previous
  // pass's, by the next for `underModal`; `fullscreen` (output name -> a
  // fullscreen window is on it), read by `hasFullscreen`
  property var _answers: ({
      "slots": new Map(),
      "fullscreen": new Map()
    })

  // A slot's state, again whenever it changes
  function setSlot(owner, slot) {
    root._slots.set(owner, slot);
    if (slot.mapped && !root._slotSeqs.has(owner)) {
      root._slotSeqs = Utils.withEntry(root._slotSeqs, owner, ++root._lastSeq);
      root._settle.restart();
    } else if (!slot.mapped) {
      root._forgetSlot(owner);
    }
  }

  // A slot that's gone
  function dropSlot(owner) {
    root._slots.drop(owner);
    root._forgetSlot(owner);
    if (root._answers.slots.has(owner))
      root._answers = {
        "slots": Utils.withEntry(root._answers.slots, owner, undefined),
        "fullscreen": root._answers.fullscreen
      };
  }

  // What a slot's owner remembers of its map, once it's unmapped
  function _forgetSlot(owner) {
    root._forget("_slotSeqs", owner);
    root._forget("_slotSettled", owner);
    root._forget("_remapping", owner);
  }

  // The service's answer for the slot `owner`: { shown, layer } (whether its
  // window may show now, and the layer it is on, a name); not answered yet:
  // not shown, on its row's layer
  function slotOf(owner) {
    return root._answers.slots.get(owner) ?? {
      "shown": false,
      "layer": root._rowLayer(root._slots.valueOf(owner)?.namespace ?? "")
    };
  }

  // The layer its row names (its answer with no fullscreen window, not wanted, no modal)
  function _rowLayer(namespace) {
    return LayerStack.layerOf(namespace, {
      "fullscreen": false,
      "wanted": false,
      "movesKeepPlace": true,
      "underModal": ""
    });
  }

  // The answer ({ shown, layer }) for the window of `namespace` on
  // `outputName`, null with none or none yet; for a namespace with one window
  // per output (the backing window). `layer` is the same for every window of
  // a namespace there (one row); `shown` is that window's own
  function slotOn(outputName, namespace) {
    const entry = root._slots.entries.find(e => e.value.outputName === outputName && e.value.namespace === namespace);
    return entry ? root._answers.slots.get(entry.owner) ?? null : null;
  }

  // The layer, a name, that the window of `namespace` on `outputName` is on
  // now, "" with none (a namespace of several windows has one row, so one
  // layer there)
  function layerOn(outputName, namespace) {
    return root.slotOn(outputName, namespace)?.layer ?? "";
  }

  // Whether a fullscreen window is on that output, as the layer pass that
  // answers `slotOf`/`layerOn` saw it, published with them (BlurManager reads
  // this one, never CompositorManager's, so a surface's handover and the
  // backing window's move happen in one turn)
  function hasFullscreen(outputName) {
    return root._answers.fullscreen.get(outputName) ?? false;
  }

  // A window just made visible is created at once but drawn (and mapped)
  // a frame or so later: the next stage waits for that
  property Timer _settle: Timer {
    interval: 50
    onTriggered: {
      const next = new Map(root._slotSettled);
      for (const owner of root._slotSeqs.keys())
        next.set(owner, true);
      if (next.size !== root._slotSettled.size)
        root._slotSettled = next;
    }
  }

  // The sequence pass's whole input as plain data: each slot by its index in
  // `_slots` (with its order, its map sequence and what it remembers of its
  // map), each output's fullscreen state, and the compositor's answers that
  // decide the layers; kept once per event turn, so a fullscreen change, a
  // settle, a remap mark or the rules' answer reruns the pass
  property KeptList _keptSlots: KeptList {
    fresh: root._slots.entries.map((e, i) => Object.assign({
        "id": i
      }, e.value, {
        "order": LayerStack.orderOf(e.value.namespace),
        "seq": root._slotSeqs.get(e.owner) ?? 0,
        "showing": root._slotSeqs.has(e.owner),
        "settled": root._slotSettled.get(e.owner) === true,
        "remapping": root._remapping.get(e.owner) === true
      })).concat(General.outputs.map(screen => ({
          "id": "output:" + screen.name,
          "fullscreen": CompositorManager.hasFullscreen(screen.name)
        })), [
      {
        "id": "pass",
        "ordered": root._ordered,
        "movesKeepPlace": root._movesKeepPlace
      }
    ])
    oncePerTurn: true
    onItemsChanged: root._sequence()
  }

  // The sequence pass: each slot's layer now (LayerStack.layerOf), which
  // slots may show, and which map again. A slot that keeps its layer while a
  // modal shows on its output (`underModal`, from its previous answer) goes
  // on keeping it.
  function _sequence() {
    const all = root._keptSlots.items;
    const pass = all.find(i => i.id === "pass");
    const items = all.filter(i => typeof i.id === "number");
    const owners = root._slots.entries.map(e => e.owner);
    const modalOutputs = new Set(items.filter(i => i.showing && LayerStack.isModal(i.namespace)).map(i => i.outputName));
    const moves = new Set();
    const entries = items.map(i => {
      const before = root._answers.slots.get(owners[i.id])?.layer;
      const state = {
        "fullscreen": all.find(o => o.id === "output:" + i.outputName)?.fullscreen ?? false,
        "wanted": i.wanted,
        "movesKeepPlace": pass?.movesKeepPlace ?? true,
        "underModal": modalOutputs.has(i.outputName) ? before ?? "" : ""
      };
      // "": not shown now (hiddenUnderFullscreen); the slot keeps its row's layer
      const answer = LayerStack.layerOf(i.namespace, state);
      const hidden = answer === "";
      const layer = hidden ? root._rowLayer(i.namespace) : answer;
      if (before !== undefined && before !== layer)
        moves.add(`LayerManager: ${i.namespace} on ${i.outputName} moves from ${before} to ${layer}`);
      // A mapped window moved to another layer lands on top of it, as if it
      // had just mapped, where a move lands on top (not movesKeepPlace;
      // supports.layerRestack, SwayFX: the blur window rising over a
      // fullscreen window and back)
      const moved = !pass?.movesKeepPlace && i.showing && before !== undefined && before !== layer;
      if (moved) {
        root._slotSeqs = Utils.withEntry(root._slotSeqs, owners[i.id], ++root._lastSeq);
        root._forget("_slotSettled", owners[i.id]);
        root._settle.restart();
      }
      return {
        "id": i.id,
        "outputName": i.outputName,
        "layer": layer,
        "order": i.order,
        "rank": i.rank,
        "rankGroup": i.rankGroup,
        "wanted": hidden ? false : i.wanted,
        "held": hidden ? false : i.held,
        "showing": i.showing,
        "mapped": moved ? false : i.settled,
        "seq": moved ? root._slotSeqs.get(owners[i.id]) : i.seq,
        "modal": LayerStack.isModal(i.namespace)
      };
    });
    for (const line of moves)
      console.log(line);
    const result = LayerArrange.sequence({
      "entries": entries,
      "ordered": pass?.ordered ?? false,
      "remappingIds": items.filter(i => i.remapping).map(i => i.id)
    });
    const remapping = new Map(root._remapping);
    for (const id of result.remap) {
      const owner = owners[id];
      if (!remapping.get(owner))
        console.log(`LayerManager: mapping ${items[id].namespace} on ${items[id].outputName} again, in its place`);
      remapping.set(owner, true);
    }
    if (remapping.size !== root._remapping.size)
      root._remapping = remapping;
    const answers = new Map(owners.map((owner, id) => [owner,
        {
          "shown": result.show.includes(id),
          "layer": entries[id].layer
        }
      ]));
    const fullscreen = new Map(all.filter(i => typeof i.id === "string" && i.id.startsWith("output:")).map(i => [i.id.slice("output:".length), i.fullscreen]));
    if (!Utils.deepEqual(Array.from(answers), Array.from(root._answers.slots)) || !Utils.deepEqual(Array.from(fullscreen), Array.from(root._answers.fullscreen)))
      root._answers = {
        "slots": answers,
        "fullscreen": fullscreen
      };
  }
}
