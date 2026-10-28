pragma Singleton

import QtQuick

// Pure helpers for the Monitors page (MonitorManager): modes, scales,
// rotation, the layout's rects and snapping, and picking the profile for
// the connected outputs. A monitor is an entry of `hyprctl monitors all -j`;
// a rule is a Monitors.items profile output (the MonitorRule schema);
// rects are { x, y, width, height } in layout (logical) pixels.
QtObject {
  id: root

  // --- Modes ---

  // "3440x1440@240.00Hz", "3440x1440@240" or "3440x1440" as
  // { width, height, rate } (rate 0 when absent), or null
  function parseMode(mode) {
    const match = /^(\d+)x(\d+)(?:@([\d.]+)(?:Hz)?)?$/.exec(String(mode ?? "").trim());
    if (!match)
      return null;
    return {
      "width": Number(match[1]),
      "height": Number(match[2]),
      "rate": match[3] ? Number(match[3]) : 0
    };
  }

  // A rate as Hyprland takes it: at most two decimals, none when whole
  function formatRate(rate) {
    return String(Math.round(rate * 100) / 100);
  }

  function formatMode(width, height, rate) {
    return `${width}x${height}` + (rate > 0 ? "@" + formatRate(rate) : "");
  }

  // availableModes as resolutions, largest first, each with its rates
  // (highest first, duplicates dropped): [{ width, height, rates: [...] }]
  function parseModes(availableModes) {
    const byResolution = {};
    const order = [];
    for (const text of availableModes ?? []) {
      const mode = parseMode(text);
      if (!mode)
        continue;
      const key = `${mode.width}x${mode.height}`;
      if (!byResolution[key]) {
        byResolution[key] = {
          "width": mode.width,
          "height": mode.height,
          "rates": []
        };
        order.push(key);
      }
      const rate = Number(formatRate(mode.rate));
      if (!byResolution[key].rates.includes(rate))
        byResolution[key].rates.push(rate);
    }
    const list = order.map(key => byResolution[key]);
    list.forEach(entry => entry.rates.sort((a, b) => b - a));
    return list.sort((a, b) => b.width * b.height - a.width * a.height || b.width - a.width);
  }

  // --- Scale and rotation ---

  // Scales that give a whole logical size (Hyprland rounds others to the
  // nearest that does, in 1/120 steps), from 0.5 to 3, plus `keep`
  function validScales(width, height, keep) {
    const result = [];
    const whole = v => Math.abs(v - Math.round(v)) < 0.001;
    for (let step = 60; step <= 360; step++) {
      const scale = step / 120;
      if (whole(width / scale) && whole(height / scale))
        result.push(Math.round(scale * 10000) / 10000);
    }
    if (keep !== undefined && keep > 0 && !result.some(scale => Math.abs(scale - keep) < 0.0001))
      result.push(keep);
    return result.sort((a, b) => a - b);
  }

  // Transforms 1, 3, 5 and 7 turn the output a quarter
  function isSideways(transform) {
    return transform % 2 === 1;
  }

  // The size an output takes in the layout: its mode, turned, over its scale
  function logicalSize(width, height, scale, transform) {
    const s = scale > 0 ? scale : 1;
    const w = Math.round(width / s);
    const h = Math.round(height / s);
    return isSideways(transform) ? {
      "width": h,
      "height": w
    } : {
      "width": w,
      "height": h
    };
  }

  // --- The layout ---

  // A rect's snapped position against `others`: each axis moves to the
  // nearest line within `threshold` (edge to edge, or aligned start, end or
  // centre), else stays. { x, y, guides: [{ axis: "x"|"y", at }] }, the
  // guides being the lines it snapped to.
  function snap(rect, others, threshold) {
    const axis = (pos, size, otherPos, otherSize) => {
      let best = null;
      for (const other of others) {
        const start = other[otherPos];
        const end = start + other[otherSize];
        const candidates = [[start, start], [end - rect[size], end], [end, end], [start - rect[size], start], [start + (other[otherSize] - rect[size]) / 2, start + other[otherSize] / 2]];
        for (const [target, line] of candidates) {
          const distance = Math.abs(rect[pos] - target);
          if (distance <= threshold && (best === null || distance < best.distance))
            best = {
              "target": Math.round(target),
              "line": Math.round(line),
              "distance": distance
            };
        }
      }
      return best;
    };
    const bx = axis("x", "width", "x", "width");
    const by = axis("y", "height", "y", "height");
    const guides = [];
    if (bx)
      guides.push({
        "axis": "x",
        "at": bx.line
      });
    if (by)
      guides.push({
        "axis": "y",
        "at": by.line
      });
    return {
      "x": bx ? bx.target : Math.round(rect.x),
      "y": by ? by.target : Math.round(rect.y),
      "guides": guides
    };
  }

  // The box around rects ({ x, y, width, height }); a 1920×1080 one at the
  // origin when there are none
  function bounds(rects) {
    if (rects.length === 0)
      return {
        "x": 0,
        "y": 0,
        "width": 1920,
        "height": 1080
      };
    const x = Math.min(...rects.map(r => r.x));
    const y = Math.min(...rects.map(r => r.y));
    return {
      "x": x,
      "y": y,
      "width": Math.max(...rects.map(r => r.x + r.width)) - x,
      "height": Math.max(...rects.map(r => r.y + r.height)) - y
    };
  }

  function _intersects(a, b) {
    return a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
  }

  // Pairs of indices whose rects overlap (Hyprland would stack them)
  function overlaps(rects) {
    const pairs = [];
    for (let i = 0; i < rects.length; i++)
      for (let j = i + 1; j < rects.length; j++)
        if (_intersects(rects[i], rects[j]))
          pairs.push([i, j]);
    return pairs;
  }

  // Whether two rects share a stretch of edge (the cursor can cross it)
  function _touches(a, b) {
    const spanX = Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x);
    const spanY = Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y);
    const sideBySide = (a.x + a.width === b.x || b.x + b.width === a.x) && spanY > 0;
    const stacked = (a.y + a.height === b.y || b.y + b.height === a.y) && spanX > 0;
    return sideBySide || stacked || _intersects(a, b);
  }

  // Indices of rects the cursor can't reach from the first one
  function islands(rects) {
    if (rects.length < 2)
      return [];
    const reached = [0];
    for (let i = 0; i < reached.length; i++)
      for (let j = 0; j < rects.length; j++)
        if (!reached.includes(j) && _touches(rects[reached[i]], rects[j]))
          reached.push(j);
    return rects.map((_, i) => i).filter(i => !reached.includes(i));
  }

  // --- Outputs and profiles ---

  // The rule `output` for a monitor: its description, which follows it to
  // another port, unless another connected monitor has the same one
  function outputId(monitor, all) {
    const description = String(monitor?.description ?? "").trim();
    const shared = (all ?? []).filter(other => String(other?.description ?? "").trim() === description).length > 1;
    return description !== "" && !shared ? "desc:" + description : monitor.name;
  }

  function matches(output, monitor) {
    if (String(output).startsWith("desc:"))
      return String(monitor?.description ?? "").trim() === output.slice(5).trim();
    return monitor?.name === output;
  }

  // The connected monitor a rule's `output` names, or null
  function find(output, monitors) {
    return (monitors ?? []).find(monitor => matches(output, monitor)) ?? null;
  }

  // The profile for the connected monitors (enabled ones: what Hyprland's
  // Lua sees, so it picks the same one): one listing exactly them wins (a
  // disabled output it lists may be missing), else the one that turns on
  // most of them; -1 when none turns any on. Ties go to the earlier profile.
  // The greeter's Hyprland Lua does the same (render.MonitorsLua).
  function matchProfile(profiles, monitors) {
    let best = -1;
    let bestScore = 0;
    (profiles ?? []).forEach((profile, index) => {
      const outputs = profile?.outputs ?? [];
      let score = 0;
      let exact = true;
      for (const rule of outputs) {
        const found = find(rule.output, monitors) !== null;
        if (found && !rule.disabled)
          score++;
        if (!found && !rule.disabled)
          exact = false;
      }
      for (const monitor of monitors ?? [])
        if (!outputs.some(rule => matches(rule.output, monitor)))
          exact = false;
      if (exact && score > 0)
        score += 1000;
      if (score > bestScore) {
        best = index;
        bestScore = score;
      }
    });
    return best;
  }

  // Color presets hyprctl reports, as the rule's `cm`
  readonly property var _cmPresets: ["srgb", "dcip3", "dp3", "adobe", "wide", "edid", "hdr", "hdredid"]

  // Rules for the monitors as they are, but every fractional scale rounded
  // down to a whole one (1.5 to 1, 2.5 to 2; 2 stays, so a HiDPI panel
  // stays readable) and side by side from left to right in their current
  // order (a mirror keeps its place): the first run's layout on Hyprland's
  // example config, whose "auto" scale is often 1.25 or 1.5
  function wholeScaleRules(all) {
    let x = 0;
    return [...all].sort((a, b) => a.x - b.x || a.y - b.y).map(monitor => {
      const rule = ruleFromMonitor(monitor, all);
      rule.scale = Math.max(1, Math.floor(monitor.scale));
      rule.y = 0;
      rule.x = x;
      if (!rule.disabled && rule.mirror === "")
        x += logicalSize(monitor.width, monitor.height, rule.scale, rule.transform).width;
      return rule;
    });
  }

  // A rule with every field, describing a monitor as it is now
  function ruleFromMonitor(monitor, all) {
    const mirror = monitor.mirrorOf && monitor.mirrorOf !== "none" ? (all ?? []).find(other => other.name === monitor.mirrorOf || String(other.id) === String(monitor.mirrorOf)) : null;
    const preset = String(monitor.colorManagementPreset ?? "");
    return {
      "output": outputId(monitor, all),
      "label": monitor.name,
      "mode": formatMode(monitor.width, monitor.height, monitor.refreshRate),
      "x": Math.round(monitor.x),
      "y": Math.round(monitor.y),
      "scale": Math.round((monitor.scale || 1) * 10000) / 10000,
      "transform": monitor.transform ?? 0,
      "disabled": !!monitor.disabled,
      "mirror": mirror ? outputId(mirror, all) : "",
      "vrr": monitor.vrr ? 1 : 0,
      "bitdepth": /2101010/.test(String(monitor.currentFormat ?? "")) ? 10 : 8,
      "cm": _cmPresets.includes(preset) ? preset : "auto",
      "sdrBrightness": monitor.sdrBrightness ?? 1,
      "sdrSaturation": monitor.sdrSaturation ?? 1
    };
  }

  // A rule's rect in the layout, from its mode (or the monitor's own when
  // "preferred" or unreadable)
  function ruleRect(rule, monitor) {
    const mode = parseMode(rule.mode) ?? (monitor ? {
        "width": monitor.width,
        "height": monitor.height
      } : {
        "width": 1920,
        "height": 1080
      });
    const size = logicalSize(mode.width, mode.height, rule.scale, rule.transform);
    return {
      "x": rule.x,
      "y": rule.y,
      "width": size.width,
      "height": size.height
    };
  }
}
