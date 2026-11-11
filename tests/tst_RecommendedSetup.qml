import QtQuick
import QtTest
import qs.components.methods

TestCase {
  id: tc
  name: "RecommendedSetup"

  RepoFiles {
    id: files
  }

  readonly property var builtSchema: files.json("qml/config/json/config.schema.json")

  // A small schema with the same shape as the built one
  readonly property var fixtureSchema: ({
      "properties": {
        "Compositor": {
          "title": "Compositor",
          "x-showIf": {
            "/$supports.configModes": true
          },
          "properties": {
            "mode": {
              "title": "Mode",
              "enum": ["detached", "included", "managed"],
              "x-enumLabels": {
                "managed": "Managed by axiom"
              },
              "x-recommended": "managed"
            }
          }
        },
        "Lockscreen": {
          "title": "Lockscreen",
          "properties": {
            "mode": {
              "title": "Locker",
              "enum": ["quickshell", "none"],
              "x-recommended": "quickshell"
            }
          }
        },
        "Idle": {
          "title": "Idle",
          "properties": {
            "enabled": {
              "title": "Handle idle",
              "type": "boolean",
              "x-recommended": true
            }
          }
        },
        "ScreenSharing": {
          "title": "Screen sharing",
          "properties": {
            "enabled": {
              "title": "Use axiom's picker",
              "type": "boolean",
              "x-recommended": true
            }
          }
        },
        "Greeter": {
          "title": "Login screen",
          "properties": {
            "enabled": {
              "title": "Use axiom's login screen",
              "type": "boolean",
              "x-recommended": true
            }
          }
        },
        "ThemeIntegrations": {
          "title": "Theme integrations",
          "x-recommended": "installed",
          "properties": {
            "gtk": {
              "type": "boolean",
              "x-recommended": false,
              "x-commands": []
            },
            "kitty": {
              "type": "boolean"
            },
            "foot": {
              "type": "boolean",
              "x-commands": ["foot", "footclient"]
            }
          }
        }
      }
    })

  function _facts(overrides) {
    return Object.assign({
      "config": {
        "Compositor": {
          "mode": "detached"
        },
        "Lockscreen": {
          "mode": "none"
        },
        "Idle": {
          "enabled": false
        },
        "ScreenSharing": {
          "enabled": false
        },
        "Greeter": {
          "enabled": false
        },
        "ThemeIntegrations": {
          "gtk": false,
          "kitty": false,
          "foot": false
        }
      },
      "schema": tc.fixtureSchema,
      "valueOf": key => key === "/$supports.configModes" ? true : undefined,
      "later": [],
      "modeAllowed": true,
      "modeDefault": true,
      "managedBlocked": false,
      "portal": {
        "known": true,
        "installed": true,
        "hookedUp": false
      },
      "apps": {
        "installed": ["kitty", "foot"],
        "hookups": {
          "kitty": "todo",
          "foot": "none"
        }
      },
      "greeter": "off"
    }, overrides ?? {});
  }

  function _rows(overrides) {
    return RecommendedSetup.rows(RecommendedSetup.entries(tc.fixtureSchema), tc._facts(overrides));
  }

  function _allChecked(rows) {
    const checked = {};
    for (const id in rows)
      checked[id] = rows[id].checkedByDefault;
    return checked;
  }

  function _ids(entries) {
    return entries.map(e => e.id);
  }

  function test_entries_of_the_built_schema() {
    const entries = RecommendedSetup.entries(tc.builtSchema);
    const commits = entries.filter(e => e.step === "commit");
    compare(tc._ids(commits), ["Compositor.mode", "Lockscreen.mode", "Idle.enabled", "Polkit.enabled"]);
    compare(tc._ids(entries).slice(-3), ["ScreenSharing.enabled", "ThemeIntegrations", "Greeter.enabled"]);
    const apps = entries.find(e => e.step === "apps");
    verify(apps.keys.length > 5, "the integrations");
    verify(apps.keys.indexOf("gtk") < 0 && apps.keys.indexOf("qt") < 0, "gtk and qt are left out");
    compare(entries[0].detail, "Managed by axiom");
    compare(entries.find(e => e.id === "Greeter.enabled").detail, "Use axiom's login screen");
  }

  function test_built_schema_values_are_valid() {
    const sections = tc.builtSchema.properties;
    for (const section in sections) {
      const node = sections[section];
      if (!node.properties)
        continue;
      if (node["x-recommended"] !== undefined) {
        compare(node["x-recommended"], "installed", section + ": a section's x-recommended is installed");
        compare(node.type, "object", section + ": installed only on an object");
      }
      for (const key in node.properties) {
        const field = node.properties[key];
        const want = field["x-recommended"];
        if (want === undefined)
          continue;
        const where = section + "." + key;
        if (node["x-recommended"] === "installed") {
          compare(want, false, where + ": under an installed section only false");
          compare(field.type, "boolean", where);
        } else if (field.type === "boolean") {
          compare(typeof want, "boolean", where + ": a boolean for a boolean field");
        } else if (field.enum) {
          verify(field.enum.indexOf(want) >= 0, where + ": in enum");
        }
      }
    }
  }

  function test_appKeys() {
    const section = tc.fixtureSchema.properties.ThemeIntegrations;
    compare(RecommendedSetup.appKeys(section, {}), [], "gtk never appears, nothing is found");
    compare(RecommendedSetup.appKeys(section, {
      "kitty": true
    }), ["kitty"], "a command found counts");
    compare(RecommendedSetup.appKeys(section, {
      "footclient": true
    }), ["foot"], "any of its commands");
    const built = tc.builtSchema.properties.ThemeIntegrations;
    verify(built.properties.gtk["x-commands"].length === 0, "gtk has every desktop's");
    const keys = RecommendedSetup.appKeys(built, {});
    verify(keys.indexOf("gtk") < 0 && keys.indexOf("qt") < 0, "gtk and qt never appear");
  }

  function test_all_available() {
    const rows = tc._rows();
    for (const id in rows) {
      verify(rows[id].available, id + " available");
      verify(rows[id].checkedByDefault, id + " ticked");
    }
    compare(rows["ThemeIntegrations"].keys, ["kitty", "foot"]);
    compare(rows["ThemeIntegrations"].hookupKeys, ["kitty"]);
  }

  function test_greeter_prerequisites() {
    const cases = {
      "noGreetd": "noGreetd",
      "noCompositor": "noCompositor",
      "noClone": "noClone",
      "checking": "unknown",
      "checkFailed": "unknown"
    };
    for (const status in cases) {
      const row = tc._rows({
        "greeter": status
      })["Greeter.enabled"];
      verify(!row.available, status);
      verify(!row.checkedByDefault, status);
      compare(row.reason, cases[status], status);
    }
  }

  function test_already_on() {
    const config = tc._facts().config;
    config.Idle.enabled = true;
    config.ThemeIntegrations.kitty = true;
    config.ThemeIntegrations.foot = true;
    let rows = tc._rows({
      "config": config,
      "apps": {
        "installed": ["kitty", "foot"],
        "hookups": {
          "kitty": "done",
          "foot": "none"
        }
      }
    });
    verify(rows["Idle.enabled"].done);
    verify(!rows["Idle.enabled"].checkedByDefault);
    verify(rows["ThemeIntegrations"].done, "all on, hookups done");
    config.ScreenSharing.enabled = true;
    rows = tc._rows({
      "config": config
    });
    verify(!rows["ScreenSharing.enabled"].done, "enabled but not hooked up");
    rows = tc._rows({
      "config": config,
      "portal": {
        "known": true,
        "installed": true,
        "hookedUp": true
      }
    });
    verify(rows["ScreenSharing.enabled"].done);
    for (const status of ["installed", "outdated"])
      verify(tc._rows({
        "greeter": status
      })["Greeter.enabled"].done, status);
  }

  function test_compositor_support() {
    let row = tc._rows({
      "valueOf": () => false
    })["Compositor.mode"];
    verify(!row.available);
    compare(row.reason, "unsupported");
    row = tc._rows({
      "managedBlocked": true
    })["Compositor.mode"];
    verify(!row.available);
    compare(row.reason, "blocked");
  }

  function test_later() {
    const entries = RecommendedSetup.entries(tc.fixtureSchema);
    let rows = tc._rows({
      "later": ["Compositor.mode"]
    });
    verify(rows["Compositor.mode"].later);
    verify(rows["Compositor.mode"].available);
    let plan = RecommendedSetup.steps(entries, rows, tc._allChecked(rows));
    compare(plan[0], {
      "step": "later",
      "path": "Compositor.mode",
      "value": "managed",
      "row": "Compositor.mode"
    });
    verify(!("Compositor.mode" in plan[1].values), "never in the commit");
    rows = tc._rows({
      "later": ["Compositor.mode"],
      "modeAllowed": false
    });
    verify(!rows["Compositor.mode"].available);
    compare(rows["Compositor.mode"].reason, "blocked");
    rows = tc._rows({
      "later": ["Compositor.mode"],
      "modeDefault": false
    });
    verify(rows["Compositor.mode"].available);
    verify(!rows["Compositor.mode"].checkedByDefault, "a config of the user's: unticked");
    verify(rows["Idle.enabled"].checkedByDefault, "every other row stays ticked");
    const checked = tc._allChecked(rows);
    checked["Compositor.mode"] = true;
    plan = RecommendedSetup.steps(entries, rows, checked);
    compare(plan[0].step, "later", "tickable by hand");
  }

  function test_portal_and_apps_unavailable() {
    let rows = tc._rows({
      "portal": {
        "known": false,
        "installed": false,
        "hookedUp": false
      }
    });
    compare(rows["ScreenSharing.enabled"].reason, "unsupported");
    rows = tc._rows({
      "portal": {
        "known": true,
        "installed": false,
        "hookedUp": false
      }
    });
    compare(rows["ScreenSharing.enabled"].reason, "missing");
    rows = tc._rows({
      "apps": {
        "installed": [],
        "hookups": {}
      }
    });
    compare(rows["ThemeIntegrations"].reason, "noApps");
    verify(!rows["ThemeIntegrations"].available);
  }

  function test_steps() {
    const entries = RecommendedSetup.entries(tc.fixtureSchema);
    const rows = tc._rows();
    const checked = tc._allChecked(rows);
    const plan = RecommendedSetup.steps(entries, rows, checked);
    compare(plan.map(s => s.step + (s.key ? ":" + s.key : "")), ["commit", "hookup:screenSharing", "portal", "hookup:kitty", "greeter"]);
    compare(plan[0].values, {
      "Compositor.mode": "managed",
      "Lockscreen.mode": "quickshell",
      "Idle.enabled": true,
      "ScreenSharing.enabled": true,
      "ThemeIntegrations.kitty": true,
      "ThemeIntegrations.foot": true
    }, "never Greeter.enabled");
    checked["Greeter.enabled"] = false;
    compare(RecommendedSetup.steps(entries, rows, checked).filter(s => s.step === "greeter").length, 0, "unticking the greeter drops its step");
    const none = {};
    for (const id in rows)
      none[id] = false;
    compare(RecommendedSetup.steps(entries, rows, none), []);
  }

  function test_portalAction() {
    compare(RecommendedSetup.portalAction(true), "defer");
    compare(RecommendedSetup.portalAction(false), "restart");
  }
}
