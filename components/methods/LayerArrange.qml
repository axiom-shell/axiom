pragma Singleton
import QtQuick

// Where a compositor puts layer-shell surfaces on an output (pure): the
// wlr-layer-shell arrangement that sway, niri and Hyprland share
// (docs/dev/compositor/layer-arrangement.md). Axiom places its popouts,
// joins and blur shapes from this rather than asking the compositor,
// which only Hyprland can answer.
QtObject {
  id: root

  // Arranged first: a surface on a higher layer reserves before any below
  readonly property var layerNames: ["overlay", "top", "bottom", "background"]

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

  // A surface's rect inside `bounds` ({ x, y, w, h }): stretched between
  // the edges it's anchored to on both sides when its size there is 0,
  // else against the edge it's anchored to, else centred; margins push it
  // in from the edges it's anchored to
  function place(surface, bounds) {
    const a = surface.anchors ?? {};
    const m = surface.margins ?? {};
    const ml = m.left ?? 0, mr = m.right ?? 0, mt = m.top ?? 0, mb = m.bottom ?? 0;
    const axis = (start, end, size, from, span, mStart, mEnd) => {
      if (start && end) {
        const room = span - mStart - mEnd;
        const s = size > 0 ? size : room;
        return [from + mStart + Math.floor((room - s) / 2), s];
      }
      if (start)
        return [from + mStart, size];
      if (end)
        return [from + span - size - mEnd, size];
      return [from + Math.floor((span - size) / 2), size];
    };
    const [x, w] = axis(a.left, a.right, surface.w ?? 0, bounds.x, bounds.w, ml, mr);
    const [y, h] = axis(a.top, a.bottom, surface.h ?? 0, bounds.y, bounds.h, mt, mb);
    return {
      "x": x,
      "y": y,
      "w": w,
      "h": h
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
        "w": bounds.w,
        "h": bounds.h - taken
      };
    case "bottom":
      return Object.assign({}, bounds, {
        "h": bounds.h - taken
      });
    case "left":
      return {
        "x": bounds.x + taken,
        "y": bounds.y,
        "w": bounds.w - taken,
        "h": bounds.h
      };
    case "right":
      return Object.assign({}, bounds, {
        "w": bounds.w - taken
      });
    }
    return bounds;
  }

  // The order surfaces on one layer are arranged in: by `order` first
  // (highest first) where the compositor sorts by it (Hyprland's layer
  // rules), then as they mapped (`seq`)
  function sorted(surfaces, ordered) {
    return surfaces.slice().sort((a, b) => (ordered ? (b.order ?? 0) - (a.order ?? 0) : 0) || a.seq - b.seq);
  }

  /**
   * Which of the compositor's own rects (`reported`, HyprState.layerRects'
   * shape) is each of `computed`'s (arrange's result, with `keep(id)`
   * choosing the surfaces to match): within an output and namespace, the
   * pairs nearest in place and size first, each rect taken once.
   * Returns { [id]: { x, y, w, h } } for the surfaces matched.
   */
  function match(computed, reported, keep) {
    const result = {};
    for (const output in computed) {
      const theirs = reported?.[output]?.layers ?? [];
      const pairs = [];
      for (const l of computed[output].layers.filter(l => keep(l.id)))
        theirs.forEach((r, i) => {
          if (r.namespace === l.namespace)
            pairs.push({
              "id": l.id,
              "i": i,
              "cost": Math.abs(r.x - l.x) + Math.abs(r.y - l.y) + Math.abs(r.w - l.w) + Math.abs(r.h - l.h)
            });
        });
      pairs.sort((a, b) => a.cost - b.cost);
      const taken = new Set();
      for (const pair of pairs) {
        if (result[pair.id] !== undefined || taken.has(pair.i))
          continue;
        taken.add(pair.i);
        const r = theirs[pair.i];
        result[pair.id] = {
          "x": r.x,
          "y": r.y,
          "w": r.w,
          "h": r.h
        };
      }
    }
    return result;
  }

  /**
   * Every surface's rect, by output: { [output]: { w, h, layers:
   * [{ id, namespace, x, y, w, h }], reserved: { top, right, bottom,
   * left } } }, output-relative (the shape HyprState.layerRects gives,
   * plus what the reserving surfaces take from each edge). `outputs` maps names to { w, h };
   * `surfaces` are { id, output, namespace, layer (layerNames), order,
   * seq (map order), anchors { left, right, top, bottom }, margins
   * { left, right, top, bottom }, w, h (0 to stretch), zone (> 0
   * reserves where zoneEdge has an edge, 0 keeps out of what others
   * reserve, -1 ignores it) }.
   * Surfaces reserving are arranged first, layer by layer, each taking
   * the room the ones before it left; the rest are placed in what's left
   * at the end (the whole output with zone -1).
   */
  function arrange(outputs, surfaces, ordered) {
    const result = {};
    for (const name in outputs) {
      const out = outputs[name];
      const full = {
        "x": 0,
        "y": 0,
        "w": out.w,
        "h": out.h
      };
      const mine = surfaces.filter(s => s.output === name);
      const byLayer = root.layerNames.map(layer => root.sorted(mine.filter(s => (s.layer ?? "top") === layer), ordered));
      let usable = full;
      const rects = [];
      const add = (s, r) => rects.push(Object.assign({
          "id": s.id,
          "namespace": s.namespace
        }, r));
      for (const layer of byLayer)
        for (const s of layer.filter(s => root.reserves(s))) {
          add(s, root.place(s, usable));
          usable = root._reserve(usable, s);
        }
      for (const layer of byLayer)
        for (const s of layer.filter(s => !root.reserves(s)))
          add(s, root.place(s, s.zone < 0 ? full : usable));
      result[name] = {
        "w": out.w,
        "h": out.h,
        "layers": rects,
        "reserved": {
          "top": usable.y,
          "right": out.w - usable.x - usable.w,
          "bottom": out.h - usable.y - usable.h,
          "left": usable.x
        }
      };
    }
    return result;
  }
}
