pragma Singleton
import QtQuick

// Where a compositor puts layer-shell surfaces on an output, and which of
// the windows axiom maps in order may show (pure): the wlr-layer-shell
// arrangement that sway, niri and Hyprland share
// (docs/dev/compositor/layer-arrangement.md). Axiom places its popouts,
// joins and blur shapes from this rather than asking the compositor,
// which only Hyprland can answer. Each decision is a named rule function
// and its answer carries the rule's name (`rule`); LayerManager alone calls
// `arrange`, `match`, `correctionsOf` and `sequence`, each with one object.
QtObject {
  id: root

  // Arranged first: a surface on a higher layer reserves before any below
  readonly property var layerNames: ["overlay", "top", "bottom", "background"]

  // --- arrange ---

  // The edge a surface reserves its zone on: anchored to it, not to the
  // opposite edge, and to both or neither of the edges beside it; "" when
  // none (a corner, the middle, or stretched across the output)
  function zoneEdge(anchors) {
    const a = anchors ?? {};
    const across = (x, y) => !!x === !!y;
    if (a.top && !a.bottom && across(a.left, a.right))
      return "top";
    if (a.bottom && !a.top && across(a.left, a.right))
      return "bottom";
    if (a.left && !a.right && across(a.top, a.bottom))
      return "left";
    if (a.right && !a.left && across(a.top, a.bottom))
      return "right";
    return "";
  }

  // A surface's rect inside `bounds` ({ x, y, width, height }): stretched
  // between the edges it's anchored to on both sides when its size there is
  // 0, else against the edge it's anchored to, else centred; margins push
  // it in from the edges it's anchored to
  function place(surface, bounds) {
    const a = surface.anchors ?? {};
    const m = surface.margins ?? {};
    const ml = m.left ?? 0, mr = m.right ?? 0, mt = m.top ?? 0, mb = m.bottom ?? 0;
    const axis = (anchored, size, from, span, margin) => {
      if (root.centredWhenUnanchored(anchored))
        return [from + Math.floor((span - size) / 2), size];
      if (anchored.start && anchored.end) {
        const room = span - margin.start - margin.end;
        const s = root.stretchWhenSizeZero(anchored, size) ? room : size;
        return [from + margin.start + Math.floor((room - s) / 2), s];
      }
      if (anchored.start)
        return [from + margin.start, size];
      return [from + span - size - margin.end, size];
    };
    const [x, width] = axis({
      "start": a.left,
      "end": a.right
    }, surface.width ?? 0, bounds.x, bounds.width, {
      "start": ml,
      "end": mr
    });
    const [y, height] = axis({
      "start": a.top,
      "end": a.bottom
    }, surface.height ?? 0, bounds.y, bounds.height, {
      "start": mt,
      "end": mb
    });
    return {
      "x": x,
      "y": y,
      "width": width,
      "height": height
    };
  }

  // Whether a surface reserves a zone: a positive one on an edge it can
  // reserve on (the protocol treats any other positive zone as 0)
  function reserves(surface) {
    return surface.zone > 0 && root.zoneEdge(surface.anchors) !== "";
  }

  // `bounds` less a surface's zone (and its margin on that edge)
  function _reserve(bounds, surface) {
    const edge = root.zoneEdge(surface.anchors);
    const m = surface.margins ?? {};
    const taken = surface.zone + (m[edge] ?? 0);
    switch (edge) {
    case "top":
      return {
        "x": bounds.x,
        "y": bounds.y + taken,
        "width": bounds.width,
        "height": bounds.height - taken
      };
    case "bottom":
      return Object.assign({}, bounds, {
        "height": bounds.height - taken
      });
    case "left":
      return {
        "x": bounds.x + taken,
        "y": bounds.y,
        "width": bounds.width - taken,
        "height": bounds.height
      };
    case "right":
      return Object.assign({}, bounds, {
        "width": bounds.width - taken
      });
    }
    return bounds;
  }

  // The order surfaces on one layer are arranged in: by `order` first
  // (highest first) where the compositor keeps it (`ordered`: Hyprland's
  // layer rules), then as they mapped (`seq`)
  function sorted(surfaces, ordered) {
    return surfaces.slice().sort((a, b) => (ordered ? (b.order ?? 0) - (a.order ?? 0) : 0) || a.seq - b.seq);
  }

  // Rule: reserving surfaces are arranged first, layer by layer
  function reservingFirstByLayer() {
    return "reservingFirstByLayer";
  }

  // Rule: where the compositor keeps the order, surfaces of one layer are
  // arranged by order, then map order
  function orderThenMapOrder() {
    return "orderThenMapOrder";
  }

  // Rule: elsewhere they are arranged in map order
  function mapOrderDecides() {
    return "mapOrderDecides";
  }

  // Rule: a size of 0 between two anchored edges stretches to fill
  // (`anchored` is { start, end }, an axis's two edges)
  function stretchWhenSizeZero(anchored, size) {
    return !!(anchored.start && anchored.end && !(size > 0));
  }

  // Rule: a surface not anchored on an axis is centred on it
  function centredWhenUnanchored(anchored) {
    return !anchored.start && !anchored.end;
  }

  // Rule: zone -1 ignores what others reserve (the whole output)
  function zoneMinusOneIgnoresReserved(surface) {
    return surface.zone < 0;
  }

  // Rule: a positive zone on no edge reserves nothing
  function zoneOnlyOnAnEdge(surface) {
    return surface.zone > 0 && !root.reserves(surface);
  }

  // The rule that decided a surface's place: `surface` (arrange's
  // input), `alone` (no other surface reserves on its layer), `ordered`
  function _arrangeRuleOf(surface, alone, ordered) {
    if (root.zoneMinusOneIgnoresReserved(surface))
      return "zoneMinusOneIgnoresReserved";
    if (root.zoneOnlyOnAnEdge(surface))
      return "zoneOnlyOnAnEdge";
    if (root.reserves(surface))
      return alone ? "reservingFirstByLayer" : root._sortRule(ordered);
    const a = surface.anchors ?? {};
    const across = {
      "start": a.left,
      "end": a.right
    };
    const down = {
      "start": a.top,
      "end": a.bottom
    };
    if (root.stretchWhenSizeZero(across, surface.width) || root.stretchWhenSizeZero(down, surface.height))
      return "stretchWhenSizeZero";
    if (root.centredWhenUnanchored(across) || root.centredWhenUnanchored(down))
      return "centredWhenUnanchored";
    return root._sortRule(ordered);
  }

  // The rule `sorted` follows
  function _sortRule(ordered) {
    return ordered ? root.orderThenMapOrder() : root.mapOrderDecides();
  }

  /**
   * Every surface's rect, by output: { [outputName]: { width, height,
   * layers: [{ id, namespace, x, y, width, height, rule }], reserved:
   * { top, right, bottom, left } } }, output-relative (the shape
   * HyprState.layerRects gives, plus what the reserving surfaces take from
   * each edge, and the rule that decided each). `outputs` maps names to
   * { width, height }; `surfaces` are { id, outputName, namespace, layer
   * (layerNames), order, seq (map order), anchors { left, right, top,
   * bottom }, margins { left, right, top, bottom }, width, height (0 to
   * stretch), zone (> 0 reserves where zoneEdge has an edge, 0 keeps out of
   * what others reserve, -1 ignores it) }; `ordered` is whether the
   * compositor keeps the order (surfaces then sort by `order` first).
   * Surfaces reserving are arranged first, layer by layer, each taking
   * the room the ones before it left; the rest are placed in what's left
   * at the end (the whole output with zone -1).
   */
  function arrange(input) {
    const {
      outputs,
      surfaces,
      ordered
    } = input;
    const result = {};
    for (const name in outputs) {
      const out = outputs[name];
      const full = {
        "x": 0,
        "y": 0,
        "width": out.width,
        "height": out.height
      };
      const mine = surfaces.filter(s => s.outputName === name);
      const byLayer = root.layerNames.map(layer => root.sorted(mine.filter(s => (s.layer ?? "top") === layer), ordered));
      let usable = full;
      const rects = [];
      const add = (s, r, alone) => rects.push(Object.assign({
          "id": s.id,
          "namespace": s.namespace
        }, r, {
          "rule": root._arrangeRuleOf(s, alone, ordered)
        }));
      for (const layer of byLayer) {
        const reserving = layer.filter(s => root.reserves(s));
        for (const s of reserving) {
          add(s, root.place(s, usable), reserving.length === 1);
          usable = root._reserve(usable, s);
        }
      }
      for (const layer of byLayer)
        for (const s of layer.filter(s => !root.reserves(s)))
          add(s, root.place(s, root.zoneMinusOneIgnoresReserved(s) ? full : usable), true);
      result[name] = {
        "width": out.width,
        "height": out.height,
        "layers": rects,
        "reserved": {
          "top": usable.y,
          "right": out.width - usable.x - usable.width,
          "bottom": out.height - usable.y - usable.height,
          "left": usable.x
        }
      };
    }
    return result;
  }

  // --- match ---

  // Rule: within an output and namespace, the pairs nearest in place and
  // size first, each rect of the compositor's taken once
  function nearestPairsFirst(pairs) {
    return pairs.slice().sort((a, b) => a.cost - b.cost);
  }

  /**
   * Which of the compositor's own rects (`reported`, HyprState.layerRects'
   * shape: { [outputName]: { layers: [{ namespace, x, y, w, h }] } }) is
   * each of `computed`'s (arrange's result), among the surfaces in
   * `mappedIds`. Returns { [id]: { x, y, width, height } } for the surfaces
   * matched.
   */
  function match(input) {
    const {
      computed,
      reported,
      mappedIds
    } = input;
    const result = {};
    for (const output in computed) {
      const theirs = reported?.[output]?.layers ?? [];
      const pairs = [];
      for (const l of computed[output].layers.filter(l => mappedIds.includes(l.id)))
        theirs.forEach((r, i) => {
          if (r.namespace === l.namespace)
            pairs.push({
              "id": l.id,
              "i": i,
              "cost": Math.abs(r.x - l.x) + Math.abs(r.y - l.y) + Math.abs(r.w - l.width) + Math.abs(r.h - l.height)
            });
        });
      const taken = new Set();
      for (const pair of root.nearestPairsFirst(pairs)) {
        if (result[pair.id] !== undefined || taken.has(pair.i))
          continue;
        taken.add(pair.i);
        const r = theirs[pair.i];
        result[pair.id] = {
          "x": r.x,
          "y": r.y,
          "width": r.w,
          "height": r.h
        };
      }
    }
    return result;
  }

  // --- correctionsOf ---

  // Rule: a mapped window whose rect differs from the compositor's is
  // corrected by the difference
  function differenceIsCorrection(computed, theirs) {
    return {
      "dx": theirs.x - computed.x,
      "dy": theirs.y - computed.y,
      "dw": theirs.width - computed.width,
      "dh": theirs.height - computed.height,
      "rule": "differenceIsCorrection"
    };
  }

  // Rule: equal again, a window has no correction
  function equalDropsCorrection(computed, theirs) {
    return theirs.x === computed.x && theirs.y === computed.y && theirs.width === computed.width && theirs.height === computed.height;
  }

  // Rule: a window unmapped keeps its last correction (it most likely maps
  // back where it was)
  function keptWhileUnmapped(correction) {
    return Object.assign({}, correction, {
      "rule": "keptWhileUnmapped"
    });
  }

  // Rule: a mapped window the compositor lists no rect for has none
  // (`droppedWhenUnmatched`; the compositor's answer is `theirs`)
  function droppedWhenUnmatched(theirs) {
    return theirs === undefined;
  }

  // Rule: a window that is gone loses its correction
  function goneDropped(id, liveIds) {
    return !liveIds.includes(id);
  }

  /**
   * The corrections of the windows' rects from the compositor's, sampled
   * once they've settled (a window resizing gets there a moment later).
   * `computed` is arrange's result, `reported` the compositor's list (as
   * `match`), `mappedIds` the mapped windows, `liveIds` every window still
   * there, `current` the corrections held now ({ [id]: { dx, dy, dw, dh } }).
   * Returns { corrections: { [id]: { dx, dy, dw, dh, rule } }, misses:
   * [{ namespace, outputName, computed, reported }] } (`misses` are the
   * mapped windows that differ, `reported` null where the compositor lists
   * none).
   */
  function correctionsOf(input) {
    const {
      computed,
      reported,
      mappedIds,
      liveIds,
      current
    } = input;
    const theirs = root.match({
      "computed": computed,
      "reported": reported,
      "mappedIds": mappedIds
    });
    const corrections = Object.assign({}, current);
    const misses = [];
    for (const outputName in computed)
      for (const l of computed[outputName].layers) {
        if (!mappedIds.includes(l.id))
          continue;
        const r = theirs[l.id];
        if (r && root.equalDropsCorrection(l, r)) {
          delete corrections[l.id];
          continue;
        }
        if (root.droppedWhenUnmatched(r))
          delete corrections[l.id];
        else
          corrections[l.id] = root.differenceIsCorrection(l, r);
        misses.push({
          "namespace": l.namespace,
          "outputName": outputName,
          "computed": {
            "x": l.x,
            "y": l.y,
            "width": l.width,
            "height": l.height
          },
          "reported": r ?? null
        });
      }
    for (const id in current) {
      const key = Number(id);
      if (root.goneDropped(key, liveIds))
        delete corrections[id];
      else if (!mappedIds.includes(key))
        corrections[id] = root.keptWhileUnmapped(current[id]);
    }
    return {
      "corrections": corrections,
      "misses": misses
    };
  }

  // --- sequence ---

  // Whether `e` shows, wants a place in the stack: wanted, or held
  function _wants(e) {
    return e.wanted || e.held;
  }

  // The windows of `e`'s output and layer
  function _peersOf(entries, e) {
    return entries.filter(o => o !== e && o.outputName === e.outputName && o.layer === e.layer);
  }

  // `o` belongs before `e`: a higher order, or a lower rank of the same in
  // its rank group (the border's corners after its strips, drawn over their
  // ends; bars stacked on one edge)
  function _before(o, e) {
    return o.order > e.order || (o.order === e.order && (o.rankGroup ?? "") === (e.rankGroup ?? "") && (o.rank ?? 0) < (e.rank ?? 0));
  }

  // Rule: a window shows once every window ordered before it there that
  // wants to show is mapped, so they map highest order first
  function showsAfterPredecessorsMapped(entries, e) {
    return root._peersOf(entries, e).every(o => !root._wants(o) || !root._before(o, e) || o.mapped);
  }

  // Rule: one already showing stays (a window ordered before it starting to
  // show, a backdrop, doesn't take it down)
  function showingStays(e) {
    return e.showing === true;
  }

  // Rule: a mapped window that one ordered before it mapped after is out
  // of place: it maps again, and so lands after it (where the compositor
  // keeps the order, only a peer of its own order counts: their tie is map
  // order)
  function outOfPlaceRemaps(entries, e, ordered) {
    return e.mapped && root._peersOf(entries, e).some(o => o.mapped && root._before(o, e) && o.seq > e.seq && (!ordered || o.order === e.order));
  }

  // Rule: a modal window (an instant action surface) is never mapped again:
  // it is last on the Overlay layer, and a blink would show
  function modalNeverRemaps(e) {
    return e.modal === true;
  }

  // Rule: where the compositor keeps the order, only windows of one order
  // can be out of place
  function orderedOnlyTiesByMapOrder(entries, e, ordered) {
    return ordered && root.outOfPlaceRemaps(entries, e, false) && !root.outOfPlaceRemaps(entries, e, true);
  }

  // Rule: a window that maps again stays hidden until it has unmapped
  function remappingHidden(e, remappingIds) {
    return remappingIds.includes(e.id);
  }

  // Rule: a held window is kept mapped while not wanted, so it keeps its
  // place (its owner draws nothing then)
  function heldStaysMapped(e) {
    return e.held === true && !e.wanted;
  }

  // Rule: of one order, a higher rank (within its rank group) waits for the
  // lower ones: `e` waits on windows of its own order alone
  function rankWithinOrder(entries, e) {
    const waiting = root._peersOf(entries, e).filter(o => root._wants(o) && root._before(o, e) && !o.mapped);
    return waiting.length > 0 && waiting.every(o => o.order === e.order);
  }

  // The rule that decided `e`, "" for a window that wants no place
  function _sequenceRuleOf(entries, e, ordered, remappingIds) {
    if (root.remappingHidden(e, remappingIds))
      return "remappingHidden";
    if (root.modalNeverRemaps(e) && root.outOfPlaceRemaps(entries, e, ordered))
      return "modalNeverRemaps";
    if (root.outOfPlaceRemaps(entries, e, ordered))
      return "outOfPlaceRemaps";
    if (root.orderedOnlyTiesByMapOrder(entries, e, ordered))
      return "orderedOnlyTiesByMapOrder";
    if (root.heldStaysMapped(e))
      return "heldStaysMapped";
    if (!root._wants(e))
      return "";
    if (root.showingStays(e))
      return "showingStays";
    return root.rankWithinOrder(entries, e) ? "rankWithinOrder" : "showsAfterPredecessorsMapped";
  }

  /**
   * Which of the windows axiom maps in order may show now, and which have
   * to map again. `entries`: { id, outputName, layer, order, rank (among
   * windows of one order, lower first: optional, 0), rankGroup, wanted (its
   * owner wants it shown), held (kept mapped even when not wanted), showing
   * (visible now), mapped (shown long enough for the compositor to have
   * mapped it), seq (when it mapped) }; `ordered` is whether the compositor
   * keeps the order; `remappingIds` the windows still unmapping to map
   * again (hidden meanwhile).
   * On each output and layer a window shows once every window ordered
   * before it there that shows is mapped, so they map highest order first.
   * One already showing stays. A mapped window that one ordered before it
   * mapped after is out of place: it maps again (`remap`), and so lands
   * after it. Returns { show: [ids], remap: [ids], rules: { [id]: ruleId } }
   * (`rules` has an entry for each window that wants a place).
   */
  function sequence(input) {
    const {
      entries,
      ordered,
      remappingIds
    } = input;
    const remap = entries.filter(e => !root.modalNeverRemaps(e) && root.outOfPlaceRemaps(entries, e, ordered)).map(e => e.id);
    const show = entries.filter(e => root._wants(e) && !remap.includes(e.id) && !root.remappingHidden(e, remappingIds) && (root.showingStays(e) || root.showsAfterPredecessorsMapped(entries, e))).map(e => e.id);
    const rules = {};
    for (const e of entries) {
      const rule = root._sequenceRuleOf(entries, e, ordered, remappingIds);
      if (rule !== "")
        rules[e.id] = rule;
    }
    return {
      "show": show,
      "remap": remap,
      "rules": rules
    };
  }
}
