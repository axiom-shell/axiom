pragma Singleton
import QtQuick
import Quickshell.Wayland

import qs.components.methods
import qs.components.methods.layer
import qs.config
import qs.services.core

/**
 * Where axiom's layer-shell windows are on their outputs, worked out by
 * axiom itself on every compositor (methods/layer/LayerArrange; docs/dev/
 * compositor/layer-arrangement.md). Each window that needs to know, or
 * that reserves space others are placed against, states how it asks to
 * be laid out (hosts/window/LayerOrigin, `setLayerSpec`): anchors, margins,
 * size, zone, and when it mapped. Where the compositor can list its layers
 * (Hyprland: CompositorManager.withLayerRects), each window's rect is
 * corrected by how far the compositor's own differs, sampled once they've
 * settled: what axiom doesn't arrange (another app's layers, a monitor's
 * reserved space) moves its windows too. Each difference is logged
 * (console.log, "LayerManager:").
 * It also maps the windows with a fixed place in the stack (bars, the
 * border, docks, integrated edge menus: hosts/window/LayerSlot, `setSlot`)
 * in LayerStack order, one stage at a time, and maps again any that land out
 * of place (the compositor stacks by map order alone, on every compositor).
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
  // size. Kept once per event turn, so a burst of changes (a window resizing
  // on every frame of an animation) reaches one pass, and equal content
  // reaches none.
  property KeptList _keptSpecs: KeptList {
    fresh: root._specs.entries.map((e, i) => Object.assign({
        "id": i
      }, e.value, {
        "seq": root._seqs.get(e.owner)
      })).concat(General.outputs.map(screen => ({
          "id": "output:" + screen.name,
          "width": screen.width,
          "height": screen.height
        })))
    oncePerTurn: true
    onItemsChanged: root._arrange()
  }

  // The arrangement pass: the windows LayerArrange places are every mapped
  // one, and those not yet mapped that reserve nothing (so nothing else
  // moves), where they'd go if they mapped now
  function _arrange() {
    const items = root._keptSpecs.items;
    const outputs = {};
    for (const item of items.filter(i => typeof i.id === "string"))
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
      "ordered": false
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
    if (!same(Array.from(root._answers.keys()), root._slots.entries.map(e => e.owner)))
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

  // Every slot's state, by owner (the LayerSlot): { outputName, layer,
  // namespace, rank, rankGroup, wanted, held, mapped }
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
  // The answer for each slot (owner -> { shown }), read by `slotOf`
  property var _answers: new Map()

  // A slot's state, again whenever it changes
  function setSlot(owner, slot) {
    // A mapped window moved to another layer lands on top of it, as if it
    // had just mapped, where the compositor does that (supports.layerRestack,
    // SwayFX: the blur window rising over a fullscreen window and back)
    const before = root._slots.valueOf(owner);
    const moved = root._restacks && before !== undefined && before.layer !== slot.layer;
    root._slots.set(owner, slot);
    if (slot.mapped && (!root._slotSeqs.has(owner) || moved)) {
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
    root._forget("_answers", owner);
  }

  // What a slot's owner remembers of its map, once it's unmapped
  function _forgetSlot(owner) {
    root._forget("_slotSeqs", owner);
    root._forget("_slotSettled", owner);
    root._forget("_remapping", owner);
  }

  // The service's answer for the slot `owner`: { shown } (whether its window
  // may show now)
  function slotOf(owner) {
    return root._answers.get(owner) ?? {
      "shown": false
    };
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
  // map), kept once per event turn
  property KeptList _keptSlots: KeptList {
    fresh: root._slots.entries.map((e, i) => Object.assign({
        "id": i
      }, e.value, {
        "order": LayerStack.orderOf(e.value.namespace),
        "seq": root._slotSeqs.get(e.owner) ?? 0,
        "showing": root._slotSeqs.has(e.owner),
        "settled": root._slotSettled.get(e.owner) === true,
        "remapping": root._remapping.get(e.owner) === true
      }))
    oncePerTurn: true
    onItemsChanged: root._sequence()
  }

  // The sequence pass: which slots may show now, and which map again
  function _sequence() {
    const items = root._keptSlots.items;
    const owners = root._slots.entries.map(e => e.owner);
    const result = LayerArrange.sequence({
      "entries": items.map(i => ({
            "id": i.id,
            "outputName": i.outputName,
            "layer": i.layer,
            "order": i.order,
            "rank": i.rank,
            "rankGroup": i.rankGroup,
            "wanted": i.wanted,
            "held": i.held,
            "showing": i.showing,
            "mapped": i.settled,
            "seq": i.seq
          })),
      "ordered": false,
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
          "shown": result.show.includes(id)
        }
      ]));
    if (!Utils.deepEqual(Array.from(answers), Array.from(root._answers)))
      root._answers = answers;
  }
}
