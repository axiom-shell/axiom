import QtQuick
import QtTest
import qs.components.methods

// The Lua it writes also goes to tests/.out/, where scripts/run_tests.sh
// checks it with `luac -p`.
TestCase {
  id: test
  name: "HyprLua"

  // Records the helpers' calls as shared fixtures for the axiom binary
  Shared {
    id: shared
    testCase: test
  }

  RepoFiles {
    id: files
  }

  readonly property var fieldSchema: ({
      "properties": {
        "gaps": {
          "type": "integer",
          "default": 5,
          "x-compositor": {
            "hyprland": {
              "key": "general.gaps_in"
            }
          }
        },
        "both": {
          "type": "integer",
          "default": 0,
          "x-compositor": {
            "hyprland": {
              "key": ["a.one", "a.two"]
            }
          }
        },
        "opacity": {
          "type": "integer",
          "default": 100,
          "x-compositor": {
            "hyprland": {
              "key": "decoration.active_opacity",
              "scale": 0.01
            }
          }
        },
        "flag": {
          "type": "boolean",
          "default": false,
          "x-compositor": {
            "hyprland": {
              "key": "misc.flag",
              "value": "int"
            }
          }
        },
        "border": {
          "type": "string",
          "default": "base0D",
          "x-compositor": {
            "hyprland": {
              "key": "general.col.active_border",
              "value": "color",
              "alpha": "cc"
            }
          }
        },
        "always": {
          "type": "string",
          "default": "dwindle",
          "x-compositor": {
            "hyprland": {
              "key": "general.layout",
              "always": true
            }
          }
        },
        "gated": {
          "type": "integer",
          "default": 3,
          "x-compositor": {
            "hyprland": {
              "key": "blur.size",
              "if": "blur"
            }
          }
        },
        "blur": {
          "type": "boolean",
          "default": false
        },
        "unmapped": {
          "type": "integer",
          "default": 1
        }
      }
    })

  // `base` with `patch` over it, a nested object's keys one by one (a v2
  // group: WindowLook.shadow, Input.keyboard)
  function merged(base, patch) {
    const out = JSON.parse(JSON.stringify(base));
    for (const key in patch)
      out[key] = typeof patch[key] === "object" && patch[key] !== null && !Array.isArray(patch[key]) ? Object.assign({}, out[key], patch[key]) : patch[key];
    return out;
  }

  function hex(name) {
    return name === "base0D" ? "112233" : "445566";
  }

  function test_string_escapes() {
    compare(shared.calls.HyprLua.string('a "b" \\ c\nd'), '"a \\"b\\" \\\\ c\\nd"');
    // A bare carriage return would end the string: Lua refuses the chunk
    compare(shared.calls.HyprLua.string("us\r,de"), '"us\\r,de"');
  }

  function test_blur_lists() {
    verify(LayerStack.blurChrome.includes("bar-floating-long") && LayerStack.blurBacked.includes("bar-pill"), "blur lists take every bar");
  }

  function test_value() {
    compare(shared.calls.HyprLua.value(0.1 + 0.2), "0.3");
    compare(shared.calls.HyprLua.value(true), "true");
    compare(shared.calls.HyprLua.value("x"), '"x"');
  }

  function test_defaults_write_only_always_fields() {
    const values = {
      "gaps": 5,
      "both": 0,
      "opacity": 100,
      "flag": false,
      "border": "base0D",
      "always": "dwindle",
      "gated": 3,
      "blur": false,
      "unmapped": 1
    };
    compare(JSON.stringify(shared.calls.HyprLua.configTable(fieldSchema, values, hex)), JSON.stringify({
      "general": {
        "layout": "dwindle"
      }
    }));
  }

  function test_changed_fields_convert() {
    const table = shared.calls.HyprLua.configTable(fieldSchema, {
      "gaps": 8,
      "both": 2,
      "opacity": 90,
      "flag": true,
      "border": "base08",
      "always": "master",
      "gated": 3,
      "blur": true
    }, hex, {
      "general.gaps_out": 12
    });
    compare(table.general.gaps_in, 8);
    compare(table.general.gaps_out, 12);
    compare(table.a.one, 2);
    compare(table.a.two, 2);
    compare(table.decoration.active_opacity, 0.9);
    compare(table.misc.flag, 1);
    compare(table.general.col.active_border, "rgba(445566cc)");
    compare(table.general.layout, "master");
    // `if`: written, default or not, only while the switch is on
    compare(table.blur.size, 3);
  }

  function test_serialize_is_sorted_and_nested() {
    compare(shared.calls.HyprLua.serialize({}), "{}");
    compare(shared.calls.HyprLua.serialize({
      "b": 1,
      "a": {
        "y": "s",
        "x": true
      }
    }), '{\n  a = { x = true, y = "s" },\n  b = 1,\n}');
  }

  // Every managed option, each changed from its default, as Lua
  function test_managed_schema_serializes_to_lua() {
    const schema = files.json("config/json/config.schema.json");
    const managed = schema.properties.Compositor.properties.hyprland;
    const values = SchemaValidation.applyDefaults({}, managed, schema);
    const expected = [];
    for (const key in managed.properties) {
      const field = managed.properties[key];
      const spec = field["x-compositor"]?.hyprland;
      if (!spec)
        continue;
      if (spec.if)
        values[spec.if] = true;
      if (field.type === "boolean")
        values[key] = !values[key];
      else if (field.type === "integer")
        values[key] = values[key] + 1 <= (field.maximum ?? Infinity) ? values[key] + 1 : values[key] - 1;
      else if (field.enum)
        values[key] = field.enum.find(option => option !== values[key]);
      else if (field.type === "string")
        values[key] = spec.value === "color" ? "base08" : "changed";
      expected.push(...(typeof spec.key === "string" ? [spec.key] : spec.key));
    }
    const table = shared.calls.HyprLua.configTable(managed, values, hex);
    for (const path of expected) {
      let node = table;
      for (const key of path.split("."))
        node = node?.[key];
      verify(node !== undefined, path + " missing from the table");
    }
    const lua = "hl = { config = function(t) end }\nhl.config(" + shared.calls.HyprLua.serialize(table) + ")\n";
    const written = files.write("tests/.out/managed.lua", lua);
    tryVerify(() => written.done, 2000);
  }

  // --- Strips ---

  readonly property var ruleDefaults: {
    const schema = files.json("config/json/config.schema.json");
    return SchemaValidation.applyDefaults({}, schema.definitions.MonitorRule, schema);
  }

  function rule(fields) {
    return Object.assign({}, ruleDefaults, fields);
  }

  function test_monitorSpec_writes_only_changes() {
    compare(shared.calls.HyprLua.monitorSpec(rule({
      "output": "DP-1",
      "mode": "3440x1440@240"
    })), {
      "output": "DP-1",
      "mode": "3440x1440@240",
      "position": "0x0",
      "scale": 1
    });
    const spec = shared.calls.HyprLua.monitorSpec(rule({
      "output": "DP-1",
      "x": -1440,
      "y": -1100,
      "transform": 3,
      "vrr": 2,
      "bitdepth": 10,
      "cm": "hdr",
      "sdrBrightness": 1.2
    }));
    compare(spec.position, "-1440x-1100");
    compare(spec.transform, 3);
    compare(spec.vrr, 2);
    compare(spec.bitdepth, 10);
    compare(spec.cm, "hdr");
    compare(spec.sdrbrightness, 1.2);
    compare(spec.sdrsaturation, undefined);
    compare(shared.calls.HyprLua.monitorSpec(rule({
      "output": "HDMI-A-1",
      "disabled": true,
      "x": 5
    })), {
      "output": "HDMI-A-1",
      "disabled": true
    });
  }

  function test_monitorsLua_without_profiles_only_unsubscribes() {
    const lines = shared.calls.HyprLua.monitorsLua([]);
    verify(lines.join("\n").includes("sub:remove()"));
    verify(!lines.join("\n").includes("axiom_apply_monitors"));
  }

  // The generated picker, run by `lua` with a stubbed hl, picks what
  // MonitorLayout.matchProfile picks
  function test_monitorsLua_picks_like_matchProfile() {
    const profiles = [
      {
        "name": "Desk",
        "outputs": [rule({
            "output": "desc:AOC",
            "mode": "3440x1440@240"
          }), rule({
            "output": "HDMI-A-1",
            "disabled": true
          })]
      },
      {
        "name": "TV",
        "outputs": [rule({
            "output": "desc:AOC",
            "mode": "3440x1440@144"
          }), rule({
            "output": "desc:LG TV",
            "mode": "1920x1080@60",
            "x": 3440,
            "mirror": "desc:AOC"
          })]
      }
    ];
    const aoc = {
      "name": "DP-1",
      "description": "AOC"
    };
    const tv = {
      "name": "HDMI-A-1",
      "description": "LG TV"
    };
    const cases = [[[aoc], "3440x1440@240"], [[aoc, tv], "3440x1440@144"], [[tv], "3440x1440@144"]];
    const monitorsLua = monitors => "{ " + monitors.map(m => `{ name = ${shared.calls.HyprLua.string(m.name)}, description = ${shared.calls.HyprLua.string(m.description)} }`).join(", ") + " }";
    const checks = cases.map(([connected, mode]) => {
      compare(profiles[MonitorLayout.matchProfile(profiles, connected)].outputs[0].mode, mode);
      return `check(${monitorsLua(connected)}, ${shared.calls.HyprLua.string(mode)})`;
    });
    const lua = `local connected, applied, removed = {}, {}, 0
hl = {
  get_monitors = function() return connected end,
  monitor = function(spec) applied[#applied + 1] = spec end,
  on = function() return { remove = function() removed = removed + 1 end } end,
}
local function run()
${shared.calls.HyprLua.monitorsLua(profiles).join("\n")}
end
run()
local function check(monitors, mode)
  connected, applied = monitors, {}
  axiom_apply_monitors()
  assert(applied[1].mode == mode, "picked " .. tostring(applied[1].mode) .. ", wanted " .. mode)
end
${checks.join("\n")}
-- The TV profile mirrors onto the AOC's connector, and resets the output
-- Desk disables
check(${monitorsLua([aoc, tv])}, "3440x1440@144")
assert(applied[2].mirror == "DP-1", "mirror resolved to a connector")
local reset = false
for _, spec in ipairs(applied) do
  if spec.output == "HDMI-A-1" and spec.mode == "preferred" then reset = true end
end
assert(reset, "the output Desk disables goes back to its defaults")
-- A first start, nothing reported yet: the first profile
check({}, "3440x1440@240")
-- Running the chunk again drops the earlier handlers
run()
assert(removed == 2, "earlier handlers removed")
`;

    const written = files.write("tests/.out/monitors.run.lua", lua);
    tryVerify(() => written.done, 2000);
  }

  // The greeter's Hyprland: the monitors always, and the x-greeter input
  // options of the parts that are on
  function test_greeterLua() {
    const schema = files.json("config/json/config.schema.json");
    const inputSchema = schema.properties.Input;
    const profiles = [
      {
        "name": "desk",
        "outputs": [rule({
            "output": "DP-1"
          })]
      }
    ];
    const none = shared.calls.HyprLua.greeterLua(profiles, inputSchema, undefined, hex);
    verify(none.some(line => line.startsWith("AXIOM_MONITOR_PROFILES")));
    verify(!none.some(line => line.startsWith("hl.config")));

    const input = SchemaValidation.applyDefaults({}, inputSchema, schema);
    input.keyboard.layout = "us,de";
    input.mouse.sensitivity = -50;
    compare(shared.calls.HyprLua.greeterLua(profiles, inputSchema, input, hex).length, none.length, "every part off: nothing set");
    input.keyboard.enabled = true;
    input.mouse.enabled = true;
    const lines = shared.calls.HyprLua.greeterLua(profiles, inputSchema, input, hex);
    const config = lines[lines.length - 1];
    verify(config.startsWith("hl.config("));
    verify(config.includes('kb_layout = "us,de"'));
    verify(config.includes("sensitivity = -0.5"));
    verify(!config.includes("touchpad"), "its part is off");
    const lua = "hl = { config = function(t) end, monitor = function(t) end, get_monitors = function() return {} end, on = function() return { remove = function() end } end }\n" + lines.join("\n") + "\n";
    const written = files.write("tests/.out/greeter.run.lua", lua);
    tryVerify(() => written.done, 2000);
  }

  // The look's spec (CompositorLayer.look) from WindowLook's values
  function look(values, activeHex, inactiveHex, borderWidth, radius, surfacesBlur) {
    return shared.calls.CompositorLayer.look(values, {
      "activeHex": activeHex,
      "inactiveHex": inactiveHex,
      "borderWidth": borderWidth,
      "radius": radius,
      "surfacesBlur": surfacesBlur
    });
  }

  function test_leaveSubmap() {
    compare(shared.calls.HyprLua.leaveSubmap("axiom_record"), `if hl.get_current_submap() == "axiom_record" then hl.dispatch(hl.dsp.submap("reset")) end`);
  }

  function test_switcherHeld() {
    compare(shared.calls.BindActions.switcherHeld(["ALT"]), ["ALT"]);
    compare(shared.calls.BindActions.switcherHeld(["ALT", "SHIFT"]), ["ALT"], "SHIFT only turns it around");
    compare(shared.calls.BindActions.switcherHeld(["SHIFT"]), ["SHIFT"], "unless it's all there is");
    compare(shared.calls.BindActions.switcherHeld([]), [], "nothing to hold");
  }
}
