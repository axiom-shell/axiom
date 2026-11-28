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

  function test_record_keeps_last_per_stage() {
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

  function test_records_of_returns_every_stage() {
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

  function test_forget_drops_all_stages_of_an_id() {
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

  function test_ids_of_is_sorted() {
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

  function test_record_inside_binding_notifies_nothing() {
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

  function test_tracing_is_off_by_default_and_set() {
    EngineTrace.setTracing(false);
    verify(EngineTrace.tracing === false);
    EngineTrace.setTracing(true);
    verify(EngineTrace.tracing === true);
  }

  function test_record_while_off_keeps_nothing() {
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

  function test_records_of_unknown_id_is_empty() {
    compare(EngineTrace.recordsOf("unknown", "x"), {});
  }

  function test_records_of_returns_a_copy() {
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

  function test_recording_binding_reruns_when_tracing_turns_on() {
    EngineTrace.setTracing(false);
    const o = createTemporaryObject(rerunComp, root);
    compare(o.seen, {});
    EngineTrace.setTracing(true);
    verify(o.seen.s !== undefined);
    compare(o.seen.s.output, 2);
  }

  function test_reserved_names_are_ordinary_keys() {
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

  function test_reserved_stages_are_ordinary_keys() {
    for (const stage of ["__proto__", "toString", "constructor"])
      EngineTrace.record({
        "engine": "rstage",
        "stage": stage,
        "id": "a",
        "input": 1,
        "output": 2
      });
    const r = EngineTrace.recordsOf("rstage", "a");
    compare(Object.keys(r).sort(), ["__proto__", "constructor", "toString"]);
    compare(r["__proto__"].output, 2);
    compare(r.toString.output, 2);
    verify(Object.getPrototypeOf(r) === Object.prototype);
    EngineTrace.forget({
      "engine": "rstage",
      "id": "a"
    });
    compare(EngineTrace.recordsOf("rstage", "a"), {});
  }

  function test_ipc_target_is_engines() {
    compare(EngineTrace._ipc.target, "engines");
    compare(BackendManager._targets.length, 1);
  }

  function test_ipc_list_answers_sorted_ids() {
    for (const id of ["b", "a"])
      EngineTrace.record({
        "engine": "ipclist",
        "stage": "s",
        "id": id,
        "input": 1,
        "output": 2
      });
    compare(EngineTrace._ipc.list("ipclist"), '["a","b"]');
    compare(EngineTrace._ipc.list("ipcunknown"), "[]");
  }

  function test_ipc_explain_answers_records() {
    EngineTrace.record({
      "engine": "ipcexplain",
      "stage": "s",
      "id": "a",
      "input": 1,
      "output": 2
    });
    compare(EngineTrace._ipc.explain("ipcexplain", "a"), JSON.stringify(EngineTrace.recordsOf("ipcexplain", "a")));
    compare(EngineTrace._ipc.explain("ipcexplain", "none"), "{}");
  }

  function test_ipc_explain_keeps_reserved_stages() {
    for (const stage of ["__proto__", "toString"])
      EngineTrace.record({
        "engine": "ipcreserved",
        "stage": stage,
        "id": "a",
        "input": 1,
        "output": 2
      });
    const json = EngineTrace._ipc.explain("ipcreserved", "a");
    compare(json, JSON.stringify(EngineTrace.recordsOf("ipcreserved", "a")));
    compare(Object.keys(JSON.parse(json)).sort(), ["__proto__", "toString"]);
  }

  function test_ipc_enable_disable_toggle_status() {
    EngineTrace._ipc.disable();
    verify(EngineTrace.tracing === false);
    verify(EngineTrace._ipc.status() === false);
    EngineTrace._ipc.enable();
    verify(EngineTrace.tracing === true);
    verify(EngineTrace._ipc.status() === true);
    EngineTrace._ipc.toggle();
    verify(EngineTrace.tracing === false);
    EngineTrace._ipc.toggle();
    verify(EngineTrace.tracing === true);
  }
}
