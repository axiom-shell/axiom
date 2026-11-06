import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "DevDiff"

  function test_checkout() {
    compare(DevDiff.checkout("main", "0123456789abcdef", false), "main@0123456");
    compare(DevDiff.checkout("main", "0123456789abcdef", true), "main@0123456*");
    compare(DevDiff.checkout("", "0123456789abcdef", false), "0123456", "a detached head: the commit");
    compare(DevDiff.checkout("main", "", false), "", "no commit: nothing");
  }

  readonly property var schema: ({
      "properties": {
        "Bars": {
          "type": "object",
          "title": "Bars",
          "properties": {
            "items": {
              "type": "array",
              "items": {
                "$ref": "#/definitions/Bar"
              }
            }
          }
        },
        "Appearance": {
          "type": "object",
          "properties": {
            "font": {
              "type": "object",
              "title": "Font",
              "properties": {
                "size": {
                  "type": "integer",
                  "title": "Size"
                }
              }
            }
          }
        }
      },
      "definitions": {
        "Bar": {
          "type": "object",
          "properties": {
            "height": {
              "type": "integer",
              "title": "Height"
            },
            "widgets": {
              "type": "array",
              "items": {
                "oneOf": [
                  {
                    "$ref": "#/definitions/ClockW"
                  },
                  {
                    "$ref": "#/definitions/DateW"
                  }
                ]
              }
            }
          }
        },
        "ClockW": {
          "properties": {
            "seconds": {
              "title": "Seconds"
            },
            "format": {
              "title": "Time format"
            }
          }
        },
        "DateW": {
          "properties": {
            "format": {
              "title": "Date format"
            }
          }
        }
      }
    })

  // Titles from the schema (a `$ref` followed), keys without one, an
  // item by its id; unknown keys (a setting live has and dev's schema
  // doesn't) by name
  function test_titleParts() {
    compare(DevDiff.titleParts(schema, ["Appearance", "font", "size"]), [
      {
        "text": "Appearance",
        "schema": false
      },
      {
        "text": "Font",
        "schema": true
      },
      {
        "text": "Size",
        "schema": true
      }
    ]);
    compare(DevDiff.titleParts(schema, ["Bars", "items",
      {
        "id": "top"
      },
      "height"]).map(part => part.text), ["Bars", "items", "top", "Height"]);
    // An item of a oneOf: a key titled when its options agree
    const widget = key => DevDiff.titleParts(schema, ["Bars", "items",
        {
          "id": "top"
        },
        "widgets",
        {
          "id": "w"
        },
        key]).map(part => part.text).pop();
    compare([widget("seconds"), widget("format")], ["Seconds", "format"]);
    compare(DevDiff.titleParts(schema, ["Gone", "old"]).map(part => [part.text, part.schema]), [["Gone", false], ["old", false]]);
  }

  // A string as it is, anything else as JSON on one line, long ones cut;
  // a side without the key has none
  function test_valueText() {
    const row = {
      "path": ["A"],
      "side": "dev",
      "dev": "foot",
      "live": {
        "a": [1, 2]
      },
      "devOnly": false
    };
    compare(DevDiff.valueText(row, "dev"), "foot");
    compare(DevDiff.valueText(row, "live"), "{\"a\":[1,2]}");
    compare(DevDiff.valueText({
      "dev": false
    }, "dev"), "false");
    compare(DevDiff.valueText({
      "dev": null
    }, "dev"), "null", "a null value is one");
    verify(!DevDiff.has({
      "dev": 1
    }, "live"));
    compare(DevDiff.valueText({
      "dev": 1
    }, "live"), "");
    const long = DevDiff.valueText({
      "dev": "x".repeat(200)
    }, "dev");
    compare(long.length, DevDiff.valueLength);
    verify(long.endsWith("…"));
    compare(DevDiff.valueText({
      "dev": "a\n  b"
    }, "dev"), "a b", "one line");
  }

  function test_sides() {
    compare(DevDiff.sideLabel("dev"), "Changed in dev");
    compare(DevDiff.sideLabel("live"), "Changed in live");
    compare(DevDiff.sideLabel("both"), "Changed in both");
    compare(DevDiff.sideLabel("other"), "");
    verify(DevDiff.toLive({
      "devOnly": false
    }));
    verify(!DevDiff.toLive({
      "devOnly": true
    }), "a dev-only setting stays in dev");
  }
}
