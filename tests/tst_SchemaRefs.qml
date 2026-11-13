import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "SchemaRefs"

  RepoFiles {
    id: repo
  }

  readonly property var schema: ({
      "definitions": {
        "Keybind": {
          "type": "object",
          "properties": {
            "argument": {
              "type": "string",
              "x-ref": {
                "kind": "specialWorkspace",
                "when": {
                  "action": ["toggleSpecial"]
                },
                "usedBy": "Used by keybind {0}",
                "name": "key"
              }
            },
            "key": {
              "type": "string"
            }
          }
        }
      },
      "properties": {
        "Keybinds": {
          "type": "object",
          "properties": {
            "binds": {
              "type": "array",
              "items": {
                "$ref": "#/definitions/Keybind"
              }
            },
            "presets": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "binds": {
                    "type": "array",
                    "items": {
                      "$ref": "#/definitions/Keybind"
                    }
                  }
                }
              }
            }
          }
        },
        "Nested": {
          "type": "object",
          "properties": {
            "inner": {
              "type": "object",
              "properties": {
                "list": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "target": {
                        "type": "string",
                        "x-ref": {
                          "kind": "other",
                          "usedBy": "Used by {0}",
                          "name": "id"
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    })

  function test_sites() {
    compare(SchemaRefs.sites(schema, "specialWorkspace"), [
      {
        "path": ["Keybinds", "binds"],
        "key": "argument",
        "when": {
          "action": ["toggleSpecial"]
        },
        "usedBy": "Used by keybind {0}",
        "name": "key",
        "nameLabels": {}
      }
    ], "a $ref'd item, not the lists inside lists");
    compare(SchemaRefs.sites(schema, "other").map(s => s.path), [["Nested", "inner", "list"]], "through nested objects");
    compare(SchemaRefs.sites(schema, "none"), []);
    compare(SchemaRefs.sites(null, "specialWorkspace"), []);
  }

  // The built schema's sites are exactly the keybinds' and hot corners' argument
  function test_builtSchema() {
    const built = repo.json("qml/config/json/config.schema.json");
    compare(SchemaRefs.sites(built, "specialWorkspace").map(s => s.path.join(".") + ":" + s.key), ["Keybinds.binds:argument", "HotCorners.items:argument"]);
    compare(SchemaRefs.sites(built, "specialWorkspace").map(s => s.nameLabels.topLeft ?? ""), ["", "Top left"], "the hot corner's titles, not its raw key");
  }
}
