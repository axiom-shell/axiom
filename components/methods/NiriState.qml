pragma Singleton
import QtQuick

// niri's IPC replies and events (NiriManager) as the shapes the rest of the
// shell reads, which don't depend on the compositor
// (docs/dev/compositor/contract.md), as SwayState is for sway.
//
// niri's state is kept as its own objects, updated event by event
// (reduce), and turned into the shapes from there. Its workspaces belong
// to an output and are numbered there from 1 (`idx`); axiom's id for one is
// its output's block base + idx - 1 (`bases`, WorkspaceGeometry.blockBases),
// and a workspace past the block's `size` has none (-1).
QtObject {
  id: root

  // Nothing known yet
  function empty() {
    return {
      "workspaces": ({}),
      "windows": ({}),
      "keyboard": null,
      "configFailed": false
    };
  }

  // The state after one event of niri's event stream ({ "WindowClosed": {
  // "id": 4 } }): the same object for an event it doesn't hold anything of
  function reduce(state, event) {
    const kind = Object.keys(event ?? {})[0] ?? "";
    const e = event?.[kind] ?? {};
    const next = Object.assign({}, state);
    switch (kind) {
    case "WorkspacesChanged":
      next.workspaces = root._byId(e.workspaces);
      return next;
    case "WorkspaceActivated":
      // Only what changes: a workspace left as it was stays the same object
      next.workspaces = root._mapValues(state.workspaces, ws => {
        const changes = {};
        const active = ws.id === e.id ? true : ws.output === state.workspaces[String(e.id)]?.output ? false : ws.is_active;
        if (active !== ws.is_active)
          changes.is_active = active;
        if (e.focused && ws.is_focused !== (ws.id === e.id))
          changes.is_focused = ws.id === e.id;
        return Object.keys(changes).length > 0 ? changes : null;
      });
      return next;
    case "WorkspaceActiveWindowChanged":
      next.workspaces = root._mapValues(state.workspaces, ws => ws.id === e.workspace_id ? {
          "active_window_id": e.active_window_id
        } : null);
      return next;
    case "WorkspaceUrgencyChanged":
      next.workspaces = root._mapValues(state.workspaces, ws => ws.id === e.id ? {
          "is_urgent": e.urgent
        } : null);
      return next;
    case "WindowsChanged":
      next.windows = root._byId(e.windows);
      return next;
    case "WindowOpenedOrChanged":
      {
        const win = e.window;
        next.windows = win.is_focused ? root._mapValues(state.windows, w => w.is_focused ? {
            "is_focused": false
          } : null) : Object.assign({}, state.windows);
        next.windows[String(win.id)] = win;
        return next;
      }
    case "WindowClosed":
      next.windows = Object.assign({}, state.windows);
      delete next.windows[String(e.id)];
      return next;
    case "WindowFocusChanged":
      next.windows = root._mapValues(state.windows, w => w.is_focused !== (w.id === e.id) ? {
          "is_focused": w.id === e.id
        } : null);
      return next;
    case "WindowFocusTimestampChanged":
      next.windows = root._mapValues(state.windows, w => w.id === e.id ? {
          "focus_timestamp": e.focus_timestamp
        } : null);
      return next;
    case "WindowUrgencyChanged":
      next.windows = root._mapValues(state.windows, w => w.id === e.id ? {
          "is_urgent": e.urgent
        } : null);
      return next;
    case "WindowLayoutsChanged":
      {
        const layouts = (e.changes ?? []).reduce((all, change) => {
          all[String(change[0])] = change[1];
          return all;
        }, {});
        next.windows = root._mapValues(state.windows, w => layouts[String(w.id)] ? {
            "layout": layouts[String(w.id)]
          } : null);
        return next;
      }
    case "KeyboardLayoutsChanged":
      next.keyboard = e.keyboard_layouts ?? null;
      return next;
    case "KeyboardLayoutSwitched":
      next.keyboard = state.keyboard ? Object.assign({}, state.keyboard, {
        "current_idx": e.idx
      }) : null;
      return next;
    case "ConfigLoaded":
      next.configFailed = e.failed === true;
      return next;
    }
    return state;
  }

  function _byId(list) {
    return (list ?? []).reduce((all, item) => {
      all[String(item.id)] = item;
      return all;
    }, {});
  }

  // `map` with each value merged with what `changes(value)` returns (null:
  // left as it is)
  function _mapValues(map, changes) {
    const next = {};
    for (const key in map) {
      const change = changes(map[key]);
      next[key] = change ? Object.assign({}, map[key], change) : map[key];
    }
    return next;
  }

  // An output's stable identity (MonitorLayout.outputId): its make, model
  // and serial, those it has
  function description(output) {
    return [output?.make, output?.model, output?.serial].filter(part => part && part !== "Unknown").join(" ");
  }

  // axiom's id for a niri workspace: its output's block base + idx - 1,
  // or -1 past the block (`size` long) or on an output without a base
  function workspaceId(ws, bases, size) {
    const base = bases?.[ws?.output ?? ""];
    const idx = Number(ws?.idx) || 0;
    return base !== undefined && idx >= 1 && idx <= size ? base + idx - 1 : -1;
  }

  // The workspaces with an id of axiom's (workspace())
  function workspaces(state, bases, size) {
    const counts = {};
    for (const key in state.windows) {
      const wsId = state.windows[key].workspace_id;
      counts[wsId] = (counts[wsId] ?? 0) + 1;
    }
    const list = [];
    for (const key in state.workspaces) {
      const ws = root.workspace(state.workspaces[key], bases, size, counts[state.workspaces[key].id] ?? 0);
      if (ws)
        list.push(ws);
    }
    return list.sort((a, b) => a.id - b.id);
  }

  // A workspace, or null for one without an id of axiom's
  function workspace(ws, bases, size, windowCount) {
    const id = root.workspaceId(ws, bases, size);
    if (id < 0)
      return null;
    return {
      "id": id,
      "name": ws.name ?? "",
      "output": ws.output ?? "",
      "windowCount": windowCount ?? 0,
      "active": ws.is_active === true,
      "focused": ws.is_focused === true
    };
  }

  // The focused output's name: the focused workspace's, else ""
  function focusedOutput(state) {
    for (const key in state.workspaces) {
      if (state.workspaces[key].is_focused)
        return state.workspaces[key].output ?? "";
    }
    return "";
  }

  // The focused window's id, or ""
  function focusedWindowId(state) {
    for (const key in state.windows) {
      if (state.windows[key].is_focused)
        return key;
    }
    return "";
  }

  // The enabled outputs of an Outputs reply ({ [name]: output }) as the
  // contract's outputs. niri doesn't say what layer surfaces reserve, so
  // `reserved` is what axiom's own take (`reserved`: { [name]: { top,
  // right, bottom, left } }, from LayerArrange.arrange), 0 elsewhere.
  function outputs(reply, state, bases, size, reserved) {
    const focused = root.focusedOutput(state);
    const active = {};
    for (const key in state.workspaces) {
      const ws = state.workspaces[key];
      if (ws.is_active)
        active[ws.output] = root.workspaceId(ws, bases, size);
    }
    const list = [];
    for (const name in reply ?? {}) {
      const o = reply[name];
      const logical = o.logical;
      if (!logical)
        continue;
      list.push({
        "name": name,
        "description": root.description(o),
        "x": logical.x,
        "y": logical.y,
        "width": logical.width,
        "height": logical.height,
        "scale": logical.scale || 1,
        "focused": name === focused,
        "activeWorkspaceId": active[name] ?? -1,
        "specialWorkspaceId": 0,
        "reserved": reserved?.[name] ?? {
          "top": 0,
          "right": 0,
          "bottom": 0,
          "left": 0
        }
      });
    }
    return list.sort((a, b) => a.x - b.x || a.y - b.y);
  }

  // The windows (the contract's) on the outputs `outputs` (the contract's).
  // niri gives a tiled window's column and its place there, and its size,
  // but not where it is: a strip is laid out from its first column at the
  // output's edge, `gap` apart (the overview squeezes a strip into its cell
  // anyway). A floating window's place is niri's own. A tiled window as
  // big as its output is fullscreen. focusRank follows niri's focus
  // timestamps, the focused window first. A tiled window's `cover` is
  // where it surely is while its workspace shows (supports.windowCover):
  // its column, the output's height, while the strip fits on the output
  // (niri doesn't scroll it then), else the whole output (the strip fills
  // the view).
  function windows(state, outputs, bases, size, gap) {
    const outputOf = name => outputs.find(o => o.name === name) ?? null;
    const raw = [];
    for (const key in state.windows)
      raw.push(state.windows[key]);
    const time = w => w.focus_timestamp ? w.focus_timestamp.secs * 1e9 + w.focus_timestamp.nanos : -1;
    const ranked = raw.slice().sort((a, b) => (b.is_focused - a.is_focused) || time(b) - time(a));
    const lefts = root._columnLefts(raw, gap);
    return raw.map(w => {
      const ws = state.workspaces[String(w.workspace_id)] ?? null;
      const output = outputOf(ws?.output ?? "");
      const layout = w.layout ?? {};
      const place = layout.pos_in_scrolling_layout;
      const tile = layout.tile_size ?? [0, 0];
      const shown = layout.tile_pos_in_workspace_view;
      const ox = output?.x ?? 0;
      const oy = output?.y ?? 0;
      let x = ox;
      let y = oy;
      if (shown) {
        x += shown[0];
        y += shown[1];
      } else if (place) {
        x += lefts[`${w.workspace_id}:${place[0]}`] ?? gap;
        y += root._tileTop(raw, w, gap);
      }
      const win = {
        "id": String(w.id),
        "appId": w.app_id ?? "",
        "initialAppId": w.app_id ?? "",
        "title": w.title ?? "",
        "workspaceId": ws ? root.workspaceId(ws, bases, size) : -1,
        "workspaceName": ws?.name ?? "",
        "output": ws?.output ?? "",
        "floating": w.is_floating === true,
        "fullscreen": !w.is_floating && !!output && Math.abs(tile[0] - output.width) < 1 && Math.abs(tile[1] - output.height) < 1,
        "maximized": false,
        "hidden": false,
        "focusRank": time(w) < 0 && !w.is_focused ? undefined : ranked.indexOf(w),
        "x": x,
        "y": y,
        "w": tile[0],
        "h": tile[1]
      };
      if (place) {
        win.column = place[0];
        win.tile = place[1];
        const left = lefts[`${w.workspace_id}:${place[0]}`] ?? gap;
        const fits = (lefts[`${w.workspace_id}:end`] ?? 0) <= (output?.width ?? 0);
        win.cover = {
          "x": fits ? ox + left : ox,
          "y": oy,
          "w": fits ? root._columnWidth(raw, w) : output?.width ?? 0,
          "h": output?.height ?? 0
        };
      }
      return win;
    });
  }

  // Each column's left edge from its output's ({ "<workspace>:<column>":
  // x }): the columns before it, each as wide as its widest window, `gap`
  // apart. "<workspace>:end" is where the strip ends, past its last gap.
  function _columnLefts(raw, gap) {
    const widths = {};
    for (const w of raw) {
      const place = w.layout?.pos_in_scrolling_layout;
      if (!place)
        continue;
      const ws = String(w.workspace_id);
      widths[ws] = widths[ws] ?? {};
      widths[ws][place[0]] = Math.max(widths[ws][place[0]] ?? 0, w.layout.tile_size?.[0] ?? 0);
    }
    const lefts = {};
    for (const ws in widths) {
      let x = gap;
      const columns = Object.keys(widths[ws]).map(Number).sort((a, b) => a - b);
      for (const column of columns) {
        lefts[`${ws}:${column}`] = x;
        x += widths[ws][column] + gap;
      }
      lefts[`${ws}:end`] = x;
    }
    return lefts;
  }

  // A tiled window's column's width: its widest window's
  function _columnWidth(raw, win) {
    const column = win.layout.pos_in_scrolling_layout[0];
    return raw.filter(w => w.workspace_id === win.workspace_id && w.layout?.pos_in_scrolling_layout?.[0] === column).reduce((width, w) => Math.max(width, w.layout.tile_size?.[0] ?? 0), 0);
  }

  // A tiled window's top edge from its output's: the windows above it in
  // its column, `gap` apart
  function _tileTop(raw, win, gap) {
    const place = win.layout.pos_in_scrolling_layout;
    return raw.filter(w => w.workspace_id === win.workspace_id && w.layout?.pos_in_scrolling_layout?.[0] === place[0] && w.layout.pos_in_scrolling_layout[1] < place[1]).reduce((top, w) => top + (w.layout.tile_size?.[1] ?? 0) + gap, gap);
  }

  // niri's transforms, in Wayland's order (0-7, the Monitors page's)
  readonly property var transforms: ["Normal", "_90", "_180", "_270", "Flipped", "Flipped90", "Flipped180", "Flipped270"]

  // Every output of an Outputs reply in detail, disabled ones too (the
  // Monitors page's shape: CompositorManager.withOutputDetails)
  function outputDetails(reply) {
    const rate = mode => Math.round((mode?.refresh_rate ?? 0) / 10) / 100;
    const list = [];
    for (const name in reply ?? {}) {
      const o = reply[name];
      const mode = o.modes?.[o.current_mode ?? -1] ?? o.modes?.find(m => m.is_preferred) ?? {};
      const logical = o.logical;
      list.push({
        "name": name,
        "description": root.description(o),
        "width": mode.width ?? 0,
        "height": mode.height ?? 0,
        "refreshRate": rate(mode),
        "x": logical?.x ?? 0,
        "y": logical?.y ?? 0,
        "scale": logical?.scale > 0 ? logical.scale : 1,
        "transform": Math.max(0, root.transforms.indexOf(logical?.transform ?? "Normal")),
        "disabled": !logical,
        "mirrorOf": "none",
        "vrr": o.vrr_enabled === true,
        "availableModes": (o.modes ?? []).map(m => `${m.width}x${m.height}@${rate(m).toFixed(2)}Hz`)
      });
    }
    return list.sort((a, b) => a.name.localeCompare(b.name));
  }

  // The keyboard's layouts (KeyboardLayouts.shape), or null before niri
  // said. `codes`: the configured xkb layouts ("us,de")
  function keyboard(state, codes) {
    const names = state.keyboard?.names ?? [];
    return names.length > 0 ? KeyboardLayouts.shape(names, state.keyboard.current_idx, codes) : null;
  }
}
