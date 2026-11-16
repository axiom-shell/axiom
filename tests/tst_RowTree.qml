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
      }), row(["popoutAtWidget"], {
        "placement": "edge",
        "length": "content"
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

  function test_menuPlacement() {
    const plan = RowTree.plan(menu());
    compare(plan.lead, true);
    compare(plan.levels, [0, 1, 1, 2, 2, 1, 2, 1, 2, 1]);
  }

  function test_andTakesTheLatest() {
    compare(RowTree.plan(menu()).parents[6], 5, "popoutAtWidget {placement, length} sits under length");
  }

  function test_anyOfRoots() {
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

  function test_anyOfSameParent() {
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

  function test_relativeKeys() {
    const rows = [row(["placement"]), row(["open", "onHover"], {
        "../placement": "edge"
      })];
    compare(RowTree.plan(rows).levels, [0, 1], "../ resolves from the object");
    const dotted = [row(["open", "onHover"]), row(["delay"], {
        "open.onHover": true
      })];
    compare(RowTree.plan(dotted).levels, [0, 1], "a dotted key resolves");
  }

  function test_configWideKeysIgnored() {
    const rows = [row(["a"]), row(["b"], {
        "/Foo.bar": true
      }), row(["c"], {
        "$bar.boxed": true
      })];
    compare(RowTree.plan(rows).levels, [0, 0, 0]);
  }

  function test_laterRowIsNoParent() {
    const rows = [row(["a"], {
        "b": true
      }), row(["b"])];
    compare(RowTree.plan(rows).levels, [0, 0]);
  }

  function test_groupShowIfOfANestedObject() {
    const rows = menu();
    compare(RowTree.plan(rows).parents[2], 0, "the nested object's condition names placement");
  }

  function test_leadNeedsAnUnconditionalFirstRow() {
    const rows = menu();
    rows[0] = row(["placement"], {
      "x": true
    });
    compare(RowTree.plan(rows).lead, false);
    const hinted = menu();
    hinted[0].schema["x-hintedIf"] = {
      "/$supports.x": true
    };
    compare(RowTree.plan(hinted).lead, false);
  }

  function test_leadNeedsTwoRows() {
    compare(RowTree.plan([row(["a"])]).lead, false);
  }

  function test_leadNeedsEveryRowUnderIt() {
    const rows = menu();
    rows.push(row(["loose"]));
    compare(RowTree.plan(rows).lead, false);
  }

  function test_empty() {
    const plan = RowTree.plan([]);
    compare(plan.lead, false);
    compare(plan.levels, []);
  }
}
