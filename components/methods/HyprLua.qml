pragma Singleton
import QtQuick

// Hyprland's Lua from schema fields, for what the shell sends Hyprland
// itself (the layer rules, monitor calls, the greeter's config; axiom's
// config layer is the daemon's: internal/compositor/render): each field with
// x-compositor.hyprland (CompositorLayer.compositorFields) becomes one value
// of a nested hl.config({...}) table, by its spec:
//   key     the option's dotted path, or a list of paths
//   scale   a factor for integers shown scaled (0.01 for a percent)
//   value   how the value is converted: "int" (a boolean as 0/1),
//           "number" (an enum of numbers written as strings),
//           "emptyIsDefault" ("default" → ""), "color" (a theme color
//           name as rgba(hex + alpha, "ff" unless given))
//   always  written even when it's the schema default; other fields are
//           only written once changed, so Hyprland's own default (and the
//           user's files) stay in charge otherwise
//   if      a switch beside it: written (default or not) only when on
QtObject {
  id: root

  // A Lua string literal
  function string(text) {
    return '"' + String(text).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n").replace(/\r/g, "\\r") + '"';
  }

  // A value as Lua: strings quoted, numbers without float noise
  function value(v) {
    if (typeof v === "string")
      return string(v);
    if (typeof v === "number")
      return String(Math.round(v * 10000) / 10000);
    return String(v);
  }

  function _convert(spec, v, resolveHex) {
    if (spec.scale !== undefined)
      return v * spec.scale;
    switch (spec.value) {
    case "int":
      return v ? 1 : 0;
    case "number":
      return Number(v);
    case "emptyIsDefault":
      return v === "default" ? "" : v;
    case "color":
      return `rgba(${resolveHex(v)}${spec.alpha ?? "ff"})`;
    }
    return v;
  }

  function _set(table, path, v) {
    const keys = path.split(".");
    let node = table;
    for (const key of keys.slice(0, -1)) {
      if (typeof node[key] !== "object" || node[key] === null)
        node[key] = {};
      node = node[key];
    }
    node[keys[keys.length - 1]] = v;
  }

  // The nested option table for `values` (an object of `objectSchema`'s
  // fields). resolveHex(colorName) gives "rrggbb"; `overrides` maps option
  // paths to values that win over the fields (axiom's shape, say).
  function configTable(objectSchema, values, resolveHex, overrides) {
    const table = {};
    for (const field of CompositorLayer.compositorFields(objectSchema, values, "hyprland", "")) {
      const spec = field.spec;
      if (field.on !== null ? !field.on : !spec.always && field.value === field.schema.default)
        continue;
      const v = _convert(spec, field.value, resolveHex);
      // A schema list reaches QML as a list object, not a JS Array
      const paths = typeof spec.key === "string" ? [spec.key] : Array.prototype.slice.call(spec.key);
      for (const path of paths)
        _set(table, path, v);
    }
    for (const path in overrides ?? {})
      _set(table, path, overrides[path]);
    return table;
  }

  // A table as a Lua literal, keys sorted. Nested tables go on lines of
  // their own below the top level, until one fits on a line.
  function serialize(table, indent) {
    const pad = indent ?? "";
    const keys = Object.keys(table).sort();
    // An array is a Lua sequence (a vec2's { x, y }: Hyprland counts its
    // elements, so { x = …, y = … } has none)
    const entry = key => {
      const v = table[key];
      if (Array.isArray(v))
        return `${key} = { ${v.map(value).join(", ")} }`;
      return `${key} = ${typeof v === "object" ? serialize(v, pad + "  ") : value(v)}`;
    };
    const flat = `{ ${keys.map(entry).join(", ")} }`;
    if (keys.length === 0)
      return "{}";
    if (pad !== "" && flat.length <= 100 && !flat.includes("\n"))
      return flat;
    return `{\n${keys.map(key => `${pad}  ${entry(key)},`).join("\n")}\n${pad}}`;
  }

  // --- Monitors (Monitors.profiles, MonitorLayout) ---

  // A monitor rule (the MonitorRule schema) as hl.monitor()'s spec: output,
  // mode, position and scale always, the rest only when changed. `mirror`
  // stays an output id: monitorsLua resolves it to a connector name.
  function monitorSpec(rule) {
    if (rule.disabled)
      return {
        "output": rule.output,
        "disabled": true
      };
    const spec = {
      "output": rule.output,
      "mode": rule.mode || "preferred",
      "position": `${Math.round(rule.x ?? 0)}x${Math.round(rule.y ?? 0)}`,
      "scale": rule.scale ?? 1
    };
    if (rule.transform)
      spec.transform = rule.transform;
    if (rule.mirror)
      spec.mirror = rule.mirror;
    if (rule.vrr)
      spec.vrr = rule.vrr;
    if (rule.bitdepth === 10)
      spec.bitdepth = 10;
    if (rule.cm && rule.cm !== "auto")
      spec.cm = rule.cm;
    if (rule.sdrBrightness !== undefined && rule.sdrBrightness !== 1)
      spec.sdrbrightness = rule.sdrBrightness;
    if (rule.sdrSaturation !== undefined && rule.sdrSaturation !== 1)
      spec.sdrsaturation = rule.sdrSaturation;
    return spec;
  }

  readonly property var _specOrder: ["output", "mode", "position", "scale"]

  // A spec on one line, output first
  function inlineSpec(spec) {
    const keys = Object.keys(spec).sort((a, b) => {
      const ia = _specOrder.indexOf(a);
      const ib = _specOrder.indexOf(b);
      return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || (a < b ? -1 : a > b ? 1 : 0);
    });
    return `{ ${keys.map(key => `${key} = ${value(spec[key])}`).join(", ")} }`;
  }

  // Lua lines that keep the monitors in the profile for what's connected:
  // AXIOM_MONITOR_PROFILES, axiom_apply_monitors() (picks as
  // MonitorLayout.matchProfile does, from hl.get_monitors(), which only
  // lists enabled outputs) run now and on every monitor.added/removed.
  // Outputs another profile lists, but the chosen one doesn't, go back to
  // Hyprland's defaults (connected or not: a disabled output isn't listed),
  // so a disable doesn't outlive its profile.
  // With no profiles it only drops the event handlers of an earlier run.
  function monitorsLua(profiles) {
    const lines = ["if AXIOM_MONITOR_SUBS then", "  for _, sub in ipairs(AXIOM_MONITOR_SUBS) do sub:remove() end", "  AXIOM_MONITOR_SUBS = nil", "end"];
    const used = (profiles ?? []).filter(profile => (profile.outputs ?? []).some(rule => rule.output));
    if (used.length === 0)
      return lines;
    lines.push("AXIOM_MONITOR_PROFILES = {");
    for (const profile of used) {
      lines.push(`  { name = ${string(profile.name ?? "")}, outputs = {`);
      for (const rule of profile.outputs)
        if (rule.output)
          lines.push(`    ${inlineSpec(monitorSpec(rule))},`);
      lines.push("  } },");
    }
    lines.push("}");
    lines.push(`function axiom_apply_monitors()
  local connected = hl.get_monitors() or {}
  local function matches(output, mon)
    if output:sub(1, 5) == "desc:" then return mon.description == output:sub(6) end
    return mon.name == output
  end
  local function find(output)
    for _, mon in ipairs(connected) do
      if matches(output, mon) then return mon end
    end
  end
  local best, bestScore = nil, 0
  for _, profile in ipairs(AXIOM_MONITOR_PROFILES) do
    local score, exact = 0, true
    for _, spec in ipairs(profile.outputs) do
      local found = find(spec.output)
      if found and not spec.disabled then score = score + 1 end
      if not found and not spec.disabled then exact = false end
    end
    for _, mon in ipairs(connected) do
      local listed = false
      for _, spec in ipairs(profile.outputs) do
        if matches(spec.output, mon) then listed = true end
      end
      if not listed then exact = false end
    end
    if exact and score > 0 then score = score + 1000 end
    if score > bestScore then best, bestScore = profile, score end
  end
  -- Nothing reported yet (a first start): the first profile, as rules
  -- waiting for their outputs
  if #connected == 0 then best = AXIOM_MONITOR_PROFILES[1] end
  if not best then return end
  local mine = {}
  for _, spec in ipairs(best.outputs) do
    mine[spec.output] = true
    local rule = {}
    for k, v in pairs(spec) do rule[k] = v end
    if rule.mirror then
      local target = find(rule.mirror)
      rule.mirror = target and target.name or nil
    end
    hl.monitor(rule)
  end
  for _, profile in ipairs(AXIOM_MONITOR_PROFILES) do
    for _, spec in ipairs(profile.outputs) do
      if not mine[spec.output] then
        mine[spec.output] = true
        hl.monitor({ output = spec.output, mode = "preferred", position = "auto", scale = "auto" })
      end
    end
  end
end`);
    lines.push(`AXIOM_MONITOR_SUBS = { hl.on("monitor.added", axiom_apply_monitors), hl.on("monitor.removed", axiom_apply_monitors) }`);
    lines.push("axiom_apply_monitors()");
    return lines;
  }

  // The greeter's Hyprland, from its bundle (GreeterBundle): the monitor
  // layouts (monitorsLua), and the Input options marked x-greeter whose
  // parts are on (`inputSchema`: Input's schema; any other option in
  // `input` is left out). resolveHex as for configTable.
  function greeterLua(profiles, inputSchema, input, resolveHex) {
    const lines = monitorsLua(profiles);
    if (!input)
      return lines;
    const table = configTable(root._greeterSchema(inputSchema), input, resolveHex, {});
    if (Object.keys(table).length > 0)
      lines.push(`hl.config(${serialize(table)})`);
    return lines;
  }

  // `objectSchema` with only its x-greeter settings (in its groups too)
  function _greeterSchema(objectSchema) {
    const out = {
      "type": "object",
      "properties": {}
    };
    const props = objectSchema?.properties ?? {};
    for (const key in props) {
      if (props[key]["x-greeter"] === true)
        out.properties[key] = props[key];
      else if (props[key].type === "object" && props[key].properties) {
        const inner = root._greeterSchema(props[key]);
        if (Object.keys(inner.properties).length > 0)
          out.properties[key] = inner;
      }
    }
    return out;
  }

  // A chunk resetting Hyprland to its main binds if it's in submap `name`
  function leaveSubmap(name) {
    return `if hl.get_current_submap() == ${string(name)} then hl.dispatch(hl.dsp.submap("reset")) end`;
  }

  // --- The window switcher ---
  // Its submap is part of axiom's layer (the daemon's, internal/compositor/
  // render's SwitcherLua): Hyprland holds every key while it's open and
  // sends what happens as `custom>>axiom-switcher:<verb>` events on socket2
  // (WindowSwitcherManager listens).

  readonly property string switcherSubmap: "axiom_switcher"
  readonly property string switcherEvent: "axiom-switcher:"
  // Leaves the switcher from outside its binds (a click on a tile)
  readonly property string switcherLeaveLua: "if axiom_switcher_leave then axiom_switcher_leave() end"
}
