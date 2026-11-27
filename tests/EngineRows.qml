import QtQuick
import qs.components.methods

// The one runner of contract rows (docs/dev/core/engines.md › The row
// format): each row calls a facade function (or a positional helper's) with
// an input built from a fixture or written out, optionally over several
// steps, and compares the answer to what the row expects with the subset
// compare, differenceOf. A test wires one up with its TestCase, the facade
// and the imported Rows.js and Fixtures.js, runs data() as its _data and
// passes each entry to run(). A malformed row is an entry whose run fails
// with its grammar error, never a skip. tst_OSDSystems uses only
// differenceOf and messageOf.
QtObject {
  id: root

  // The TestCase (or anything with verify(ok, message)) run() reports to
  property var testCase: null

  // What rows call: a singleton or any object with functions. One with an
  // `api` is an engine facade (its calls take one record; a feed names its
  // fed stage)
  property var facade: null

  // The imported Fixtures.js: builders by name, or null
  property var fixtures: null

  // The imported Rows.js `rows`
  property var rows: []

  // One _data entry per row: { tag, row, error }, `error` "" for a
  // well-formed row
  function data() {
    const out = [];
    const ids = new Set();
    const tags = new Set();
    const list = root.rows ?? [];
    for (let index = 0; index < list.length; index++) {
      const row = list[index];
      const id = root._rowId(row);
      let tag = id !== "" ? id + " " + (typeof row.why === "string" ? row.why : "") : "row " + index;
      if (tags.has(tag))
        tag += " #" + index;
      tags.add(tag);
      let error = root._grammarError(row);
      if (id !== "") {
        if (ids.has(id))
          error = "repeated id";
        ids.add(id);
      }
      out.push({
        "tag": tag,
        "row": row,
        "error": error
      });
    }
    return out;
  }

  // Runs one entry of data(): one testCase.verify per compared step, and
  // returns after the first failed one
  function run(data) {
    const row = data.row;
    if (data.error !== "") {
      const id = root._rowId(row);
      root.testCase.verify(false, (id !== "" ? id : data.tag) + ": " + data.error);
      return;
    }
    const fed = root._fedOf(row.call);
    const steps = row.steps !== undefined ? row.steps : [
      {
        "expect": row.expect
      }
    ];
    const state = {};
    for (let i = 0; i < steps.length; i++) {
      const step = steps[i];
      const where = row.id + " step " + i;
      const got = root._attempt(() => {
        if (i === 0)
          root._begin(row, fed, state);
        return fed !== "" ? root._feedStep(row, fed, state, step) : root._plainStep(row, state, step);
      });
      if (got.threw) {
        root.testCase.verify(false, where + " threw: " + got.message);
        return;
      }
      if (step.expect === undefined)
        continue;
      const difference = root.differenceOf(got.value, step.expect);
      root.testCase.verify(difference === null, difference === null ? "" : root.messageOf(where, difference));
      if (difference !== null)
        return;
    }
  }

  // null when `actual` holds every part of `expected`, else the first
  // difference { path, expected, actual }, expected keys in their order. An
  // expected object holds when each of its keys holds in the actual; an
  // expected array when the actual is an array of the same length whose
  // elements hold in order; a scalar when ===. A { "$count": n } (array
  // length or key count), { "$less": x }, { "$between": [a, b] } or
  // { "$absent": true } object holds by its own rule
  function differenceOf(actual, expected) {
    return root._difference(actual, expected, "");
  }

  // The failure text of a difference: `<where>: <path>: expected <e>, got
  // <a>` (the empty path is written `output`)
  function messageOf(where, difference) {
    return where + ": " + (difference.path === "" ? "output" : difference.path) + ": expected " + root._textOf(difference.expected) + ", got " + root._textOf(difference.actual);
  }

  function _textOf(value) {
    if (value === undefined || typeof value === "number" && !isFinite(value))
      return String(value);
    try {
      return JSON.stringify(value);
    } catch (e) {
      return String(value);
    }
  }

  // The row's id when it is an object with a string id, else ""
  function _rowId(row) {
    const id = root._isObject(row) ? row.id : undefined;
    return typeof id === "string" ? id : "";
  }

  // The row's `with` then each step's, `undefined` entries kept
  function _withsOf(row) {
    return [row.with].concat((row.steps ?? []).map(step => step.with));
  }

  // The row's `expect` then each step's, `undefined` entries kept
  function _expectsOf(row) {
    return [row.expect].concat((row.steps ?? []).map(step => step.expect));
  }

  function _isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }

  function _attempt(fn) {
    try {
      return {
        "threw": false,
        "value": fn()
      };
    } catch (e) {
      return {
        "threw": true,
        "message": e !== null && e !== undefined && e.message !== undefined ? e.message : String(e)
      };
    }
  }

  // -- the compare --

  function _difference(actual, expected, path) {
    if (root._isObject(expected)) {
      const keys = Object.keys(expected);
      if (keys.some(key => key.startsWith("$"))) {
        if (root._specialError(expected) !== "" || !root._specialHolds(actual, expected))
          return {
            "path": path,
            "expected": expected,
            "actual": actual
          };
        return null;
      }
      if (actual === null || typeof actual !== "object")
        return {
          "path": path,
          "expected": expected,
          "actual": actual
        };
      for (const key of keys) {
        const difference = root._difference(actual[key], expected[key], path === "" ? key : path + "." + key);
        if (difference !== null)
          return difference;
      }
      return null;
    }
    if (Array.isArray(expected)) {
      if (!Array.isArray(actual) || actual.length !== expected.length)
        return {
          "path": path,
          "expected": expected,
          "actual": actual
        };
      for (let i = 0; i < expected.length; i++) {
        const difference = root._difference(actual[i], expected[i], path + "[" + i + "]");
        if (difference !== null)
          return difference;
      }
      return null;
    }
    if (actual === expected)
      return null;
    return {
      "path": path,
      "expected": expected,
      "actual": actual
    };
  }

  // The one check of a `$` object: "" or what is wrong with it
  function _specialError(special) {
    const keys = Object.keys(special);
    if (keys.length !== 1)
      return "a $ key can't mix with other keys";
    const key = keys[0];
    const value = special[key];
    if (key === "$count" || key === "$less")
      return typeof value === "number" ? "" : key + " takes a number";
    if (key === "$between")
      return Array.isArray(value) && value.length === 2 && typeof value[0] === "number" && typeof value[1] === "number" ? "" : "$between takes an array of two numbers";
    if (key === "$absent")
      return value === true ? "" : "$absent takes true";
    return "unknown key " + key;
  }

  // Whether `actual` meets a well-formed `$` object
  function _specialHolds(actual, special) {
    if (special.$count !== undefined) {
      if (Array.isArray(actual))
        return actual.length === special.$count;
      return actual !== null && typeof actual === "object" && Object.keys(actual).length === special.$count;
    }
    if (special.$less !== undefined)
      return typeof actual === "number" && actual < special.$less;
    if (special.$between !== undefined)
      return typeof actual === "number" && actual >= special.$between[0] && actual <= special.$between[1];
    return actual === undefined;
  }

  // -- the grammar --

  // "" when `row` is a well-formed row, else what is wrong with it
  function _grammarError(row) {
    if (!root._isObject(row))
      return "a row is an object";
    const known = ["id", "why", "call", "fixture", "input", "args", "with", "expect", "steps"];
    for (const key of Object.keys(row))
      if (known.indexOf(key) < 0)
        return "unknown key " + key;
    if (typeof row.id !== "string")
      return "id is missing";
    if (!/^[A-Z]+-(?:[A-Za-z]+-)?\d{2,}$/.test(row.id))
      return "bad id";
    if (typeof row.why !== "string" || row.why === "")
      return "why is empty";
    const facade = root.facade;
    if (typeof row.call !== "string" || !facade || typeof facade[row.call] !== "function")
      return "call is not a function of the facade";
    const api = root._apiOf();
    if (api !== null && !(row.call in api))
      return "call is not in the facade's api";
    const sources = ["fixture", "input", "args"].filter(key => row[key] !== undefined);
    if (sources.length !== 1)
      return "a row has exactly one of fixture, input, args";
    if (row.fixture !== undefined && (typeof row.fixture !== "string" || !root.fixtures || typeof root.fixtures[row.fixture] !== "function"))
      return "unknown fixture";
    if (row.input !== undefined && !root._isObject(row.input))
      return "input is not an object";
    if (row.args !== undefined) {
      if (!Array.isArray(row.args))
        return "args is not an array";
      if (row.args.length > 4)
        return "args holds at most 4 values";
      if (row.with !== undefined)
        return "args can't have with";
      if (row.steps !== undefined)
        return "args can't have steps";
      if (api !== null)
        return "an engine facade takes one input record, not args";
    }
    if ((row.expect !== undefined) === (row.steps !== undefined))
      return "a row has exactly one of expect, steps";
    if (row.steps !== undefined) {
      if (!Array.isArray(row.steps))
        return "steps is not an array";
      const stepKeys = ["now", "with", "expect"];
      for (const step of row.steps) {
        if (!root._isObject(step))
          return "a step is an object";
        for (const key of Object.keys(step))
          if (stepKeys.indexOf(key) < 0)
            return "unknown step key " + key;
        if (step.now !== undefined && typeof step.now !== "number")
          return "a step's now is a number";
      }
    }
    for (const patch of root._withsOf(row))
      if (patch !== undefined && !root._isObject(patch))
        return "with is not an object";
    const fed = root._fedOf(row.call);
    const stageError = fed !== "" ? root._feedKeyError(row, fed) : root._prevKeyError(row);
    if (stageError !== "")
      return stageError;
    return root._expectError(root._expectsOf(row).filter(expect => expect !== undefined));
  }

  // The facade's api, or null for a helper
  function _apiOf() {
    const api = root.facade ? root.facade.api : undefined;
    return api !== undefined && api !== null && typeof api === "object" ? api : null;
  }

  // The stage `call` feeds ("" when it is no feed)
  function _fedOf(call) {
    const api = root._apiOf();
    const entry = api !== null ? api[call] : undefined;
    return entry !== undefined && entry !== null && typeof entry.feeds === "string" ? entry.feeds : "";
  }

  // A steps row's `with` (the row's and each step's) never writes `prev`:
  // the runner does
  function _prevKeyError(row) {
    if (row.steps === undefined)
      return "";
    for (const patch of root._withsOf(row))
      if (root._isObject(patch) && patch.prev !== undefined)
        return "with can't write prev";
    return "";
  }

  // A feed row's keys are stage names (`input` also `prev`, keyed the
  // same), the runner writes `prev` and `event`
  function _feedKeyError(row, fed) {
    const stages = [row.call, fed];
    const keyed = (value, what, extra) => {
      if (!root._isObject(value))
        return what + " is keyed by stage";
      for (const key of Object.keys(value))
        if (stages.indexOf(key) < 0 && key !== extra)
          return what + " has " + key + ", which is no stage of the feed";
      return "";
    };
    if (row.input !== undefined) {
      let error = keyed(row.input, "input", "prev");
      if (error === "" && row.input.prev !== undefined)
        error = keyed(row.input.prev, "input.prev", "");
      if (error === "" && root._isObject(row.input[fed]) && row.input[fed].event !== undefined)
        error = "input can't write event";
      if (error !== "")
        return error;
    }
    for (const patch of root._withsOf(row)) {
      if (patch === undefined)
        continue;
      if (root._isObject(patch) && patch.prev !== undefined)
        return "with can't write prev";
      let error = keyed(patch, "with", "");
      for (const stage of stages)
        if (error === "" && root._isObject(patch[stage]) && patch[stage].prev !== undefined)
          error = "with can't write prev";
      if (error === "" && root._isObject(patch[fed]) && patch[fed].event !== undefined)
        error = "with can't write event";
      if (error !== "")
        return error;
    }
    for (const expect of root._expectsOf(row)) {
      const error = expect === undefined ? "" : keyed(expect, "expect", "");
      if (error !== "")
        return error;
    }
    return "";
  }

  // "" when each expect holds only well-formed `$` objects and together they
  // hold a literal to check (a string, number, boolean or null; the values
  // of $count, $less and $between count, $absent's does not)
  function _expectError(expects) {
    const found = {
      "error": "",
      "literal": false
    };
    for (const expect of expects)
      root._scanExpect(expect, found);
    if (found.error !== "")
      return found.error;
    return found.literal ? "" : "no expect holds a literal value";
  }

  function _scanExpect(value, found) {
    if (Array.isArray(value)) {
      for (const item of value)
        root._scanExpect(item, found);
      return;
    }
    if (root._isObject(value)) {
      const keys = Object.keys(value);
      if (keys.some(key => key.startsWith("$"))) {
        const error = root._specialError(value);
        if (error !== "" && found.error === "")
          found.error = "bad $ object: " + error;
        if (error === "" && keys[0] !== "$absent")
          found.literal = true;
        return;
      }
      for (const key of keys)
        root._scanExpect(value[key], found);
      return;
    }
    if (value !== undefined)
      found.literal = true;
  }

  // -- building and calling --

  // `base` with `patch` merged over it: objects by key, recursively; arrays
  // and scalars replace. Builds new objects, never touches `base`, and keeps
  // what `base` holds that isn't JSON (a function) by reference
  function _withApplied(base, patch) {
    if (!root._isObject(base) || !root._isObject(patch))
      return Utils.clone(patch);
    const out = Object.assign({}, base);
    for (const key of Object.keys(patch))
      out[key] = root._isObject(base[key]) && root._isObject(patch[key]) ? root._withApplied(base[key], patch[key]) : Utils.clone(patch[key]);
    return out;
  }

  // A step's carried input: the previous one with the step's `with` merged
  // in and its `now` written
  function _stepInput(carried, patch, now) {
    const out = patch !== undefined ? root._withApplied(carried, patch) : Object.assign({}, carried);
    if (now !== undefined)
      out.now = now;
    return out;
  }

  // Builds the row's base input into `state` (an args row has none)
  function _begin(row, fed, state) {
    if (row.args !== undefined)
      return;
    let base = row.fixture !== undefined ? root.fixtures[row.fixture]() : Utils.clone(row.input);
    if (row.with !== undefined)
      base = root._withApplied(base, row.with);
    state.base = base;
    if (fed !== "") {
      const prevs = root._isObject(base.prev) ? base.prev : {};
      state.carried = {};
      state.prev = {};
      for (const stage of [row.call, fed]) {
        state.carried[stage] = Object.assign({}, base[stage] ?? {});
        state.prev[stage] = prevs[stage] !== undefined ? prevs[stage] : null;
      }
    } else if (row.steps !== undefined) {
      state.carried = Object.assign({}, base);
      delete state.carried.prev;
      state.prev = base.prev !== undefined ? base.prev : null;
    }
  }

  // One step of a row that isn't a feed: the answer of the call
  function _plainStep(row, state, step) {
    const facade = root.facade;
    if (row.args !== undefined)
      return facade[row.call].apply(facade, Utils.clone(row.args));
    if (row.steps === undefined)
      return facade[row.call](state.base);
    state.carried = root._stepInput(state.carried, step.with, step.now);
    const input = Object.assign({}, state.carried);
    input.prev = state.prev;
    const output = facade[row.call](input);
    state.prev = output;
    return output;
  }

  // One step of a feed row: `call` once, then the fed stage once per event
  // of its answer; the answer is { <call>: …, <fed>: … } (the fed stage's
  // last output, or its unchanged `prev` when no event came)
  function _feedStep(row, fed, state, step) {
    const facade = root.facade;
    for (const stage of [row.call, fed])
      state.carried[stage] = root._stepInput(state.carried[stage], root._isObject(step.with) ? step.with[stage] : undefined, step.now);
    const input = Object.assign({}, state.carried[row.call]);
    input.prev = state.prev[row.call];
    const output = facade[row.call](input);
    state.prev[row.call] = output;
    const events = output !== null && output !== undefined && Array.isArray(output.events) ? output.events : [];
    for (const event of events) {
      const eventInput = Object.assign({}, state.carried[fed]);
      eventInput.prev = state.prev[fed];
      eventInput.event = event;
      state.prev[fed] = facade[fed](eventInput);
    }
    const got = {};
    got[row.call] = output;
    got[fed] = state.prev[fed];
    return got;
  }
}
