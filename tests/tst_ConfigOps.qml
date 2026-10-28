import QtQuick
import QtTest
import qs.components.methods

// The config's path ops (ConfigOps). diff and apply are called through
// Shared, so their cases are shared fixtures: the daemon's tests decode
// each diff as config.set's params, strictly, and check Go's Diff and
// ApplyOps give the same (backend/internal/daemon/configops_shared_test.go)
TestCase {
  id: test
  name: "ConfigOps"

  Shared {
    id: shared
    testCase: test
  }

  // The shape config.set decodes (backend/internal/config/ops.go): "op",
  // a path of keys, "value" only on a set
  function test_diff() {
    const rows = [[
        {
          "a": {
            "b": 1
          }
        },
        {
          "a": {
            "b": 1
          }
        },
        [], "same"], [
        {
          "a": {
            "b": 1,
            "c": 2
          }
        },
        {
          "a": {
            "b": 1,
            "c": 3
          }
        },
        [
          {
            "op": "set",
            "path": ["a", "c"],
            "value": 3
          }
        ], "a leaf"], [
        {
          "L": [1]
        },
        {
          "L": [1, 2]
        },
        [
          {
            "op": "set",
            "path": ["L"],
            "value": [1, 2]
          }
        ], "a list whole"], [
        {
          "a": {
            "b": 1,
            "c": 2
          }
        },
        {
          "a": {
            "b": 1
          }
        },
        [
          {
            "op": "delete",
            "path": ["a", "c"]
          }
        ], "a key gone"], [
        {},
        {
          "a": {
            "b": 1
          }
        },
        [
          {
            "op": "set",
            "path": ["a"],
            "value": {
              "b": 1
            }
          }
        ], "a section new"], [
        {
          "a": {
            "b": 1
          }
        },
        {
          "a": null
        },
        [
          {
            "op": "set",
            "path": ["a"],
            "value": null
          }
        ], "an object to a value"]];
    for (const [before, after, expected, message] of rows) {
      const ops = shared.calls.ConfigOps.diff(before, after);
      compare(ops, expected, message);
      compare(shared.calls.ConfigOps.apply(before, ops), after, message + ": applied");
    }
  }

  // A save as ConfigManager.commit makes it: the live schema's defaults
  // with a setting changed, a list replaced and a key gone
  function test_diff_a_save() {
    const before = SchemaValidation.applyDefaults({}, shared.schema);
    const after = JSON.parse(JSON.stringify(before));
    after.Appearance.theme.name = "nord";
    after.Bars.items = [];
    delete after.General.primaryMonitor;
    const ops = shared.calls.ConfigOps.diff(before, after);
    compare(ops.length, 3);
    compare(shared.calls.ConfigOps.apply(before, ops), after);
  }

  function test_apply() {
    const config = {
      "Bars": {
        "style": {
          "radius": 4,
          "gap": 2
        },
        "items": [1]
      },
      "General": {
        "x": 1
      }
    };
    compare(ConfigOps.apply(config, []), config, "no ops: the config itself");
    const out = shared.calls.ConfigOps.apply(config, [
      {
        "op": "set",
        "path": ["Bars", "style", "gap"],
        "value": 5
      },
      {
        "op": "delete",
        "path": ["General", "x"]
      }
    ]);
    compare(out.Bars.style, {
      "radius": 4,
      "gap": 5
    });
    compare(out.General, {});
    verify(out.Bars.items === config.Bars.items, "siblings along the path are shared");
    compare(config.Bars.style.gap, 2, "the original is untouched");
    compare(config.General.x, 1, "the original is untouched");
    compare(shared.calls.ConfigOps.apply(config, [
      {
        "op": "set",
        "path": ["Bars",
          {
            "id": "a"
          }
        ],
        "value": {}
      }
    ]), null, "an {id} selector");
    compare(shared.calls.ConfigOps.apply(config, [
      {
        "op": "order",
        "path": ["Bars", "items"],
        "value": []
      }
    ]), null, "an order");
  }

  function test_previewOps() {
    const config = {
      "Bars": {
        "style": {
          "radius": 4
        },
        "items": [1]
      },
      "General": {
        "x": 1
      }
    };
    const out = ConfigOps.apply(config, ConfigOps.previewOps({
      "Bars.style.radius": 8,
      "Bars": {
        "style": {
          "radius": 0
        },
        "items": []
      },
      "New.deep.key": true
    }));
    compare(out.Bars, {
      "style": {
        "radius": 8
      },
      "items": []
    }, "the deeper path shows through the section laid over it");
    compare(out.New, {
      "deep": {
        "key": true
      }
    }, "missing objects are made");
    verify(out.General === config.General, "untouched sections stay the same object");
  }
}
