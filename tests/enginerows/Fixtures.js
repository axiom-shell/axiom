.pragma library
// The fixtures of tst_EngineRows' rows: builders, each returning a fresh
// object per call (a fixture's output is handed to the runner as built).

// An input that carries a `prev` of its own
function withPrev() {
  return {"value": 5, "prev": {"answer": 99}};
}

// A feed row's input, keyed by stage, with a `prev` for the fed stage
function feedSeeded() {
  return {"watch": {"events": []}, "prev": {"reduce": {"n": 7}}};
}

// An input holding a function (the merge keeps it by reference)
function withFunction() {
  return {"value": 1, "tell": function () { return "kept"; }};
}
