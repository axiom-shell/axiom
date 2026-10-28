import QtQuick
import qs.components.methods

// The cases the JS helpers and the axiom binary (Go) must agree on
// (tests/fixtures/shared/, docs/dev/backend/README.md › Shared fixtures):
// SchemaValidation, which the shell still fills defaults from, against the
// binary's config pipeline, and ConfigOps, the ops the shell's saves send
// (config.set) and its pushes carry. Each op calls one
// helper with JSON arguments and returns a JSON value; the expected output
// is that value's exact bytes (canonical()). Tests call the helpers through
// here: while scripts/dev/fixtures.py records, every call is logged as a
// case, so the inline cases of the tests become shared fixtures without
// being copied by hand. tst_Shared replays them.
QtObject {
  id: root

  // The TestCase whose calls are recorded (its name and current function
  // name the cases)
  property var testCase: null

  // The live schema, which a case names by its path instead of copying it
  readonly property string schemaPath: "config/json/config.schema.json"
  readonly property var schema: _json(schemaPath)

  readonly property bool recording: _read("tests/fixtures/shared/.recording") !== ""
  property int _calls: 0

  // op → function(args) returning the output: the schema's, and every
  // function of the compositor config helpers as "<Helper>.<function>"
  readonly property var ops: root._withHelperOps({
    "schema.applyDefaults": args => SchemaValidation.applyDefaults(args[0], args[1], args.length > 2 ? args[2] : args[1]),
    "schema.resolveRef": args => SchemaValidation.resolveRef(args[0], args[1])
  })

  // ConfigOps (config.set's ops, decoded by the binary's daemon tests) and
  // the bind and layer helpers the axiom binary also ports
  // (backend/internal/compositor/render), still used by the shell itself,
  // by name (the rest went to the binary, their cases frozen there). A test calls one through
  // its proxy here (shared.calls.BindKeys.keyId(…)), which records
  // the call; the helper's properties are read on the helper itself.
  readonly property var helpers: ({
      "BindActions": BindActions,
      "BindKeys": BindKeys,
      "ConfigOps": ConfigOps,
      "KeyNames": KeyNames,
      "LayerStack": LayerStack
    })
  readonly property var calls: _proxies()

  function _functionsOf(helper) {
    const names = [];
    for (const key in helper)
      if (typeof helper[key] === "function" && !key.startsWith("_") && !/Changed$/.test(key) && !["destroyed", "deleteLater", "toString", "objectNameChanged"].includes(key))
        names.push(key);
    return names;
  }

  function _withHelperOps(ops) {
    for (const name in root.helpers) {
      const helper = root.helpers[name];
      for (const fn of _functionsOf(helper))
        ops[name + "." + fn] = args => helper[fn].apply(helper, args);
    }
    return ops;
  }

  function _proxies() {
    const out = {};
    for (const name in root.helpers) {
      const proxy = {};
      for (const fn of _functionsOf(root.helpers[name]))
        // (a function, not an arrow: qmlformat drops a lone rest
        // parameter's parentheses)
        proxy[fn] = function (...args) {
          return root.call(name + "." + fn, args);
        };
      out[name] = proxy;
    }
    return out;
  }

  // The exact bytes an output is compared by: 2-space JSON, JS key order,
  // a trailing newline (undefined is written as null)
  function canonical(value) {
    return (value === undefined ? "null" : JSON.stringify(value, null, 2)) + "\n";
  }

  // Calls op with args, recording the call while fixtures are recorded. A
  // function among the arguments is recorded as the answers it gave
  // ({"$fn": {"<its arguments as JSON>": answer}}), an undefined one as
  // {"$undefined": true}.
  function call(op, args) {
    if (!recording)
      return ops[op](args);
    const tables = [];
    const recorded = args.map(arg => _recordable(arg, tables));
    const called = args.map(arg => _answering(arg, tables));
    const output = ops[op](called);
    _record(op, _caseText(op, recorded), canonical(output));
    return output;
  }

  // An argument as it's recorded: a copy taken before the call (a helper
  // may change what it's given), each function a table its calls fill in
  function _recordable(value, tables) {
    if (value === undefined)
      return {
        "$undefined": true
      };
    if (typeof value === "function") {
      const table = {};
      tables.push({
        "fn": value,
        "table": table
      });
      return {
        "$fn": table
      };
    }
    if (value === null || typeof value !== "object" || value === root.schema)
      return value;
    if (Array.isArray(value))
      return value.map(v => _recordable(v, tables));
    const out = {};
    for (const key in value)
      if (value[key] !== undefined)
        out[key] = _recordable(value[key], tables);
    return out;
  }

  // The argument passed on: each function wrapped to note what it answers
  function _answering(value, tables) {
    if (typeof value === "function") {
      const entry = tables.find(t => t.fn === value);
      return function (...a) {
        const answer = value(...a);
        entry.table[JSON.stringify(a)] = answer === undefined ? {
          "$undefined": true
        } : answer;
        return answer;
      };
    }
    // The caller's own value (a helper may fill it in) unless it holds a
    // function to wrap
    if (!_holdsFunction(value) || value === root.schema)
      return value;
    if (Array.isArray(value))
      return value.map(v => _answering(v, tables));
    const out = {};
    for (const key in value)
      out[key] = _answering(value[key], tables);
    return out;
  }

  function _holdsFunction(value) {
    if (typeof value === "function")
      return true;
    if (value === null || typeof value !== "object")
      return false;
    for (const key in value)
      if (_holdsFunction(value[key]))
        return true;
    return false;
  }

  // A recorded case's arguments with blobs resolved
  function resolveArgs(args) {
    return _resolve(JSON.parse(JSON.stringify(args)));
  }

  // The helpers, by their own names, for the tests to call

  function applyDefaults(value, schema, rootSchema) {
    return call("schema.applyDefaults", rootSchema === undefined ? [value, schema] : [value, schema, rootSchema]);
  }
  function resolveRef(schema, rootSchema) {
    return call("schema.resolveRef", [schema, rootSchema]);
  }

  // --- recording ---

  function _caseText(op, args) {
    return JSON.stringify({
      "op": op,
      "args": args.map(arg => arg === root.schema ? {
          "$repoFile": root.schemaPath
        } : arg)
    }, null, 2) + "\n";
  }

  // Logs one call for scripts/dev/fixtures.py. The payload goes as hex
  // UTF-16 code units: Qt's logging re-encodes text, which would change
  // the bytes the case is compared by.
  function _record(op, caseText, expectedText) {
    const results = testCase?.qtest_results;
    const payload = JSON.stringify({
      "suite": op.split(".")[0],
      "test": testCase?.name ?? "",
      "function": results?.functionName ?? "",
      "tag": results?.dataTag ?? "",
      "label": "",
      "index": _calls++,
      "case": caseText,
      "expected": expectedText
    });
    let hex = "";
    for (let i = 0; i < payload.length; i++)
      hex += ("000" + payload.charCodeAt(i).toString(16)).slice(-4);
    console.log("@@FIXTURE " + hex);
  }

  function _resolve(value) {
    if (value === null || typeof value !== "object")
      return value;
    if (!Array.isArray(value) && value.$undefined === true && Object.keys(value).length === 1)
      return undefined;
    // A recorded function: its answers, by its arguments
    if (!Array.isArray(value) && value.$fn !== undefined && Object.keys(value).length === 1) {
      const table = _resolve(value.$fn);
      return function (...a) {
        return table[JSON.stringify(a)];
      };
    }
    // Large arguments are stored once, by hash (scripts/dev/fixtures.py)
    if (!Array.isArray(value) && typeof value.$blob === "string" && Object.keys(value).length === 1)
      return _resolve(_json("tests/fixtures/shared/blobs/" + value.$blob + ".json"));
    if (!Array.isArray(value) && typeof value.$repoFile === "string" && Object.keys(value).length === 1)
      return value.$repoFile === root.schemaPath ? root.schema : _json(value.$repoFile);
    if (Array.isArray(value))
      return value.map(v => _resolve(v));
    for (const key in value)
      value[key] = _resolve(value[key]);
    return value;
  }

  // Files by path from the repo root (as RepoFiles, which this can't use
  // from its own bindings: they may run before a child object exists)
  function _read(path) {
    const xhr = new XMLHttpRequest();
    xhr.open("GET", Qt.resolvedUrl("../" + path), false);
    xhr.send();
    return xhr.responseText;
  }

  function _json(path) {
    const text = _read(path);
    if (text === "")
      throw new Error("empty or unreadable: " + path);
    return JSON.parse(text);
  }
}
