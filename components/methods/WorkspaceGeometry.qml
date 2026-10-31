pragma Singleton

import QtQuick

// Pure geometry for the workspace overview: a cols×rows board of monitor
// miniatures. Grid coordinates have (0, 0) at the first cell's corner; rects
// are { x, y, w, h } (actions live in CompositorManager).
QtObject {
  id: root

  // The largest scale at which cols×rows monitors of monW×monH, `gap` apart,
  // fit in availW×availH
  function fitScale(availW, availH, monW, monH, gap, cols, rows) {
    if (monW <= 0 || monH <= 0)
      return 0.1;
    const sx = (availW - gap * (cols - 1)) / (monW * cols);
    const sy = (availH - gap * (rows - 1)) / (monH * rows);
    return Math.max(0.01, Math.min(sx, sy));
  }

  function cellRect(index, cellW, cellH, gap, cols) {
    return {
      x: (index % cols) * (cellW + gap),
      y: Math.floor(index / cols) * (cellH + gap),
      w: cellW,
      h: cellH
    };
  }

  // The cell index under a point, or -1 (gaps, outside the board, and the
  // unused end of a last row: `count` cells in all)
  function cellAt(x, y, cellW, cellH, gap, cols, count) {
    const col = Math.floor(x / (cellW + gap));
    const row = Math.floor(y / (cellH + gap));
    if (col < 0 || row < 0 || col >= cols || row * cols + col >= count)
      return -1;
    if (x - col * (cellW + gap) > cellW || y - row * (cellH + gap) > cellH)
      return -1;
    return row * cols + col;
  }

  // A window's rect inside its cell. Windows are in global layout
  // coordinates, so the monitor's origin comes off first.
  function windowRect(win, monitorX, monitorY, scale, cellW, cellH) {
    return _inCell(_scaledRect(win, monitorX, monitorY, scale), cellW, cellH);
  }

  function _scaledRect(win, monitorX, monitorY, scale) {
    return {
      x: ((win?.x ?? 0) - monitorX) * scale,
      y: ((win?.y ?? 0) - monitorY) * scale,
      w: (win?.w ?? 0) * scale,
      h: (win?.h ?? 0) * scale
    };
  }

  // A rect kept inside its cell, at least 8 px each way
  function _inCell(r, cellW, cellH) {
    const w = Math.max(8, Math.min(r.w, cellW));
    const h = Math.max(8, Math.min(r.h, cellH));
    return {
      x: Math.min(Math.max(r.x, 0), cellW - w),
      y: Math.min(Math.max(r.y, 0), cellH - h),
      w: w,
      h: h
    };
  }

  // A strip workspace's tiled windows inside its cell, as
  // windowRect but with the whole strip squeezed along its direction to
  // fit, so columns scrolled off the monitor show too, in order. Rects in
  // the order of `wins`.
  function stripRects(wins, monitorX, monitorY, scale, cellW, cellH, vertical) {
    const rects = wins.map(win => _scaledRect(win, monitorX, monitorY, scale));
    const pos = vertical ? "y" : "x";
    const len = vertical ? "h" : "w";
    const cellLength = vertical ? cellH : cellW;
    const start = Math.min(0, ...rects.map(r => r[pos]));
    const end = Math.max(cellLength, ...rects.map(r => r[pos] + r[len]));
    const k = cellLength / (end - start);
    return rects.map(r => {
      const squeezed = Object.assign({}, r);
      squeezed[pos] = (r[pos] - start) * k;
      squeezed[len] = r[len] * k;
      return _inCell(squeezed, cellW, cellH);
    });
  }

  // A workspace's windows in strip order: tiled ones by
  // their place along the strip (a column's windows across it), floating
  // ones after them
  function stripOrder(wins, vertical) {
    const along = vertical ? "y" : "x";
    const across = vertical ? "x" : "y";
    const place = (win, axis) => win[axis] ?? 0;
    // Where the compositor says which column a window is in, and its place
    // there (niri), that's the order; else it comes from where they are
    const placed = (a, b) => a.column !== undefined && b.column !== undefined;
    const tiled = wins.filter(win => !win.floating).sort((a, b) => placed(a, b) ? a.column - b.column || (a.tile ?? 0) - (b.tile ?? 0) : place(a, along) - place(b, along) || place(a, across) - place(b, across));
    return tiled.concat(wins.filter(win => win.floating));
  }

  function contains(r, x, y) {
    return x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h;
  }

  function _distance(r, x, y) {
    const dx = Math.max(r.x - x, 0, x - (r.x + r.w));
    const dy = Math.max(r.y - y, 0, y - (r.y + r.h));
    return dx * dx + dy * dy;
  }

  // The topmost window under a point: floating windows sit above tiled ones.
  // items: [{ id, floating, rect }] in grid coordinates.
  function windowAt(items, x, y) {
    let tiled = "";
    for (let i = items.length - 1; i >= 0; i--) {
      const item = items[i];
      if (!contains(item.rect, x, y))
        continue;
      if (item.floating)
        return item.id;
      if (tiled === "")
        tiled = item.id;
    }
    return tiled;
  }

  // Where dwindle tiles a window dropped at a point, as Hyprland's
  // placeWindow reproduces it: on the tiled window under the point (else the
  // nearest), side by side when that is wider than tall × multiplier, in the
  // half the point is in. items: that cell's other tiled windows. Returns
  // { id, side, rect: the half } or null for an empty workspace.
  function dropTarget(items, x, y, multiplier) {
    let best = null;
    let bestDistance = -1;
    for (const item of items) {
      const d = _distance(item.rect, x, y);
      if (best === null || d < bestDistance) {
        best = item;
        bestDistance = d;
      }
    }
    if (best === null)
      return null;
    const r = best.rect;
    if (r.w > r.h * multiplier) {
      const first = x < r.x + r.w / 2;
      return {
        id: best.id,
        side: first ? "left" : "right",
        rect: {
          x: first ? r.x : r.x + r.w / 2,
          y: r.y,
          w: r.w / 2,
          h: r.h
        }
      };
    }
    const first = y < r.y + r.h / 2;
    return {
      id: best.id,
      side: first ? "top" : "bottom",
      rect: {
        x: r.x,
        y: first ? r.y : r.y + r.h / 2,
        w: r.w,
        h: r.h / 2
      }
    };
  }

  // Where a tiled window dropped at a point lands on a strip: a new column
  // after the tiled window nearest the point (the scrolling layout opens a
  // window after the focused one, which placeWindow focuses). Returns
  // { id, side, rect: the target's after half } or null.
  function stripDropTarget(items, x, y, vertical) {
    const best = items.reduce((nearest, item) => nearest === null || _distance(item.rect, x, y) < _distance(nearest.rect, x, y) ? item : nearest, null);
    if (best === null)
      return null;
    const r = best.rect;
    return {
      id: best.id,
      side: vertical ? "bottom" : "right",
      rect: vertical ? {
        x: r.x,
        y: r.y + r.h / 2,
        w: r.w,
        h: r.h / 2
      } : {
        x: r.x + r.w / 2,
        y: r.y,
        w: r.w / 2,
        h: r.h
      }
    };
  }

  // The edges a resize grabs from a press: those whose outer third it's in
  // (both near a corner), or the nearest one from the middle.
  function resizeEdges(r, x, y) {
    const edges = {
      left: x < r.x + r.w / 3,
      right: x > r.x + r.w * 2 / 3,
      top: y < r.y + r.h / 3,
      bottom: y > r.y + r.h * 2 / 3
    };
    if (edges.left || edges.right || edges.top || edges.bottom)
      return edges;
    const distances = {
      left: x - r.x,
      right: r.x + r.w - x,
      top: y - r.y,
      bottom: r.y + r.h - y
    };
    const nearest = Object.keys(distances).reduce((a, b) => distances[a] <= distances[b] ? a : b);
    edges[nearest] = true;
    return edges;
  }

  // Stable order for assigning workspace-id blocks to monitors (grid and
  // perMonitor layouts): the primary monitor first (matched by `name`, as
  // General.primaryMonitor is stored/matched elsewhere), then the rest by
  // `key` — a caller-supplied stable identity (CompositorManager fills it with
  // MonitorLayout.outputId, the same "follows the monitor across ports"
  // identity monitor profiles use). The compositor's own order can
  // change on a hotplug/reconnect/restart; `key`/`name` don't, so this can't
  // reshuffle who owns which ids the way raw discovery order did.
  // monitors: [{ name, key, x, y }, ...], any order.
  function orderMonitors(monitors, primaryName) {
    const list = (monitors ?? []).slice();
    const isPrimary = m => !!primaryName && m.name === primaryName;
    const primary = list.filter(isPrimary);
    const rest = list.filter(m => !isPrimary(m));
    rest.sort((a, b) => String(a.key ?? a.name).localeCompare(String(b.key ?? b.name)));
    return primary.concat(rest);
  }

  // Each output's first workspace id ({ [name]: id }) when every output
  // owns a block of `size` ids. Blocks are numbered over every monitor the
  // monitor profiles name (by their rules' `output`; the primary first,
  // matched by connector or by the rule's `label` while unplugged), then the
  // connected ones none names (keyed by MonitorLayout.outputId), each part
  // in orderMonitors' order, so a block never moves with what's connected.
  // outputs: [{ name, description }]; profiles: [{ outputs: [{ output,
  // label }] }] (MonitorsConfig.profiles)
  function blockBases(outputs, primaryName, size, profiles) {
    const list = outputs ?? [];
    const known = [];
    for (const profile of profiles ?? []) {
      for (const rule of profile.outputs ?? []) {
        if (rule.output && !known.some(k => k.key === rule.output))
          known.push({
            "key": rule.output,
            "name": rule.label,
            "connected": ""
          });
      }
    }
    const unknown = [];
    for (const o of list) {
      const k = known.find(k => !k.connected && MonitorLayout.matches(k.key, o));
      if (k) {
        k.connected = o.name;
        k.name = o.name;
      } else
        unknown.push({
          "name": o.name,
          "key": MonitorLayout.outputId(o, list),
          "connected": o.name
        });
    }
    return root.orderMonitors(known, primaryName).concat(root.orderMonitors(unknown, primaryName)).reduce((bases, o, i) => {
      if (o.connected)
        bases[o.connected] = i * size + 1;
      return bases;
    }, {});
  }

  // The output next to output `name` toward `direction` (left, right, up,
  // down): of those whose centre lies that way, the nearest, a step across
  // the direction counting double. "" with none. outputs: [{ name, x, y,
  // width, height }]
  function outputToward(outputs, name, direction) {
    const centre = o => ({
          "x": o.x + o.width / 2,
          "y": o.y + o.height / 2
        });
    const from = (outputs ?? []).find(o => o.name === name);
    if (!from)
      return "";
    const at = centre(from);
    const axis = {
      "left": [-1, 0],
      "right": [1, 0],
      "up": [0, -1],
      "down": [0, 1]
    }[direction];
    if (!axis)
      return "";
    let best = "";
    let bestScore = Infinity;
    for (const o of outputs) {
      const c = centre(o);
      const along = (c.x - at.x) * axis[0] + (c.y - at.y) * axis[1];
      const across = Math.abs((c.x - at.x) * axis[1] + (c.y - at.y) * axis[0]);
      if (o.name === name || along <= 0)
        continue;
      const score = along + 2 * across;
      if (score < bestScore) {
        best = o.name;
        bestScore = score;
      }
    }
    return best;
  }

  // The middle workspace of a `cols` × `rows` grid block whose first id
  // is `base` (ids run along each row, then down the rows): the middle
  // cell, or with an even count the one after the middle (right, down)
  function centreWorkspace(base, cols, rows) {
    return base + Math.floor(Math.max(1, rows) / 2) * Math.max(1, cols) + Math.floor(Math.max(1, cols) / 2);
  }

  // Every monitor to its grid block's centre (centreWorkspace), for a
  // grid's start: remapWorkspaces' { focus, changed } (focus: every
  // monitor, the focused one last, as applyRemap takes it). With
  // `untouched`, only monitors still where the compositor started them
  // go: on their block's first id, or outside their block (one Hyprland
  // numbered on); the rest keep the one they show. monitors: [{ name,
  // block, active, focused }] (remapWorkspaces'); `size` ids a block
  function centreFocus(monitors, size, cols, rows, untouched) {
    const focus = (monitors ?? []).map(m => {
      const base = m.block * size + 1;
      const fresh = m.active === base || m.active < base || m.active >= base + size;
      return {
        "monitor": m.name,
        "id": !untouched || fresh ? root.centreWorkspace(base, cols, rows) : m.active,
        "active": m.active,
        "focused": !!m.focused
      };
    });
    return {
      "focus": focus.filter(f => !f.focused).concat(focus.filter(f => f.focused)).map(f => ({
            "monitor": f.monitor,
            "id": f.id
          })),
      "changed": focus.some(f => f.id !== f.active)
    };
  }

  // Where windows go when the workspace layout changes (CompositorManager's
  // remap): every workspace with windows moves into its own monitor's ids
  // under `to`, at the same place in the block where it can, so its windows
  // stay open and on their monitor. Ids a monitor didn't own under `from`
  // (a workspace stuck on the wrong monitor) keep their id if it's in range,
  // else take a free one. Where two want one id (the shared 1..size of the
  // standard layout, or a smaller block), the first in monitor order keeps
  // it and the rest take free ids; windows only merge when none is free.
  // from/to: { blocks, size } (blocks: each monitor owns `size` ids, else
  // all share 1..size). monitors: [{ name, block, active, focused }] in
  // block order (block: its index from 0, as blockBases numbers them);
  // windows: [{ id, workspace, output }] (workspace an id, output a
  // monitor's name). Returns { moves: [{ id, to }], focus:
  // [{ monitor, id }]
  // (every monitor's mapped active workspace, the focused one last),
  // changed }.
  function remapWorkspaces(monitors, windows, from, to) {
    const base = (layout, i) => layout.blocks ? monitors[i].block * layout.size + 1 : 1;
    const taken = {};
    const target = {};
    const preferred = (i, id) => {
      const lo = base(to, i);
      const index = id - base(from, i);
      if (index >= 0 && index < from.size)
        return index < to.size ? lo + index : -1;
      return id >= lo && id < lo + to.size ? id : -1;
    };
    const free = i => {
      const lo = base(to, i);
      for (let id = lo; id < lo + to.size; id++) {
        if (!taken[id])
          return id;
      }
      return -1;
    };
    // Each monitor's workspaces with windows, in id order
    const occupied = [];
    monitors.forEach((m, i) => {
      const ids = [];
      windows.forEach(w => {
        if (w.output === m.name && w.workspace > 0 && !ids.includes(w.workspace))
          ids.push(w.workspace);
      });
      ids.sort((a, b) => a - b).forEach(id => occupied.push({
          "index": i,
          "id": id
        }));
    });
    const deferred = occupied.filter(o => {
      const id = preferred(o.index, o.id);
      if (id < 0 || taken[id])
        return true;
      taken[id] = true;
      target[o.index + ":" + o.id] = id;
      return false;
    });
    deferred.forEach(o => {
      const lo = base(to, o.index);
      const fallback = preferred(o.index, o.id);
      const id = free(o.index);
      const chosen = id > 0 ? id : (fallback > 0 ? fallback : lo + to.size - 1);
      taken[chosen] = true;
      target[o.index + ":" + o.id] = chosen;
    });
    const moves = windows.filter(w => w.workspace > 0).map(w => {
      const i = monitors.findIndex(m => m.name === w.output);
      return {
        "id": w.id,
        "from": w.workspace,
        "to": target[i + ":" + w.workspace] ?? w.workspace
      };
    }).filter(move => move.to !== move.from).map(move => ({
          "id": move.id,
          "to": move.to
        }));
    const focus = monitors.map((m, i) => {
      let id = target[i + ":" + m.active];
      if (id === undefined) {
        id = preferred(i, m.active);
        if (id < 0 || taken[id])
          id = free(i);
        if (id < 0)
          id = base(to, i);
        taken[id] = true;
      }
      return {
        "monitor": m.name,
        "id": id,
        "active": m.active,
        "focused": !!m.focused
      };
    });
    const changed = moves.length > 0 || focus.some(f => f.id !== f.active);
    return {
      "moves": moves,
      "focus": focus.filter(f => !f.focused).concat(focus.filter(f => f.focused)).map(f => ({
            "monitor": f.monitor,
            "id": f.id
          })),
      "changed": changed
    };
  }
}
