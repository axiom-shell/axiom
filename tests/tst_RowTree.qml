import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "RowTree"

  function row(path, showIf, groupShowIf) {
    return {
      "path": path,
      "schema": showIf ? {
        "x-showIf": showIf
      } : {},
      "groupShowIf": groupShowIf ?? []
    };
  }

  // Menu's Placement group, in the order the form lists it
  function menu() {
    return [row(["placement"]), row(["edge"], {
        "placement": {
          "not": "free"
        }
      }), row(["freeAnchor", "at"], null, [
        {
          "condition": {
            "placement": "free"
          },
          "path": []
        }
      ]), row(["freeAnchor", "x"], {
        "at": "point"
      }, [
        {
          "condition": {
            "placement": "free"
          },
          "path": []
        }
      ]), row(["freeAnchor", "y"], {
        "at": "point"
      }, [
        {
          "condition": {
            "placement": "free"
          },
          "path": []
        }
      ]), row(["length"], {
        "placement": "edge"
      }), row(["background"], {
        "placement": ["edge", "free"]
      }), row(["detached"], {
        "placement": "edge",
        "background": "panel"
      }), row(["distance"], {
        "anyOf": [
          {
            "placement": "edge",
            "detached": true
          },
          {
            "placement": "edge",
            "background": "none"
          }
        ]
      })];
  }

  function test_menu_placement() {
    const plan = RowTree.plan(menu());
    compare(plan.levels, [0, 1, 1, 2, 2, 1, 1, 2, 1]);
  }

  function test_and_takes_the_latest() {
    compare(RowTree.plan(menu()).parents[7], 6, "detached {placement, background} sits under background");
  }

  function test_any_of_roots() {
    const rows = [row(["a"]), row(["b"]), row(["c"], {
        "anyOf": [
          {
            "a": 1
          },
          {
            "b": 1
          }
        ]
      })];
    compare(RowTree.plan(rows).levels, [0, 0, 0]);
    compare(RowTree.plan(rows).parents[2], -1);
  }

  function test_any_of_same_parent() {
    const rows = [row(["a"]), row(["c"], {
        "anyOf": [
          {
            "a": 1
          },
          {
            "a": 2
          }
        ]
      })];
    compare(RowTree.plan(rows).levels, [0, 1]);
  }

  function test_relative_keys() {
    const rows = [row(["placement"]), row(["open", "onHover"], {
        "../placement": "edge"
      })];
    compare(RowTree.plan(rows).levels, [0, 1], "../ resolves from the object");
    const dotted = [row(["open", "onHover"]), row(["delay"], {
        "open.onHover": true
      })];
    compare(RowTree.plan(dotted).levels, [0, 1], "a dotted key resolves");
  }

  function test_config_wide_keys_ignored() {
    const rows = [row(["a"]), row(["b"], {
        "/Foo.bar": true
      }), row(["c"], {
        "$bar.boxed": true
      })];
    compare(RowTree.plan(rows).levels, [0, 0, 0]);
  }

  function test_later_row_is_no_parent() {
    const rows = [row(["a"], {
        "b": true
      }), row(["b"])];
    compare(RowTree.plan(rows).levels, [0, 0]);
  }

  function test_group_show_if_of_a_nested_object() {
    const rows = menu();
    compare(RowTree.plan(rows).parents[2], 0, "the nested object's condition names placement");
  }

  // A nested object's heading carries its own condition (SchemaLayout `group`
  // row), so it sits at the level of the rows it heads
  function test_group_row_takes_its_show_if() {
    const under = [
      {
        "condition": {
          "mode": "rotate"
        },
        "path": ["S"]
      }
    ];
    const rows = [row(["S", "mode"]),
      {
        "kind": "group",
        "path": ["S", "rotation"],
        "showIf": {
          "mode": "rotate"
        }
      },
      row(["S", "rotation", "interval"], null, under), row(["S", "rotation", "order"], null, under)];
    const plan = RowTree.plan(rows);
    compare(plan.levels, [0, 1, 1, 1]);
    compare(plan.parents, [-1, 0, 0, 0]);
  }

  // Idle: Dim's heading and its rows sit under "enabled", the level under its mode
  function test_idle_dim_levels() {
    const under = [
      {
        "condition": {
          "enabled": true
        },
        "path": ["Idle"]
      }
    ];
    const rows = [row(["Idle", "enabled"]),
      {
        "kind": "group",
        "path": ["Idle", "dim"],
        "showIf": {
          "enabled": true
        }
      },
      row(["Idle", "dim", "timeout"], null, under), row(["Idle", "dim", "mode"], null, under), row(["Idle", "dim", "level"], {
        "mode": "dim"
      }, under)];
    compare(RowTree.plan(rows).levels, [0, 1, 1, 1, 2]);
  }

  function test_empty() {
    const plan = RowTree.plan([]);
    compare(plan.levels, []);
  }
}
