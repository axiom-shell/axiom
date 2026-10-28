import QtQuick
import QtTest
import qs.components.methods

TestCase {
  id: test
  name: "SchemaValidation"

  // Records the helper calls as shared fixtures (Shared.qml)
  Shared {
    id: shared
    testCase: test
  }

  readonly property var schema: ({
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "size": {
          "type": "integer",
          "default": 10,
          "minimum": 1,
          "maximum": 20
        },
        "mode": {
          "type": "string",
          "default": "a",
          "enum": ["a", "b"]
        },
        "nested": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "on": {
              "type": "boolean",
              "default": true
            }
          }
        },
        "widgets": {
          "type": "array",
          "default": [],
          "items": {
            "$ref": "#/definitions/Widget"
          }
        },
        "free": {
          "type": "object",
          "additionalProperties": {
            "type": "integer"
          }
        }
      },
      "definitions": {
        "Widget": {
          "oneOf": [
            {
              "$ref": "#/definitions/Clock"
            },
            {
              "$ref": "#/definitions/Label"
            }
          ]
        },
        "Clock": {
          "type": "object",
          "additionalProperties": false,
          "required": ["type"],
          "properties": {
            "type": {
              "const": "Clock"
            },
            "format": {
              "type": "string",
              "default": "HH:mm"
            }
          }
        },
        "Label": {
          "type": "object",
          "additionalProperties": false,
          "required": ["type", "text"],
          "properties": {
            "type": {
              "const": "Label"
            },
            "text": {
              "type": "string"
            }
          }
        }
      }
    })

  function test_defaults_fill_everything() {
    const filled = shared.applyDefaults({}, schema);
    compare(filled.size, 10);
    compare(filled.mode, "a");
    compare(filled.nested.on, true);
    compare(filled.widgets.length, 0);
  }

  function test_defaults_keep_values_and_do_not_mutate() {
    const input = {
      "size": 3,
      "nested": {
        "on": false
      }
    };
    const filled = shared.applyDefaults(input, schema);
    compare(filled.size, 3);
    compare(filled.nested.on, false);
    compare(input.mode, undefined);
  }

  function test_defaults_follow_oneOf_by_type() {
    const filled = shared.applyDefaults({
      "widgets": [
        {
          "type": "Clock"
        },
        {
          "type": "Label",
          "text": "hi"
        }
      ]
    }, schema);
    compare(filled.widgets[0].format, "HH:mm");
    compare(filled.widgets[1].format, undefined);
  }

  // Keys beside a $ref override the definition's: one definition, two
  // defaults (Lockscreen.layout and Greeter.layout share ScreenLayout)
  function test_ref_siblings_override_the_definition() {
    const twoDefaults = {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "a": {
          "$ref": "#/definitions/Box",
          "default": {
            "items": ["a"]
          }
        },
        "b": {
          "$ref": "#/definitions/Box",
          "default": {
            "items": ["b"]
          }
        },
        "plain": {
          "$ref": "#/definitions/Box"
        }
      },
      "definitions": {
        "Box": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "size": {
              "type": "integer",
              "default": 2
            },
            "items": {
              "type": "array",
              "default": [],
              "items": {
                "type": "string"
              }
            }
          }
        }
      }
    };
    const filled = shared.applyDefaults({}, twoDefaults);
    compare(filled.a.items, ["a"]);
    compare(filled.b.items, ["b"]);
    compare(filled.a.size, 2);
    compare(filled.plain.items, []);
    // A value that is there keeps its own, and fills only what's missing
    compare(shared.applyDefaults({
      "a": {
        "size": 5
      }
    }, twoDefaults).a.items, []);
  }
}
