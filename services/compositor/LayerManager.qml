pragma Singleton
import QtQuick
import Quickshell.Wayland

import qs.components.methods
import qs.config

/**
 * Where axiom's layer-shell windows are on their outputs, worked out by
 * axiom itself on every compositor (methods/LayerArrange; docs/dev/
 * compositor/layer-arrangement.md). Each window that needs to know, or
 * that reserves space others are placed against, reports how it asks to
 * be laid out (hosts/popout/LayerOrigin): anchors, margins, size, zone,
 * and when it mapped. Where the compositor can list its layers (Hyprland:
 * CompositorManager.withLayerRects), each window's rect is corrected by
 * how far the compositor's own differs, sampled once they've settled:
 * what axiom doesn't arrange (another app's layers, a monitor's reserved
 * space) moves its windows too. Each difference is logged (console.log,
 * "LayerManager:").
 * It also maps the windows with a fixed place in the stack (bars, the
 * border, docks, integrated edge menus: hosts/popout/LayerSlot) in
 * LayerStack order, one stage at a time, and maps again any that land out
 * of place where the compositor stacks by map order alone.
 */
QtObject {
  id: root

  // { owner uid: spec } as reported; spec: { output, namespace, layer,
  // anchors, margins, w, h, zone, mapped }
  property var _specs: ({})
  property int _lastUid: 0
  property int _lastSeq: 0
  property var _seqs: ({})

  // Whether the compositor stacks and arranges by LayerStack order itself
  readonly property bool _ordered: CompositorManager.supports.layerOrder === true

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

  // Every reported window's rect by output, as LayerArrange.arrange
  // gives it ({ [output]: { w, h, layers: [{ id, namespace, x, y, w, h }] } });
  // replaced only when something moved
  property var rects: ({})

  // A reporting window's id: owners keep it for their lifetime
  function register() {
    return ++root._lastUid;
  }

  // A window's layout, again whenever it changes; null once it's gone
  function report(uid, spec) {
    const specs = Object.assign({}, root._specs);
    const seqs = Object.assign({}, root._seqs);
    if (spec)
      specs[uid] = spec;
    else
      delete specs[uid];
    // Mapped from now on: arranged after everything mapped before it
    if (spec?.mapped && seqs[uid] === undefined)
      seqs[uid] = ++root._lastSeq;
    else if (!spec?.mapped)
      delete seqs[uid];
    root._specs = specs;
    root._seqs = seqs;
    root._arrange.restart();
  }

  // Where window `uid` is on its output ({ x, y, w, h }), or null when
  // it isn't laid out (no output, or reserving space and not mapped):
  // as computed, plus its correction from the compositor's list
  function rectOf(uid, output) {
    const rect = (root.rects[output]?.layers ?? []).find(l => l.id === uid);
    if (!rect)
      return null;
    const c = root._corrections[uid];
    return c ? {
      "x": rect.x + c.dx,
      "y": rect.y + c.dy,
      "w": rect.w + c.dw,
      "h": rect.h + c.dh
    } : rect;
  }

  // The windows LayerArrange places: every mapped one, and those not yet
  // mapped that reserve nothing (so nothing else moves), where they'd go
  // if they mapped now
  function _surfaces() {
    const out = [];
    for (const uid in root._specs) {
      const spec = root._specs[uid];
      const seq = root._seqs[uid];
      if (seq === undefined && LayerArrange.reserves(spec))
        continue;
      out.push(Object.assign({}, spec, {
        "id": Number(uid),
        "order": LayerStack.orderOf(spec.namespace),
        "seq": seq ?? root._lastSeq + 1
      }));
    }
    return out;
  }

  // Coalesces a burst of reports (a window resizing on every frame of an
  // animation) into one arrangement
  property Timer _arrange: Timer {
    interval: 0
    onTriggered: {
      const outputs = General.outputs.reduce((acc, screen) => {
        acc[screen.name] = {
          "w": screen.width,
          "h": screen.height
        };
        return acc;
      }, {});
      const next = LayerArrange.arrange(outputs, root._surfaces(), root._ordered);
      if (JSON.stringify(next) !== JSON.stringify(root.rects)) {
        root.rects = next;
        root._check.restart();
      }
    }
  }
  property Connections _outputs: Connections {
    target: General
    function onOutputsChanged() {
      root._arrange.restart();
    }
  }

  // --- Corrections from the compositor's own list ---

  // { uid: { dx, dy, dw, dh } }: how far the compositor's rect of each
  // mapped window differs from the computed one (LayerArrange.match),
  // sampled only once they've settled (a window resizing gets there a
  // moment later), so a window animating keeps its last one. Kept while a
  // window is unmapped (it most likely maps back where it was), dropped
  // when mapped with no rect of its own reported.
  property var _corrections: ({})
  property string _lastMismatch: ""
  property Timer _check: Timer {
    interval: 600
    onTriggered: CompositorManager.withLayerRects(reported => {
      if (!reported)
        return;
      const mapped = id => root._seqs[id] !== undefined;
      const theirs = LayerArrange.match(root.rects, reported, mapped);
      const corrections = Object.assign({}, root._corrections);
      const misses = [];
      for (const output in root.rects)
        for (const l of root.rects[output].layers) {
          if (!mapped(l.id))
            continue;
          const r = theirs[l.id];
          if (r && r.x === l.x && r.y === l.y && r.w === l.w && r.h === l.h) {
            delete corrections[l.id];
            continue;
          }
          if (r)
            corrections[l.id] = {
              "dx": r.x - l.x,
              "dy": r.y - l.y,
              "dw": r.w - l.w,
              "dh": r.h - l.h
            };
          else
            delete corrections[l.id];
          misses.push(`${l.namespace} on ${output} computed ${l.x},${l.y} ${l.w}x${l.h}; reported ${r ? `${r.x},${r.y} ${r.w}x${r.h}` : "none"}`);
        }
      // Of windows gone, none
      for (const uid in corrections)
        if (root._specs[uid] === undefined)
          delete corrections[uid];
      if (JSON.stringify(corrections) !== JSON.stringify(root._corrections))
        root._corrections = corrections;
      const text = misses.sort().join("\n");
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

  // { slot uid: { output, layer, namespace, wanted, held, mapped } }
  property var _slots: ({})
  property var _slotSeqs: ({})
  // Slots mapped long enough for the compositor to have mapped them
  property var _slotSettled: ({})
  // Slots unmapped to map again in their place, until they've unmapped
  property var _remapping: ({})
  // Slots that may show now ({ uid: true })
  property var shownSlots: ({})

  // A slot's state, again whenever it changes; null once it's gone
  function reportSlot(uid, slot) {
    const slots = Object.assign({}, root._slots);
    if (slot)
      slots[uid] = slot;
    else
      delete slots[uid];
    root._slots = slots;
    if (slot?.mapped && root._slotSeqs[uid] === undefined) {
      root._slotSeqs[uid] = ++root._lastSeq;
      root._settle.restart();
    } else if (!slot?.mapped) {
      delete root._slotSeqs[uid];
      delete root._slotSettled[uid];
      delete root._remapping[uid];
    }
    root._sequence.restart();
  }

  // A window just made visible is created at once but drawn (and mapped)
  // a frame or so later: the next stage waits for that
  property Timer _settle: Timer {
    interval: 50
    onTriggered: {
      for (const uid in root._slotSeqs)
        root._slotSettled[uid] = true;
      root._sequence.restart();
    }
  }

  property Timer _sequence: Timer {
    interval: 0
    onTriggered: {
      const entries = Object.keys(root._slots).map(uid => {
        const slot = root._slots[uid];
        return {
          "id": uid,
          "output": slot.output,
          "layer": slot.layer,
          "order": LayerStack.orderOf(slot.namespace),
          "rank": slot.rank,
          "wanted": slot.wanted,
          "held": slot.held,
          "showing": root._slotSeqs[uid] !== undefined,
          "mapped": root._slotSettled[uid] === true,
          "seq": root._slotSeqs[uid] ?? 0
        };
      });
      const result = LayerStack.sequence(entries, root._ordered);
      for (const uid of result.remap) {
        if (!root._remapping[uid])
          console.log(`LayerManager: mapping ${root._slots[uid].namespace} on ${root._slots[uid].output} again, in its place`);
        root._remapping[uid] = true;
      }
      const shown = result.show.filter(uid => !root._remapping[uid]).reduce((acc, uid) => {
        acc[uid] = true;
        return acc;
      }, {});
      if (JSON.stringify(shown) !== JSON.stringify(root.shownSlots))
        root.shownSlots = shown;
    }
  }
}
