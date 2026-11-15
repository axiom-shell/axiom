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
        "WindowRules": {
          "type": "object",
          "properties": {
            "rules": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "id": {
                    "type": "string"
                  },
                  "name": {
                    "type": "string"
                  },
                  "windows": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "properties": {
                        "inner": {
                          "type": "string",
                          "x-ref": {
                            "kind": "specialWorkspace",
                            "usedBy": "no",
                            "name": "name"
                          }
                        }
                      }
                    }
                  },
                  "window": {
                    "type": "object",
                    "properties": {
                      "special": {
                        "type": "object",
                        "properties": {
                          "id": {
                            "type": "string",
                            "x-ref": {
                              "kind": "specialWorkspace",
                              "usedBy": "Used by window rule {0}",
                              "name": "name"
                            }
                          }
                        }
                      }
                    }
                  },
                  "shell": {
                    "type": "object",
                    "properties": {
                      "pauseBinds": {
                        "type": "object",
                        "properties": {
                          "binds": {
                            "type": "array",
                            "items": {
                              "type": "string"
                            },
                            "x-ref": {
                              "kind": "keybind",
                              "usedBy": "Used by window rule {0}",
                              "name": "name"
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
        "field": ["argument"],
        "many": false,
        "key": "argument",
        "when": {
          "action": ["toggleSpecial"]
        },
        "usedBy": "Used by keybind {0}",
        "name": "key",
        "nameLabels": {}
      },
      {
        "path": ["WindowRules", "rules"],
        "field": ["window", "special", "id"],
        "many": false,
        "key": "window.special.id",
        "when": {},
        "usedBy": "Used by window rule {0}",
        "name": "name",
        "nameLabels": {}
      }
    ], "a $ref'd item and a nested field, not the lists inside lists nor arrays of objects");
    compare(SchemaRefs.sites(schema, "keybind"), [
      {
        "path": ["WindowRules", "rules"],
        "field": ["shell", "pauseBinds", "binds"],
        "many": true,
        "key": "shell.pauseBinds.binds",
        "when": {},
        "usedBy": "Used by window rule {0}",
        "name": "name",
        "nameLabels": {}
      }
    ], "an array of ids");
    compare(SchemaRefs.sites(schema, "other").map(s => s.path), [["Nested", "inner", "list"]], "through nested objects");
    compare(SchemaRefs.sites(schema, "none"), []);
    compare(SchemaRefs.sites(null, "specialWorkspace"), []);
  }

  function test_references() {
    const sites = SchemaRefs.sites(schema, "keybind").concat(SchemaRefs.sites(schema, "specialWorkspace").slice(1));
    const config = {
      "WindowRules": {
        "rules": [
          {
            "id": "a",
            "name": "Games",
            "shell": {
              "pauseBinds": {
                "binds": ["x", "", "y", 5]
              }
            },
            "window": {
              "special": {
                "id": "gaming"
              }
            }
          },
          {
            "id": "b",
            "name": "",
            "window": {
              "special": {
                "id": ""
              }
            }
          },
          {
            "id": "c",
            "name": "",
            "shell": {
              "pauseBinds": {
                "binds": ["z"]
              }
            }
          }
        ]
      }
    };
    compare(SchemaRefs.references(config, sites).map(r => r.id + "@" + r.name), ["x@Games", "y@Games", "z@c", "gaming@Games"], "an array's ids, a nested field, the id for an empty name");
    compare(SchemaRefs.references({}, sites), []);
    compare(SchemaRefs.references(null, null), []);
  }

  // The built schema's sites: the keybinds' and hot corners' argument, a rule's special workspace; a rule's paused shortcuts
  function test_builtSchema() {
    const built = repo.json("qml/config/json/config.schema.json");
    compare(SchemaRefs.sites(built, "specialWorkspace").map(s => s.path.join(".") + ":" + s.key), ["Keybinds.binds:argument", "WindowRules.rules:window.special.id", "HotCorners.items:argument"]);
    compare(SchemaRefs.sites(built, "keybind").map(s => s.path.join(".") + ":" + s.key), ["WindowRules.rules:shell.pauseBinds.binds"]);
    compare(SchemaRefs.sites(built, "specialWorkspace").map(s => s.nameLabels.topLeft ?? ""), ["", "", "Top left"], "the hot corner's titles, not its raw key");
  }
}
