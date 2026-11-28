import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "StateShape"

  function test_accept_same_kind() {
    compare(StateShape.accept([1], []), [1]);
    compare(StateShape.accept({
      "a": 1
    }, {}), {
      "a": 1
    });
    compare(StateShape.accept(3, 0), 3);
    compare(StateShape.accept("x", ""), "x");
    compare(StateShape.accept(true, false), true);
  }

  function test_accept_other_kind() {
    compare(StateShape.accept({}, []), [], "object for array");
    compare(StateShape.accept([], {}), {}, "array for object");
    compare(StateShape.accept(null, {}), {}, "null for object");
    compare(StateShape.accept("1", 0), 0, "string for number");
    compare(StateShape.accept(1, ""), "", "number for string");
    compare(StateShape.accept(null, []), [], "null for array");
  }

  function test_null_fallback() {
    compare(StateShape.accept({
      "a": 1
    }, null), {
      "a": 1
    });
    compare(StateShape.accept([1], null), [1]);
    compare(StateShape.accept(5, null), null);
    compare(StateShape.accept("s", null), null);
    compare(StateShape.accept(null, null), null);
  }

  function test_undefined_fallback() {
    compare(StateShape.accept({
      "a": 1
    }, undefined), {
      "a": 1
    });
    compare(StateShape.accept(5, undefined), undefined);
    compare(StateShape.accept("s", undefined), undefined);
    compare(StateShape.accept(null, undefined), undefined);
    compare(StateShape.parse("{\"a\":1}", undefined).value, {
      "a": 1
    });
    compare(StateShape.parse("5", undefined).value, undefined);
    compare(StateShape.parse("\"s\"", undefined).value, undefined);
    compare(StateShape.parse("null", undefined).value, undefined);
  }

  function test_clear_shaped_fallback() {
    const clear = {
      "failures": 0,
      "lastHash": ""
    };
    compare(StateShape.accept([], clear), clear);
    compare(StateShape.accept({
      "failures": 2
    }, clear), {
      "failures": 2
    });
  }

  function test_parse_empty() {
    compare(StateShape.parse(null, {}), {
      "value": {},
      "corrupt": false
    });
    compare(StateShape.parse(undefined, []), {
      "value": [],
      "corrupt": false
    });
    compare(StateShape.parse("", []), {
      "value": [],
      "corrupt": false
    });
  }

  function test_parse_bad_json() {
    compare(StateShape.parse("{oops", {
      "a": 1
    }), {
      "value": {
        "a": 1
      },
      "corrupt": true
    });
  }

  function test_parse_ok() {
    compare(StateShape.parse("{\"a\": 2}", {}), {
      "value": {
        "a": 2
      },
      "corrupt": false
    });
  }

  function test_parse_wrong_kind_is_not_corrupt() {
    compare(StateShape.parse("[1]", {}), {
      "value": {},
      "corrupt": false
    });
    compare(StateShape.parse("null", {}), {
      "value": {},
      "corrupt": false
    }, "JSON null");
    compare(StateShape.parse("null", null), {
      "value": null,
      "corrupt": false
    });
    compare(StateShape.parse("7", null), {
      "value": null,
      "corrupt": false
    });
  }
}
