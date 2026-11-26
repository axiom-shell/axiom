import QtQuick
import QtTest
import qs.services.core

// EngineTrace: keeps the last input and output per (engine, stage, id) while tracing is on, answers them
// as copies, and notifies nothing when it records. Each test uses its own engine name: the singleton is
// shared across the functions.
TestCase {
  id: root

  name: "EngineTrace"

  // Built inside a test, with tracing on: its binding records and reads
  Component {
    id: boundComp

    QtObject {
      property int changes: 0
      property var seen: {
        EngineTrace.record({
          "engine": "bound",
          "stage": "s",
          "id": "a",
          "input": 1,
          "output": 2
        });
        return EngineTrace.recordsOf("bound", "a");
      }

      onSeenChanged: changes++
    }
  }

  // Built inside a test, with tracing off: its binding records, so turning tracing on re-runs it
  Component {
    id: rerunComp

    QtObject {
      property var seen: {
        EngineTrace.record({
          "engine": "rerun",
          "stage": "s",
          "id": "a",
          "input": 1,
          "output": 2
        });
        return EngineTrace.recordsOf("rerun", "a");
      }
    }
  }

  function initTestCase() {
    failOnWarning(/./);
    verify(EngineTrace.tracing === false);
  }

  function init() {
    failOnWarning(/./);
    EngineTrace.setTracing(true);
  }

  function cleanup() {
    EngineTrace.setTracing(false);
  }

  function test_recordKeepsLastPerStage() {
    EngineTrace.record({
      "engine": "last",
      "stage": "s",
      "id": "a",
      "input": 1,
      "output": 2
    });
    EngineTrace.record({
      "engine": "last",
      "stage": "s",
      "id": "a",
      "input": 3,
      "output": 4
    });
    compare(EngineTrace.recordsOf("last", "a").s.input, 3);
    compare(EngineTrace.recordsOf("last", "a").s.output, 4);
  }

  function test_recordsOfReturnsEveryStage() {
    EngineTrace.record({
      "engine": "stages",
      "stage": "s",
      "id": "a",
      "input": 1,
      "output": 2
    });
    EngineTrace.record({
      "engine": "stages",
      "stage": "t",
      "id": "a",
      "input": 5,
      "output": 6
    });
    compare(Object.keys(EngineTrace.recordsOf("stages", "a")).sort(), ["s", "t"]);
    compare(EngineTrace.recordsOf("stages", "a").t.output, 6);
  }

  function test_forgetDropsAllStagesOfAnId() {
    for (const stage of ["s", "t"])
      EngineTrace.record({
        "engine": "forget",
        "stage": stage,
        "id": "a",
        "input": 1,
        "output": 2
      });
    EngineTrace.record({
      "engine": "forget",
      "stage": "s",
      "id": "b",
      "input": 1,
      "output": 2
    });
    EngineTrace.forget({
      "engine": "forget",
      "id": "a"
    });
    compare(EngineTrace.recordsOf("forget", "a"), {});
    verify(EngineTrace.recordsOf("forget", "b").s !== undefined);
    compare(EngineTrace.idsOf("forget"), ["b"]);
  }

  function test_idsOfIsSorted() {
    for (const id of ["c", "a", "b"])
      EngineTrace.record({
        "engine": "sorted",
        "stage": "s",
        "id": id,
        "input": 1,
        "output": 2
      });
    compare(EngineTrace.idsOf("sorted"), ["a", "b", "c"]);
  }

  function test_recordInsideBindingNotifiesNothing() {
    const o = createTemporaryObject(boundComp, root);
    o.changes = 0;
    verify(EngineTrace.recordsOf("bound", "a").s !== undefined);
    EngineTrace.record({
      "engine": "bound",
      "stage": "s",
      "id": "a",
      "input": 3,
      "output": 4
    });
    EngineTrace.record({
      "engine": "bound",
      "stage": "t",
      "id": "a",
      "input": 3,
      "output": 4
    });
    compare(o.changes, 0);
  }

  function test_tracingIsOffByDefaultAndSet() {
    EngineTrace.setTracing(false);
    verify(EngineTrace.tracing === false);
    EngineTrace.setTracing(true);
    verify(EngineTrace.tracing === true);
  }

  function test_recordWhileOffKeepsNothing() {
    EngineTrace.setTracing(false);
    EngineTrace.record({
      "engine": "off",
      "stage": "s",
      "id": "a",
      "input": 1,
      "output": 2
    });
    compare(EngineTrace.recordsOf("off", "a"), {});
    compare(EngineTrace.idsOf("off"), []);
  }

  function test_recordsOfUnknownIdIsEmpty() {
    compare(EngineTrace.recordsOf("unknown", "x"), {});
  }

  function test_recordsOfReturnsACopy() {
    EngineTrace.record({
      "engine": "copy",
      "stage": "s",
      "id": "a",
      "input": 1,
      "output": 2
    });
    const r = EngineTrace.recordsOf("copy", "a");
    r.s.input = 99;
    r.extra = {};
    compare(EngineTrace.recordsOf("copy", "a").s.input, 1);
    compare(Object.keys(EngineTrace.recordsOf("copy", "a")), ["s"]);
  }

  function test_recordingBindingRerunsWhenTracingTurnsOn() {
    EngineTrace.setTracing(false);
    const o = createTemporaryObject(rerunComp, root);
    compare(o.seen, {});
    EngineTrace.setTracing(true);
    verify(o.seen.s !== undefined);
    compare(o.seen.s.output, 2);
  }

  function test_reservedNamesAreOrdinaryKeys() {
    for (const [engine, id] of [["__proto__", "x"], ["reserved", "__proto__"], ["reserved", "toString"], ["reserved", "hasOwnProperty"]]) {
      EngineTrace.record({
        "engine": engine,
        "stage": "s",
        "id": id,
        "input": 1,
        "output": 2
      });
      compare(EngineTrace.recordsOf(engine, id).s.output, 2);
      verify(EngineTrace.idsOf(engine).indexOf(id) >= 0);
      EngineTrace.forget({
        "engine": engine,
        "id": id
      });
      compare(EngineTrace.recordsOf(engine, id), {});
      compare(EngineTrace.idsOf(engine).indexOf(id), -1);
    }
    verify(({}).s === undefined);
    verify(({}).x === undefined);
    verify(typeof ({}).toString === "function");
    verify(typeof ({}).hasOwnProperty === "function");
    verify(Object.keys(Object.prototype).length === 0);
  }
}
