pragma Singleton
import QtQuick

// Sway's IPC replies (SwayManager) as the shapes the rest of the shell reads,
// which don't depend on the compositor (docs/dev/compositor/contract.md), as
// HyprState is for Hyprland; and quoting the commands SwayManager sends back.
QtObject {
  id: root

  // A string as one argument of a sway command, arriving as it is from a
  // config file and at runtime alike: bare when it's plain word
  // characters, else each run without a `"` in double quotes and each `"`
  // in single ones. Sway takes unescaped quotes out but keeps a backslash
  // before one, so escaping a quote can't work. (The daemon's copy:
  // render.SwayQuote.)
  function quote(text) {
    const value = String(text ?? "");
    if (/^[A-Za-z0-9_.:+\-\/@~=*]+$/.test(value))
      return value;
    return value.split("\"").map(part => part === "" ? "" : `"${part}"`).join("'\"'") || "\"\"";
  }

  // Sway's output names for Wayland's transforms 0-7
  readonly property var _transforms: ["normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270"]

  // What one get_tree reply holds: { windows (the contract's windows, without
  // focusRank), counts ({ [workspace num]: windows on it }), workspaceRects
  // and outputRects ({ [name]: { x, y, width, height } }), order (window ids
  // in the order sway's focus stacks say they were used, most recent first),
  // focusedId ("" with none) }. Windows in the scratchpad aren't listed; one
  // shown from it is, on the workspace it shows on.
  function tree(reply) {
    const info = {
      "windows": [],
      "counts": {},
      "workspaceRects": {},
      "outputRects": {},
      "order": _focusOrder(reply),
      "focusedId": ""
    };
    for (const output of reply?.nodes ?? []) {
      if (output.name === "__i3")
        continue;
      info.outputRects[output.name] = output.rect;
      for (const ws of output.nodes ?? []) {
        if (ws.type !== "workspace")
          continue;
        info.workspaceRects[ws.name] = ws.rect;
        const before = info.windows.length;
        _walk(ws, {
          "output": output.name,
          "ws": ws,
          "floating": false,
          "hidden": false
        }, info);
        if (ws.num > 0)
          info.counts[ws.num] = (info.counts[ws.num] ?? 0) + info.windows.length - before;
      }
    }
    return info;
  }

  // A view's leaves are its windows (they have a pid; an empty split doesn't)
  function _walk(node, at, info) {
    const tabbed = node.layout === "tabbed" || node.layout === "stacked";
    // The front tab: the most recent of its tiled children (a workspace's
    // focus stack lists its floating windows too)
    const front = (node.focus ?? []).find(id => (node.nodes ?? []).some(child => child.id === id));
    const visit = (child, floating) => {
      const hidden = at.hidden || (tabbed && !floating && child.id !== front);
      if (child.pid !== undefined && child.pid !== null && (child.nodes ?? []).length === 0) {
        info.windows.push(root.window(child, at.ws, at.output, floating || at.floating, hidden));
        if (child.focused)
          info.focusedId = String(child.id);
      } else {
        _walk(child, {
          "output": at.output,
          "ws": at.ws,
          "floating": floating || at.floating,
          "hidden": hidden
        }, info);
      }
    };
    for (const child of node.nodes ?? [])
      visit(child, false);
    for (const child of node.floating_nodes ?? [])
      visit(child, true);
  }

  // Sway keeps a focus stack per container (focus: child ids, most recent
  // first). Following them from the root lists every window by how recently
  // it was used: a truer order than nothing, before any focus event arrives.
  function _focusOrder(node) {
    if (!node)
      return [];
    const children = (node.nodes ?? []).concat(node.floating_nodes ?? []);
    if (children.length === 0)
      return node.pid !== undefined && node.pid !== null ? [String(node.id)] : [];
    const rank = id => {
      const i = (node.focus ?? []).indexOf(id);
      return i < 0 ? Infinity : i;
    };
    const sorted = children.slice().sort((a, b) => rank(a.id) - rank(b.id));
    return [].concat(...sorted.map(child => _focusOrder(child)));
  }

  // A window (a get_tree leaf) on workspace `ws` (its tree node) and output
  // `output` (a name). fullscreen_mode 1 is on its workspace, 2 global: both
  // cover the screen.
  function window(node, ws, output, floating, hidden) {
    const appId = node.app_id ?? node.window_properties?.["class"] ?? "";
    return {
      "id": String(node.id),
      "appId": appId,
      "initialAppId": appId,
      "title": node.name ?? "",
      "workspaceId": ws?.num ?? -1,
      "workspaceName": ws?.name ?? "",
      "output": output ?? "",
      "floating": floating === true,
      "fullscreen": (Number(node.fullscreen_mode) || 0) > 0,
      "maximized": false,
      "hidden": hidden === true,
      "focusRank": undefined,
      "x": node.rect?.x ?? 0,
      "y": node.rect?.y ?? 0,
      "w": node.rect?.width ?? 0,
      "h": node.rect?.height ?? 0
    };
  }

  // The windows with their focusRank: `recent` (ids focused since axiom
  // started, most recent first) ahead of the tree's own order, the focused
  // window first
  function ranked(windows, recent, order, focusedId) {
    const ids = mru([focusedId].concat(recent ?? [], order ?? []).filter(id => id !== ""));
    return windows.map(win => {
      const rank = ids.indexOf(win.id);
      return Object.assign({}, win, {
        "focusRank": rank < 0 ? undefined : rank
      });
    });
  }

  // `ids` with duplicates dropped, keeping each one's first place
  function mru(ids) {
    return ids.filter((id, i) => ids.indexOf(id) === i);
  }

  // `id` put first in `recent`, at most `limit` long
  function touch(recent, id, limit) {
    return [id].concat((recent ?? []).filter(other => other !== id)).slice(0, limit ?? 200);
  }

  // A monitor (Quickshell's I3Monitor, or its fields) as an output. Its
  // reserved space (bars' exclusive zones) is what its active workspace's
  // rect leaves of its own, from the tree (info: tree()), less the gaps at
  // the edges (`gaps`: { top, right, bottom, left }), which sway takes off
  // the workspace too.
  function output(monitor, info, gaps) {
    const ipc = monitor?.lastIpcObject ?? {};
    const name = monitor?.name ?? "";
    const own = info?.outputRects?.[name] ?? {
      "x": monitor?.x ?? 0,
      "y": monitor?.y ?? 0,
      "width": monitor?.width ?? 0,
      "height": monitor?.height ?? 0
    };
    const wsName = monitor?.activeWorkspace?.name ?? ipc.current_workspace ?? "";
    const ws = info?.workspaceRects?.[wsName];
    const description = [ipc.make, ipc.model, ipc.serial].filter(part => part && part !== "Unknown").join(" ");
    return {
      "name": name,
      "description": description,
      "x": monitor?.x ?? 0,
      "y": monitor?.y ?? 0,
      "width": monitor?.width ?? 0,
      "height": monitor?.height ?? 0,
      "scale": monitor?.scale || 1,
      "focused": monitor?.focused === true,
      "activeWorkspaceId": (monitor?.activeWorkspace?.num ?? -1) > 0 ? monitor.activeWorkspace.num : -1,
      "specialWorkspaceId": 0,
      "reserved": ws ? {
        "left": Math.max(0, ws.x - own.x - (gaps?.left ?? 0)),
        "top": Math.max(0, ws.y - own.y - (gaps?.top ?? 0)),
        "right": Math.max(0, own.x + own.width - ws.x - ws.width - (gaps?.right ?? 0)),
        "bottom": Math.max(0, own.y + own.height - ws.y - ws.height - (gaps?.bottom ?? 0))
      } : {
        "left": 0,
        "top": 0,
        "right": 0,
        "bottom": 0
      }
    };
  }

  // A workspace (Quickshell's I3Workspace, or its fields), or null for one
  // with no number (axiom's workspaces are numbers). counts: tree().counts
  function workspace(ws, counts) {
    const num = ws?.num ?? ws?.number ?? -1;
    if (!(num > 0))
      return null;
    return {
      "id": num,
      "name": ws?.name ?? "",
      "output": ws?.monitor?.name ?? "",
      "windowCount": counts?.[num] ?? 0,
      "active": ws?.active === true,
      "focused": ws?.focused === true
    };
  }

  // The main keyboard's layouts from a get_inputs reply
  // (KeyboardLayouts.shape), or null with no keyboard. `codes`: the
  // configured xkb_layout ("us,de").
  function keyboard(inputs, codes) {
    const keyboards = (inputs ?? []).filter(input => input.type === "keyboard" && (input.xkb_layout_names ?? []).length > 0);
    const main = keyboards.find(k => /keyboard/i.test(k.name ?? "")) ?? keyboards[0];
    return main ? KeyboardLayouts.shape(main.xkb_layout_names, main.xkb_active_layout_index ?? 0, codes) : null;
  }

  // What a sway config's text (get_config) sets that axiom follows: { gaps:
  // the gap at each screen edge ({ top, right, bottom, left }: the outer
  // gap plus the inner one, which sway adds at the edges too), layouts (the
  // first xkb_layout, "us,de", or ""), blur (SwayFX's: { enabled, size,
  // passes }), dim (SwayFX's default_dim_inactive, 0–1) }. Only the
  // defaults count, not a `workspace N gaps` override.
  function configInfo(text) {
    const outer = {
      "top": 0,
      "right": 0,
      "bottom": 0,
      "left": 0
    };
    let inner = 0;
    let layouts = "";
    // SwayFX's defaults
    const blur = {
      "enabled": false,
      "size": 5,
      "passes": 2
    };
    let dim = 0;
    for (const raw of String(text ?? "").split("\n")) {
      const line = raw.replace(/#.*/, "").trim();
      const gap = /^gaps\s+(inner|outer|horizontal|vertical|top|right|bottom|left)\s+(-?\d+)/.exec(line);
      if (gap) {
        const value = Number(gap[2]);
        const sides = {
          "outer": ["top", "right", "bottom", "left"],
          "horizontal": ["right", "left"],
          "vertical": ["top", "bottom"]
        }[gap[1]] ?? [gap[1]];
        if (gap[1] === "inner")
          inner = value;
        else
          sides.forEach(side => outer[side] = value);
      }
      const blurLine = /^blur(_radius|_passes)?\s+(\S+)/.exec(line);
      if (blurLine && !blurLine[1])
        blur.enabled = /^(enable|yes|on|true)$/.test(blurLine[2]);
      else if (blurLine)
        blur[blurLine[1] === "_radius" ? "size" : "passes"] = Number(blurLine[2]) || 0;
      const dimLine = /^default_dim_inactive\s+([\d.]+)/.exec(line);
      if (dimLine)
        dim = Math.max(0, Math.min(1, Number(dimLine[1]) || 0));
      const layout = /(?:^|\s)xkb_layout\s+("?)([^"\s]+)\1/.exec(line);
      if (layout && layouts === "")
        layouts = layout[2];
    }
    return {
      "gaps": {
        "top": Math.max(0, outer.top + inner),
        "right": Math.max(0, outer.right + inner),
        "bottom": Math.max(0, outer.bottom + inner),
        "left": Math.max(0, outer.left + inner)
      },
      "layouts": layouts,
      "blur": blur,
      "dim": dim
    };
  }

  // A get_outputs reply as output details (contract.md › Outputs): every
  // output, disabled ones too
  function outputDetails(outputs) {
    const rate = mode => Math.round((mode?.refresh ?? 0) / 10) / 100;
    return (outputs ?? []).map(o => {
      const mode = o.current_mode ?? {};
      const disabled = o.active === false;
      return {
        "name": o.name,
        "description": [o.make, o.model, o.serial].filter(part => part && part !== "Unknown").join(" "),
        "width": mode.width ?? o.rect?.width ?? 0,
        "height": mode.height ?? o.rect?.height ?? 0,
        "refreshRate": rate(mode),
        "x": o.rect?.x ?? 0,
        "y": o.rect?.y ?? 0,
        "scale": disabled ? 1 : (o.scale > 0 ? o.scale : 1),
        "transform": Math.max(0, root._transforms.indexOf(o.transform ?? "normal")),
        "disabled": disabled,
        "mirrorOf": "none",
        "vrr": o.adaptive_sync_status === "enabled",
        "availableModes": (o.modes ?? []).map(m => `${m.width}x${m.height}@${rate(m).toFixed(2)}Hz`)
      };
    });
  }

  // The special group a window's mark puts it in (axiom-special-<name>-<id>:
  // the name is everything up to the last "-"), or "" for another mark
  function specialGroup(mark) {
    const found = /^axiom-special-(.+)-[^-]+$/.exec(String(mark ?? ""));
    return found ? found[1] : "";
  }

  // Of `windows` (the contract's), the ids in special group `name` (marked
  // axiom-special-<name>-…, `marks`: { [id]: [marks] }), and whether to show
  // them on `output`: hide when any is shown there, else show
  function specialToggle(windows, marks, name, output) {
    const ids = Object.keys(marks ?? {}).filter(id => (marks[id] ?? []).some(mark => root.specialGroup(mark) === name));
    const shown = windows.some(win => ids.includes(win.id) && win.output === output);
    return {
      "ids": ids,
      "show": !shown
    };
  }

  // The marks of every window in a get_tree reply: { [id]: [marks] }, for
  // those with any
  function marks(reply) {
    const result = {};
    const walk = node => {
      if ((node.marks ?? []).length > 0 && node.pid !== undefined && node.pid !== null)
        result[String(node.id)] = node.marks;
      for (const child of (node.nodes ?? []).concat(node.floating_nodes ?? []))
        walk(child);
    };
    if (reply)
      walk(reply);
    return result;
  }

  /**
   * The window look sway can only set a window at a time: opacity (sway
   * has no focused/unfocused opacity of its own) and SwayFX's blur,
   * shadows and dimming (their commands without criteria reach only the
   * focused window, and the dim's default only windows opened later).
   * What each of `windows` (the contract's) should have with `focusedId`
   * focused and `effects`, the look's parts (render.Look) as {
   *   opacity  { active, inactive, fullscreen } in percent, or null
   *   blur     true/false (look.blur.windows), or null to leave alone
   *   shadows  true/false, or null to leave alone
   *   dim      0–1, or null
   * }, against `applied` ({ id: { opacity, blur, shadows, dim } } as last
   * set). Returns { lines, applied }: one command list per window that
   * changes, and what's set then. Opacity going off puts every window back
   * to 1 and the dim to `revertDim` (the config's default_dim_inactive);
   * the blur and shadows go back with the reload that turns a part off.
   */
  function windowCommands(windows, focusedId, effects, applied, revertDim) {
    const now = {};
    const lines = [];
    const had = key => Object.values(applied ?? {}).some(set => set?.[key] !== undefined);
    if (!effects?.opacity && had("opacity"))
      lines.push("[all] opacity 1");
    if ((effects?.dim ?? null) === null && had("dim"))
      lines.push(`[all] dim_inactive ${Number(revertDim) || 0}`);
    const toggle = on => on ? "enable" : "disable";
    for (const win of windows ?? []) {
      const want = {};
      if (effects?.opacity) {
        const o = effects.opacity;
        want.opacity = Math.round(win.fullscreen ? o.fullscreen : win.id === focusedId ? o.active : o.inactive) / 100;
      }
      if ((effects?.blur ?? null) !== null)
        want.blur = effects.blur === true;
      if ((effects?.shadows ?? null) !== null)
        want.shadows = effects.shadows === true;
      if ((effects?.dim ?? null) !== null)
        want.dim = Math.round(Number(effects.dim) * 100) / 100;
      const was = applied?.[win.id] ?? {};
      const changes = [];
      if (want.opacity !== undefined && was.opacity !== want.opacity)
        changes.push(`opacity ${want.opacity}`);
      if (want.blur !== undefined && was.blur !== want.blur)
        changes.push(`blur ${toggle(want.blur)}`);
      if (want.shadows !== undefined && was.shadows !== want.shadows)
        changes.push(`shadows ${toggle(want.shadows)}`);
      if (want.dim !== undefined && was.dim !== want.dim)
        changes.push(`dim_inactive ${want.dim}`);
      if (Object.keys(want).length > 0)
        now[win.id] = want;
      if (changes.length > 0)
        lines.push(`[con_id=${Number(win.id)}] ${changes.join(", ")}`);
    }
    return {
      "lines": lines,
      "applied": now
    };
  }
}
