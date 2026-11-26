pragma Singleton

import QtQuick

// EngineTrace: while tracing is on, keeps the last input and output of each engine stage per id, so a
// decision can be explained afterwards. Recording notifies nothing, so an adapter may call it from a
// binding; reading `tracing` makes a recording binding re-run when it toggles, so turning it on fills the
// trace at once. Outside this file and the tests only `.record(`, `.forget(` and `.tracing` are used
// (check_engines › trace).
QtObject {
  id: root

  // Mutated in place, never reassigned, so a record inside a binding notifies nothing (qml-pitfalls.md:
  // plain objects only, a Map in a singleton's var crashes the GC): {engine: {id: {stage: {input, output}}}}
  property var _store: Object.create(null)
  property bool _tracing: false
  readonly property bool tracing: root._tracing

  // entry: {engine, stage, id, input, output}; the values as given
  function record(entry) {
    if (!root._tracing)
      return;
    const byId = root._store[entry.engine] ?? (root._store[entry.engine] = Object.create(null));
    const byStage = byId[entry.id] ?? (byId[entry.id] = Object.create(null));
    byStage[entry.stage] = {
      "input": entry.input,
      "output": entry.output
    };
  }

  // entry: {engine, id}; works whether or not tracing is on, so an id destroyed while tracing was off
  // never comes back
  function forget(entry) {
    delete root._store[entry.engine]?.[entry.id];
    if (root._store[entry.engine] && Object.keys(root._store[entry.engine]).length === 0)
      delete root._store[entry.engine];
  }

  // -> {stage: {input, output}}, a copy; {} when none
  function recordsOf(engine, id) {
    const out = {};
    const byStage = root._store[engine]?.[id] ?? {};
    for (const stage of Object.keys(byStage))
      Object.defineProperty(out, stage, {
        "value": {
          "input": byStage[stage].input,
          "output": byStage[stage].output
        },
        "enumerable": true,
        "writable": true,
        "configurable": true
      });
    return out;
  }

  function idsOf(engine) {
    return Object.keys(root._store[engine] ?? {}).sort();
  }

  // A plain setter: no owner argument, unlike a registry's acquire(owner)/release(owner)
  function setTracing(on) {
    root._tracing = on === true;
  }
}
