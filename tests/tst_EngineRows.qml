import QtQuick
import QtTest
import qs.components.methods
import "enginerows/Rows.js" as RowsFile
import "enginerows/Fixtures.js" as Fixtures

// EngineRows, the row runner (tests/EngineRows.qml): the rows of
// enginerows/Rows.js run through it against two fake facades, and every
// failure message and every kind of malformed row is checked through a
// stand-in TestCase that records what is reported instead of failing.
TestCase {
  id: root

  name: "EngineRows"

  // An engine facade: each stage answers with what it was given
  QtObject {
    id: facadeEcho

    readonly property var api: ({
        "echo": {},
        "none": {},
        "maybe": {},
        "list": {},
        "divide": {},
        "watch": {
          "feeds": "reduce"
        },
        "reduce": {}
      })

    function echo(input) {
      if (input.explode)
        throw new Error("boom");
      return {
        "seen": input,
        "answer": input.value === undefined ? null : input.value,
        "told": typeof input.tell === "function" ? input.tell() : null
      };
    }

    function none(input) {
      return null;
    }

    function maybe(input) {
      return input.value === 0 ? undefined : {
        "answer": input.value
      };
    }

    function list(input) {
      return input.list;
    }

    // NaN for 0 over 0
    function divide(input) {
      return input.a / input.b;
    }

    // Answers the events its input holds, which `reduce` is fed
    function watch(input) {
      return {
        "seen": input,
        "events": input.events ?? []
      };
    }

    function reduce(input) {
      return {
        "seen": input,
        "n": (input.prev ? input.prev.n : 0) + 1,
        "got": input.event
      };
    }

    // A function of the facade that its api doesn't list
    function hidden(input) {
      return input;
    }
  }

  // A plain positional helper
  QtObject {
    id: helperPositional

    function moveItem(list, from, to) {
      const out = list.slice();
      out.splice(to, 0, out.splice(from, 1)[0]);
      return out;
    }

    function push(list, item) {
      list.push(item);
      return list;
    }
  }

  // The rows of Rows.js, by the facade they run against
  EngineRows {
    id: facadeRows

    testCase: root
    facade: facadeEcho
    fixtures: Fixtures
    rows: RowsFile.rows.filter(row => row.call in facadeEcho.api)
  }

  EngineRows {
    id: helperRows

    testCase: root
    facade: helperPositional
    rows: RowsFile.rows.filter(row => !(row.call in facadeEcho.api))
  }

  // Runners on rows a test writes: one reporting to the TestCase, one to the
  // stand-ins below
  EngineRows {
    id: scratchRows

    testCase: root
    facade: facadeEcho
    fixtures: Fixtures
  }

  EngineRows {
    id: scratchHelperRows

    testCase: root
    facade: helperPositional
  }

  // Records the failures reported to it
  QtObject {
    id: standIn

    property var calls: []

    function verify(ok, message) {
      if (!ok)
        calls.push(message);
    }
  }

  EngineRows {
    id: standInRows

    testCase: standIn
    facade: facadeEcho
    fixtures: Fixtures
  }

  // Throws on a failed verify like QtTest does
  QtObject {
    id: throwing

    property var calls: []

    function verify(ok, message) {
      if (ok)
        return;
      calls.push(message);
      throw new Error("QtQuickTest::fail");
    }
  }

  EngineRows {
    id: throwingRows

    testCase: throwing
    facade: facadeEcho
  }

  // Runs `rows` through the stand-in: the messages it was told of
  function failuresOf(rows) {
    standIn.calls = [];
    standInRows.rows = rows;
    for (const entry of standInRows.data())
      standInRows.run(entry);
    return standIn.calls;
  }

  function test_rows_data() {
    const out = [];
    for (const entry of facadeRows.data())
      out.push(Object.assign({
        "helper": false
      }, entry));
    for (const entry of helperRows.data())
      out.push(Object.assign({
        "helper": true
      }, entry));
    return out;
  }

  function test_rows(data) {
    (data.helper ? helperRows : facadeRows).run(data);
  }

  function test_a_reordered_array_fails() {
    const failures = failuresOf([
      {
        "id": "DEMO-90",
        "why": "order",
        "call": "list",
        "input": {
          "list": [1, 2]
        },
        "expect": [2, 1]
      }
    ]);
    compare(failures, ["DEMO-90 step 0: [0]: expected 2, got 1"]);
  }

  function test_each_special_key_fails_when_it_does_not_hold_data() {
    return [
      {
        "tag": "$count",
        "expect": {
          "seen": {
            "list": {
              "$count": 5
            }
          }
        }
      },
      {
        "tag": "$less",
        "expect": {
          "answer": {
            "$less": 3
          }
        }
      },
      {
        "tag": "$between",
        "expect": {
          "answer": {
            "$between": [6, 9]
          }
        }
      },
      {
        "tag": "$absent",
        "expect": {
          "answer": {
            "$absent": true
          },
          "seen": {
            "value": 5
          }
        }
      }
    ];
  }

  function test_each_special_key_fails_when_it_does_not_hold(data) {
    const failures = failuresOf([
      {
        "id": "DEMO-91",
        "why": "special",
        "call": "echo",
        "input": {
          "value": 5,
          "list": [1, 2, 3]
        },
        "expect": data.expect
      }
    ]);
    compare(failures.length, 1);
    verify(failures[0].startsWith("DEMO-91 step 0: "), failures[0]);
  }

  function test_a_throw_reports_the_step() {
    const failures = failuresOf([
      {
        "id": "DEMO-92",
        "why": "throw",
        "call": "echo",
        "input": {
          "value": 1
        },
        "steps": [
          {
            "expect": {
              "answer": 1
            }
          },
          {
            "with": {
              "explode": true
            },
            "expect": {
              "answer": 1
            }
          }
        ]
      }
    ]);
    compare(failures, ["DEMO-92 step 1 threw: boom"]);
  }

  function test_a_failing_verify_is_not_reported_as_a_throw() {
    throwing.calls = [];
    throwingRows.rows = [
      {
        "id": "DEMO-93",
        "why": "fails",
        "call": "echo",
        "input": {
          "value": 5
        },
        "expect": {
          "answer": 6
        }
      }
    ];
    try {
      throwingRows.run(throwingRows.data()[0]);
    } catch (e) {}
    compare(throwing.calls.length, 1);
    verify(throwing.calls[0].indexOf("threw") < 0, throwing.calls[0]);
  }

  function test_a_failing_step_message() {
    compare(failuresOf([
      {
        "id": "DEMO-94",
        "why": "path",
        "call": "echo",
        "input": {
          "value": 5
        },
        "expect": {
          "answer": 6
        }
      }
    ]), ["DEMO-94 step 0: answer: expected 6, got 5"]);
    compare(failuresOf([
      {
        "id": "DEMO-95",
        "why": "no path",
        "call": "none",
        "input": {},
        "expect": 5
      }
    ]), ["DEMO-95 step 0: output: expected 5, got null"]);
    compare(failuresOf([
      {
        "id": "DEMO-96",
        "why": "not a number",
        "call": "divide",
        "input": {
          "a": 0,
          "b": 0
        },
        "expect": 1
      }
    ]), ["DEMO-96 step 0: output: expected 1, got NaN"]);
  }

  // Each kind of row the grammar refuses: `rows` as JSON, and the one
  // failure's whole message
  function test_a_malformed_row_fails_once_data() {
    return [
      {
        "tag": "a repeated id",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1},"expect":{"answer":1}},{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1},"expect":{"answer":1}}]',
        "message": "DEMO-50: repeated id"
      },
      {
        "tag": "call missing",
        "rows": '[{"id":"DEMO-50","why":"w","input":{"value":1},"expect":{"answer":1}}]',
        "message": "DEMO-50: call is not a function of the facade"
      },
      {
        "tag": "call not a function of the facade",
        "rows": '[{"id":"DEMO-50","why":"w","call":"nothing","input":{"value":1},"expect":{"answer":1}}]',
        "message": "DEMO-50: call is not a function of the facade"
      },
      {
        "tag": "call not in the api",
        "rows": '[{"id":"DEMO-50","why":"w","call":"hidden","input":{"value":1},"expect":{"answer":1}}]',
        "message": "DEMO-50: call is not in the facade's api"
      },
      {
        "tag": "both fixture and input",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1},"expect":{"answer":1},"fixture":"withPrev"}]',
        "message": "DEMO-50: a row has exactly one of fixture, input, args"
      },
      {
        "tag": "none of fixture, input, args",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","expect":{"answer":1}}]',
        "message": "DEMO-50: a row has exactly one of fixture, input, args"
      },
      {
        "tag": "args with with",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","expect":{"answer":1},"args":[],"with":{"value":1}}]',
        "message": "DEMO-50: args can't have with"
      },
      {
        "tag": "args with steps",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","args":[],"steps":[{"expect":{"answer":1}}]}]',
        "message": "DEMO-50: args can't have steps"
      },
      {
        "tag": "args on a facade with api",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","expect":{"answer":1},"args":[1]}]',
        "message": "DEMO-50: an engine facade takes one input record, not args"
      },
      {
        "tag": "five args",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","expect":{"answer":1},"args":[1,2,3,4,5]}]',
        "message": "DEMO-50: args holds at most 4 values"
      },
      {
        "tag": "both expect and steps",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1},"expect":{"answer":1},"steps":[{"expect":{"answer":1}}]}]',
        "message": "DEMO-50: a row has exactly one of expect, steps"
      },
      {
        "tag": "neither expect nor steps",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1}}]',
        "message": "DEMO-50: a row has exactly one of expect, steps"
      },
      {
        "tag": "a step now that is not a number",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1},"steps":[{"now":"10","expect":{"answer":1}}]}]',
        "message": "DEMO-50: a step's now is a number"
      },
      {
        "tag": "no literal leaf",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1},"expect":{"answer":{"$absent":true}}}]',
        "message": "DEMO-50: no expect holds a literal value"
      },
      {
        "tag": "an unknown row key",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1},"expect":{"answer":1},"expected":{"answer":1}}]',
        "message": "DEMO-50: unknown key expected"
      },
      {
        "tag": "an unknown step key",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1},"steps":[{"expected":{"answer":1}}]}]',
        "message": "DEMO-50: unknown step key expected"
      },
      {
        "tag": "a bad $ object",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1},"expect":{"answer":{"$less":2,"x":1}}}]',
        "message": "DEMO-50: bad $ object: a $ key can't mix with other keys"
      },
      {
        "tag": "an unknown fixture",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","expect":{"answer":1},"fixture":"nothing"}]',
        "message": "DEMO-50: unknown fixture"
      },
      {
        "tag": "a bad id",
        "rows": '[{"id":"demo-1","why":"w","call":"echo","input":{"value":1},"expect":{"answer":1}}]',
        "message": "demo-1: bad id"
      },
      {
        "tag": "a missing id",
        "rows": '[{"why":"w","call":"echo","input":{"value":1},"expect":{"answer":1}}]',
        "message": "row 0: id is missing"
      },
      {
        "tag": "an empty why",
        "rows": '[{"id":"DEMO-50","why":"","call":"echo","input":{"value":1},"expect":{"answer":1}}]',
        "message": "DEMO-50: why is empty"
      },
      {
        "tag": "prev in a steps row's with",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1},"steps":[{"expect":{"answer":1}}],"with":{"prev":{}}}]',
        "message": "DEMO-50: with can't write prev"
      },
      {
        "tag": "prev in a feed row's with.<stage>",
        "rows": '[{"id":"DEMO-50","why":"w","call":"watch","input":{},"steps":[{"with":{"watch":{"prev":{}}},"expect":{"reduce":null}}]}]',
        "message": "DEMO-50: with can't write prev"
      },
      {
        "tag": "event in a feed row's with.<fed>",
        "rows": '[{"id":"DEMO-50","why":"w","call":"watch","input":{},"steps":[{"with":{"reduce":{"event":{}}},"expect":{"reduce":null}}]}]',
        "message": "DEMO-50: with can't write event"
      },
      {
        "tag": "event in a feed row's input.<fed>",
        "rows": '[{"id":"DEMO-50","why":"w","call":"watch","input":{"reduce":{"event":{}}},"expect":{"reduce":null}}]',
        "message": "DEMO-50: input can't write event"
      },
      {
        "tag": "a feed row's input with a key that is no stage",
        "rows": '[{"id":"DEMO-50","why":"w","call":"watch","input":{"other":1},"expect":{"reduce":null}}]',
        "message": "DEMO-50: input has other, which is no stage of the feed"
      },
      {
        "tag": "a feed row's with with a key that is no stage",
        "rows": '[{"id":"DEMO-50","why":"w","call":"watch","input":{},"steps":[{"with":{"other":1},"expect":{"reduce":null}}]}]',
        "message": "DEMO-50: with has other, which is no stage of the feed"
      },
      {
        "tag": "an input that is not an object",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":5,"expect":{"answer":1}}]',
        "message": "DEMO-50: input is not an object"
      },
      {
        "tag": "args that are not an array",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","args":5,"expect":{"answer":1}}]',
        "message": "DEMO-50: args is not an array"
      },
      {
        "tag": "steps that are not an array",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1},"steps":{}}]',
        "message": "DEMO-50: steps is not an array"
      },
      {
        "tag": "a step that is not an object",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1},"steps":[5]}]',
        "message": "DEMO-50: a step is an object"
      },
      {
        "tag": "a row's with that is not an object",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1},"with":5,"expect":{"answer":1}}]',
        "message": "DEMO-50: with is not an object"
      },
      {
        "tag": "a step's with that is not an object",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1},"steps":[{"with":5,"expect":{"answer":1}}]}]',
        "message": "DEMO-50: with is not an object"
      },
      {
        "tag": "a feed row's expect that is not an object",
        "rows": '[{"id":"DEMO-50","why":"w","call":"watch","input":{},"expect":5}]',
        "message": "DEMO-50: expect is keyed by stage"
      },
      {
        "tag": "$count not a number",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1},"expect":{"answer":{"$count":"x"}}}]',
        "message": "DEMO-50: bad $ object: $count takes a number"
      },
      {
        "tag": "$less not a number",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1},"expect":{"answer":{"$less":"x"}}}]',
        "message": "DEMO-50: bad $ object: $less takes a number"
      },
      {
        "tag": "$between not two numbers",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1},"expect":{"answer":{"$between":[1]}}}]',
        "message": "DEMO-50: bad $ object: $between takes an array of two numbers"
      },
      {
        "tag": "$absent not true",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1},"expect":{"answer":{"$absent":1}}}]',
        "message": "DEMO-50: bad $ object: $absent takes true"
      },
      {
        "tag": "an unknown $ key",
        "rows": '[{"id":"DEMO-50","why":"w","call":"echo","input":{"value":1},"expect":{"answer":{"$other":1}}}]',
        "message": "DEMO-50: bad $ object: unknown key $other"
      }
    ];
  }

  function test_a_malformed_row_fails_once(data) {
    standInRows.rows = JSON.parse(data.rows);
    const entries = standInRows.data();
    compare(entries.filter(entry => entry.error !== "").length, 1);
    verify(entries[entries.length - 1].error !== "");
    const failures = failuresOf(JSON.parse(data.rows));
    compare(failures.length, 1);
    compare(failures[0], data.message);
  }

  function test_difference_of_returns_the_first_differing_path() {
    const difference = facadeRows.differenceOf({
      "a": {
        "b": [1,
          {
            "c": 2
          }
        ]
      },
      "d": 1
    }, {
      "a": {
        "b": [1,
          {
            "c": 3
          }
        ]
      },
      "d": 2
    });
    compare(JSON.stringify(difference), '{"path":"a.b[1].c","expected":3,"actual":2}');
    compare(facadeRows.differenceOf({
      "a": 1,
      "b": 2
    }, {
      "a": 1
    }), null);
  }

  function test_difference_of_reports_a_bad_special_object() {
    const difference = facadeRows.differenceOf(1, {
      "$less": 2,
      "x": 1
    });
    verify(difference !== null);
    compare(JSON.stringify(difference.expected), '{"$less":2,"x":1}');
    compare(difference.actual, 1);
  }

  function test_an_args_row_leaves_its_array_unchanged() {
    const row = {
      "id": "DEMO-96",
      "why": "args",
      "call": "push",
      "args": [["a"], "b"],
      "expect": ["a", "b"]
    };
    const before = Utils.clone(row.args);
    scratchHelperRows.rows = [row];
    scratchHelperRows.run(scratchHelperRows.data()[0]);
    verify(Utils.deepEqual(row.args, before));
  }

  function test_with_never_mutates_the_fixture_or_the_row() {
    const rows = [
      {
        "id": "DEMO-97",
        "why": "fixture row",
        "call": "echo",
        "fixture": "withPrev",
        "with": {
          "extra": {
            "k": 1
          }
        },
        "steps": [
          {
            "with": {
              "extra": {
                "k": 2
              }
            },
            "expect": {
              "seen": {
                "extra": {
                  "k": 2
                }
              }
            }
          },
          {
            "with": {
              "value": 7
            },
            "expect": {
              "answer": 7
            }
          }
        ]
      },
      {
        "id": "DEMO-98",
        "why": "input row",
        "call": "echo",
        "input": {
          "o": {
            "a": 1
          }
        },
        "with": {
          "o": {
            "a": 2
          }
        },
        "steps": [
          {
            "with": {
              "o": {
                "b": 3
              }
            },
            "expect": {
              "seen": {
                "o": {
                  "a": 2,
                  "b": 3
                }
              }
            }
          }
        ]
      }
    ];
    const before = Utils.clone(rows);
    scratchRows.rows = rows;
    for (const entry of scratchRows.data())
      scratchRows.run(entry);
    verify(Utils.deepEqual(rows, before));
  }
}
