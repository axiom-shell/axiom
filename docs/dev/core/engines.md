# Engines

> **Files:** `tests/EngineRows.qml`, `tests/tst_EngineRows.qml`, `tests/enginerows/`
> **Config:** none
> **Related:** [Testing](../testing.md), [Shared UI pieces](shared-ui-pieces.md) (Pure helpers)

What an engine is, the shape every engine facade takes, the rules that keep an engine readable, and the row format and runner its contract tests are written in. Read it before adding a decision module to `qml/components/methods/`, before writing rule rows for a helper, and before changing `tests/EngineRows.qml`.

## What an engine is
An **engine** is a pure QML decision module in `qml/components/methods/<engine>/`, entered through one facade `<Name>Engine`. The folder is the facade's stem minus `Engine`, lower-cased: `WorkspaceEngine` lives in `workspace/`.

A domain is an engine when it:
- takes inputs from more than one owner;
- answers more than one host;
- has at least two of: a model step over a set, a per-request decision at rest, a reducer over time, a per-frame drawn form (the four stages in [Stages](#stages)).

**Not an engine:** a one-decision rule helper with one consumer (`NotificationLevel`, `WindowOrder`, `Search`, `PomodoroCycle`); a parser of an outside format (`HyprState`, `NiriState`); a domain's pure helpers with no stage (`LayerArrange`, `LayerStack`); a generic utility (`Utils`, `ScreenEdge`, `Tone`); a surface (a prompt, a power menu: hosts of engines). These stay at the `methods/` root or in their domain folder. An engine is also not a service with logic in it, a host calling helpers in sequence, or a folder of helpers sharing a prefix.

`OSDEngine` (`qml/components/methods/OSDEngine.qml`) carries the name but has no `api`; the runner treats it as a helper.

## Principles
In priority order; each rules out a shape that made decisions hard to follow.
- **Readable resolution.** Every decided output carries the id of the rule that decided it; every rule is a table row with an `id` and a `why`, or a function named for the rule; every stage takes one object and destructures it on its first line; every facade declares its `api` in code. A reader goes from an output to its rule id, to the row or function (one grep), to the input fields it reads.
- **One quantity, one derivation.** A value is computed in one place and read from there.
- **Decide at rest; drawn values are outputs only; data flows one way at each rate.** No output feeds back into the stage that made it.
- **Total rule tables, no fallthrough.** Every case has a row; none is decided by elimination.
- **Whole answer per call; a separate step applies it.** A decision returns everything the caller needs; applying it is another step.
- **One space, one grid, one snap.** Geometry is decided in one coordinate space and snapped once.
- **Time is data; one clock per moving item.** `now`, `progress` and gliding values are numbers in; `Date.now()`, Timers and animations live only in owners and hosts; timed outputs say `next`.
- **Order is data.** "Newer wins" is a field, never the order of calls.
- **Hosts apply; tests call what owners and adapters call.** A host holds no decision.
- **Declarations over hooks.** A fact a plug-in states is a field, not a function the engine calls.
- **Identity-stable results, bounded per-frame work.** Owners keep results identity-stable; per-frame stages allocate little.

## Roles
| Role | What it is | Lives |
|---|---|---|
| **Facade** | one `pragma Singleton` `<Domain>Engine` of at most 200 lines; members in this order: `api`, `tuning`, the stage functions in stage order (`model`, `solve`, `reduce`, `drawn`), then extras; each stage destructures, calls named internals, returns | `methods/<engine>/<Name>Engine.qml` |
| **Internal file** | stage bodies and rule tables | `methods/<engine>/` |
| **Kit** | pure per-item formulas the engine's own drawing items call per delegate | `methods/<engine>/` |
| **Feeder** | one owner member that returns the shell values (`env`) or a reducer's `entries`, with a `// reads:` line per config read; it gathers async inputs before the owner runs the engine | in the owner |
| **Owner** | runs `model` and `reduce` (and `solve` for scene inputs it gathers); keeps lists with `KeptList` and objects with `Utils.keepEqual`; holds a reducer's memory in one `_prev` property; applies `effects` one turn after the run; logs `problems` | an existing `*Manager`, a reader, an editor service, or a per-instance base |
| **Adapter** | the one item per host kind that builds the `request`, calls `solve` and `drawn` in one binding each and maps the result to typed scalar properties; it holds `solve`'s `prev` | the host's folder |
| **Host** | windows, items, focus, IPC targets and animations (`SlideAnimation`, `Glide`); reads adapter properties and owner outputs, applies them, and never calls a facade | `hosts/`, `surfaces/` |
| **Plug-in** | a folder of declarations (and a watcher) found by schema `kinds`; it calls only what its folder and the facade's declared extras offer | `surfaces/<area>/systems/<Type>/`, `bar/widgets/<Type>/`, `content/<Type>/` |

## Data words
- **Stage inputs** carry only these keys: `config`, `env`, `state`, `prev`, `event`, `entries`, `tuning`, `request`, `now`, `motion`, `result`, `model`. Domain values nest under `env` (shell values at config or theme rate, including `supports` and `borderWidth`) or `state` (live values, including other engines' outputs). No flat domain key on a stage input.
- **Strings that name things** end in `Name`: a screen, edge or output that crosses as a string is `screenName`, `edgeName`, `outputName`. The host-side `ScreenEdge` int never appears in engine data. **Platform enums** (layer, keyboard-focus and exclusion-mode values) never enter an engine input or output; the window maps the engine's string when it applies.
- **`entries`** is the set a reducer runs over: an array of `{id, …}`.
- **`event`** is `{kind, …}`; its time is the `now` argument, never a field. The run at a reducer's `next` is `event: {kind: "due"}`.
- **`now`** and **`next`** are milliseconds on one clock (the owner's `Date.now()`). `next` is the absolute time the output next changes with no new input, and **`0` means never** (`OSDParts.partsDue` is the precedent). A reducer returns `0` or a value greater than `now`.
- **`motion`** is `{progress, gliding, parent}`: `progress` is 0–1 of the host's one slide (`SlideAnimation`); `gliding` maps an item key to the current values of the host's `Glide` animations whose targets are rest outputs (absent key: at rest); `parent` is the parent surface's `motion`, or `null`.
- **`effects`** is `[{kind, …}]`: one-shot actions, the only deferred actions an owner applies.
- **`problems`** is `[{code, key, detail}]`: never thrown, never logged by the engine.
- **`tuning`** is the facade's decided product constants (a readonly `tuning` property). A stage destructures it with the facade's as default (`const {request, model, prev, tuning = root.tuning} = input;`), so owners pass nothing and tests pass a replacement. Units are milliseconds, logical pixels and unsuffixed fractions; any other unit is suffixed in the name.
- **Output nouns** are per engine (`scene`, `result`, `outcomes`, `changes`, `board`, …). A forwarded output keeps its name on every hop.

## Stages
Four facade verbs plus two impure steps. This table is the contract every engine conforms to.

| Verb | Allowed input keys (required in **bold**) | Output (all keys present) | Rate | Caller | Never takes |
|---|---|---|---|---|---|
| **`model`** | **one of `config`/`state`**, `env`, `tuning` | `{<model noun>, problems}` | the whole set per owner key (a screen, an editor draft) when an input changes; at most once per turn (`KeptList` with `oncePerTurn`) | owners | `prev`, `now`, `event`, `request`, `motion` |
| **`solve`** | **`request`**, `model`, `prev`, `env`, `tuning` | `result` with `rule`/`rules` on decided objects, `problems` | per request change, at rest; never per animation frame | adapters (one binding); owners for inputs they gather and for their own surfaces | `now`, `motion`, `event`, `entries`, `state` |
| **`reduce`** | **`prev`**, **`now`**, **`entries` and/or `event`** (`api.reduce.in` names which; `event: null` on a run caused by anything but an event), `state`, `env`, `config`, `tuning` | `{<noun>, effects, next, problems}`, JSON-plain | on each event, each entries change and each change of its `state`, `env` or `config` (synchronously, in the call or notification that brought it), and again at `next`; never per frame | owners | `motion`, `request`, `result` |
| **`drawn`** | **`result`**, **`motion`**, `state` (upstream engine outputs), `tuning` | drawn geometry, snapped to whole pixels where it crosses to another owner | per frame while `motion` or its `state` changes | adapters (one binding) | `prev`, `now`, `event`, `effects`, `next`, `env` |
| `gather` (impure) | readers, services | `{config, env, state}` for the owner's run | on change; async inputs collected first | the owner's feeder | |
| `apply` (impure) | outputs | windows, items, claims, timers, compositor calls, animations | on an output change | hosts, owners | |

**Extras.** A facade may declare extras in `api` (`"extra": true`). An extra with a stage's signature is named `<stage><Noun>` and obeys that stage's row. Any other extra is a pure function of one object, named for its answer. `api` is the one declaration of extras. An extra returns an object carrying `rule`, or `null` for none.

**Verb choice** (decides any new stage): whole set, no memory, no time is `model`; one request at rest, memory only for sticky rules is `solve`; memory and/or time over events or a competing set is `reduce`; per frame is `drawn`.

**The config boundary.**
- Config reaches an engine already normalised by the Go daemon (prune, defaults, validate). The first stage is `model`, never "normalise" or "build".
- `model` takes reader outputs, never `ConfigManager.config`, `live` or the schema; it fills no default, prunes nothing and uses no `??` on a config value.
- Defaults for data outside config come from `ConfigManager.withDefaults(value, definition)` in the feeder.
- `x-inherit`, unit conversion and id lookups stay in the reader. Annotation facts come from `SchemaLayout` through the reader; an engine never walks the schema.
- Editors run the same stages on the draft through `live`, so the owner's keep-equal step is required.

**Merged or split.**
- Per-entry enrichment and the cross-entry set step are one `model`.
- The request is a shape, not a stage. Routing is part of `reduce`.
- Schedule is not a stage: timed outputs carry `next`, and the owner re-runs at it.
- Snap is the last step of `solve` and `drawn`, inside the producing engine.

## The facade
One `pragma Singleton` with one destructure form everywhere: `function <verb>(input) { const {…} = input; … }`. Parameter destructuring is not used, so `api.<verb>.in` is read against one line shape. Members in order: `api` first, then `tuning`, the stages, the extras.

```qml
// Where an example thing sits, and how its ends meet what is there
pragma Singleton
import QtQuick
import qs.components.methods

QtObject {
  id: root

  // The API: each stage's input keys and, per output path, the function or table that produces it
  readonly property var api: ({
      "solve": {"in": ["request", "model", "prev", "env", "tuning"], "out": {"room": "ExampleRules.roomOf", "ends.*": "ExampleRules.endRows", "box": "ExampleRules.boxOf"}},
      "pointAt": {"in": ["spot"], "out": {"": "ExampleRules.pointAt"}, "extra": true}
    })
  // floorBorders: the smallest fillet, in border widths
  readonly property var tuning: ({"floorBorders": 2})

  function solve(input) {
    const {request, model, prev, env, tuning = root.tuning} = input;
    // Room first, from the anchor alone
    const room = ExampleRules.roomOf({model, anchor: request.anchor, tuning});
    const ends = ExampleRules.endsOf({model, request, room, env, tuning});
    return {"room": room, "ends": ends, "box": ExampleRules.boxOf({room, request}), "problems": []};
  }
}
```

A producer's name never reuses a member name another file uses for a different quantity. No comment, `why` or row in the repo cites a plan, step or ticket id: a product value's comment says what the value is.

## Timing and flow
Each named rule below is a rule id: a function or row named so, pinned by a contract row.
- **Rates.** Rates are the table's. `solve` results don't depend on each other, except a child on its parent (`request.parent`) and the members of one set-solved request.
- **Drawn-rate transport is by binding.** A drawn output another adapter or item reads is read through a property binding: never `Qt.callLater`, never an `on…Changed` handler that pushes it on. Membership (which publisher feeds which consumer) changes at rest; values travel by binding.
- **Three deferrals, each marked.** `Qt.callLater` is used only to apply reducer `effects` and window, claim or compositor changes (and log `problems`), to coalesce a burst of an owner's changes (`KeptList` with `oncePerTurn`), and for a first-frame animation gate (a `Glide` enabled one turn after creation). Each carries `// allowed: apply <what>` or `// allowed: settle <what>`.
- **No output is an input of the same stage.** `prev` is what the owner or adapter stored after the last run. A host animation's current value (`motion.gliding`) is an input: its target is a rest output, its value is the host's `Glide`, never an engine's `drawn` output.
- **Rest in, drawn out.** `state` carries rest values; a zone never follows a claim outcome.
- **Owner-solves for scene inputs.** An input the model needs that only items can measure reaches the owner through one registry as a rest value, and the owner runs every stage that consumes it in one pass.
- **One clock per moving item.** A surface's slide is its host's `SlideAnimation` (`motion.progress`); every other moving item is its host's own `Glide` on a rest target, read as `motion.gliding[<key>]`. A retarget mid-glide is the `Glide`'s. Copies and publishers read the same numbers; none runs a second animation.
- **Known vs estimated is an input flag** (`origin.known`), never mixed silently.
- **No reader carries a service's result.** A reader's shell fact that a service decides is a declared `// set by: <Service>` property that service alone writes; an engine feeder reads the owning service, never the reader's copy.
- **Reducers answer in the call; one assignment per run.** An owner runs `reduce` synchronously inside the call that adds an entry or delivers an event (the whole set each time). A run reads `prev` from the owner's `_prev` at its start and stores its whole output into `_prev` in one assignment, as its last write; every public output is a readonly binding on `_prev`; effects are queued at that assignment in run order. A call arriving while the notifications of that assignment run reads `_prev` from its own run and assigns in turn.
- **Loops at rest are broken only by named intake rules.** Where an engine's output reaches an upstream stage's input through a host or owner, a named rule reads only the field it names, and its contract row shows a fixed point in one step. A back edge with no such rule is a design error.
- **An owner runs every stage that consumes a value only items can measure**, so the measure and its consumers change in one pass.

## Reactivity and budgets
- No memo in `methods/`; memo lives in owners, keyed by identity.
- Owners keep lists with `KeptList` and objects with `Utils.deepEqual` or `Utils.keepEqual` before assignment.
- Adapters expose typed scalars; a pair of related facts comes from one result object ([QML pitfalls](qml-pitfalls.md)). Arrays are consumed by count.
- Budgets (mean over a sweep, failing at five times): `drawn` at most 0.1 ms per run; `solve` at most 1 ms; `model` at most 2 ms per screen; `reduce` at most 1 ms for 32 entries.

## Readability
- **Rule granularity.** `rule` sits on the smallest output object one rule decides. An object whose fields come from different rules carries `rules: {field: id}`. A boolean or number decided per id is `{value, rule}`.
- **The `api` trace map.** `api.<stage>.out` maps every output path to the function or table that produces it (`"ends.*.line": "ExampleRules.lineOf"`). Every derived quantity is produced by one function named for it, so "why is this value 52?" is one read of the facade: the producer, then its inputs. `api.<stage>.in` equals the stage's destructure line, and the `api` keys equal the facade's functions.
- **Three table kinds**, each one grammar. **Cell**: rows `{id, when: {axis: value or [values]}, then, why}`, the axes and their value sets declared beside the rows, no wildcards, exactly one row per cell. **Ordered**: rows `{id, when: "<predicate function>", then, why}`, first match wins, the array order is the order, every row reachable, the last row a catch-all with its own id. **Rank**: rows `{name, rank, why}`, lowest first, read by `rankOf(name)`. `then` is a literal outcome or the name of a function in the same file; the output's `rule` is the row's `id`. Tables, `axes` and `api` are literals (strings, numbers, booleans, arrays, objects), so a script can read them.
- **Rule ids** are lowerCamel sentences, never renamed (add a new id and remove the old with its rows). `why` sits only on rows, `rule` only on outputs. A function-named rule returns `rule` equal to its own name.
- **Object inputs.** Stages and extras take one object, destructured on the first line.
- **File shape.** Facade at most 200 lines, other engine files at most 500, a function at most 60, at most one ternary per expression (`?.` and `??` excluded).
- **Named numbers.** A number in a decision is a `tuning` field or a table cell.
- **Geometry out, strings last.** Outputs are rects, arcs and spans; a path string an item needs is built from that geometry in the same stage and returned beside it.

## Code in inputs
- Plug-in definitions pass as `state.systems`; the engine reads declarations by field and calls a hook through one internal call site per hook, and a hook needs a reason line.
- Capability functions in `env` are allowed when deterministic and memoised by their owner; tests pass a stand-in.
- Never: closures in `state`, `request` or `prev`; platform enums; Items in any engine input (a registry of publishers holds Items; only the values read through it reach `drawn`).

## Errors and logging
Engines never throw or log. An inconsistent input gives a safe result plus `problems`; the owner logs `console.warn("[<Facade>] <code> <key>: <detail>")` once per `(code, key)` until it clears. Each `code` has a contract row.

## Tests
| Kind | Files | Mechanism |
|---|---|---|
| **Contract rows** | `tests/<engine>/Rows.js` for an engine, `tests/flat/<Helper>.js` for a root helper, each run by a `tst_<Name>.qml` through `tests/EngineRows.qml` | each row calls one facade function (or a declared feed) and subset-compares the output |
| **Timeline** | rows with `steps` in the same rows file | each step calls the reducer with the previous output as `prev` |
| **Unit `_data`** | `tests/tst_<Internal>.qml` | QtTest tables for big internal tables |
| **Fixtures** | `tests/<engine>/Fixtures.js` | named builders. A file whose builders only return plain data is `.pragma library` (`tests/osd/*.js`); one whose builders use the importing test's facades and helpers is not (`tests/barstyle/Bars.js`) |

- A helper's existing `_data` tables stay and keep passing. A kept table that pins a rule a rows file names prefixes each tag with the row id (`"MOD-04 strip below 7 em"`); it becomes rows only when its rule changes. New rule rows for a helper go in `tests/flat/<Helper>.js`, run by an `EngineRows` inside the same `tst_<Helper>.qml`.
- A helper that imports `qs.config`, `qs.services.*` or Quickshell gets no rows file: its decision moves into a pure helper first, or stays pinned by its existing test.
- Rows land in the same change as the code they pin, all green; there are no pending or expected-failure rows.
- A row id's prefix is an upper-case abbreviation of the engine or helper the rows test.
- Checks that aren't a facade call (pixel checks, harness items) are not rows.

## The row format
A rows file is a `.pragma library` with a purpose comment and `var rows = <a JSON array>;` in strict JSON: keys quoted, no comments, no trailing commas inside the array, so Python reads it with `json.loads`.

```js
// tests/example/Rows.js
.pragma library
// The example engine's contract rows
var rows = [
  { "id": "DEMO-01", "why": "a notification arriving under an engaged popout waits until it closes",
    "call": "reduce", "fixture": "menuOverToastArea",
    "steps": [
      {"now": 0,   "with": {"entries": [{"id": "menu:a", "surface": "barPopout", "engaged": true}, {"id": "toast:1", "surface": "toast"}]},
                   "expect": {"outcomes": {"toast:1": {"state": "yielded", "rule": "toastWaitsForEngaged"}}, "next": 0}},
      {"now": 900, "with": {"entries": [{"id": "toast:1", "surface": "toast"}]},
                   "expect": {"outcomes": {"toast:1": {"state": "open", "rule": "rankOrder"}}}} ] },
  { "id": "DEMO-02", "why": "a wall end reaches where windows start",
    "call": "solve", "fixture": "userBar4", "with": {"request": {"surface": "edgePopout", "edgeName": "left"}},
    "expect": {"ends": {"start": {"line": 52, "rule": "wallFillet"}}} },
  { "id": "DEMO-03", "why": "a list of three items has its first moved to the end",
    "call": "moveItem", "args": [["a", "b", "c"], 0, 2], "expect": ["b", "c", "a"] }
];
```

**Keys.**
- A row has `id` (`<PREFIX>-<nn>`, two or more digits, optionally `<PREFIX>-<Type>-<nn>`; stable forever, unique in `rows`, a removed row's id is never reused), `why` (one non-empty sentence in plain words; a product answer's row states the answer itself), and `call`.
- Then exactly one of `fixture` (a function name in `fixtures`), `input` (an object) or `args` (an array of 0–4 values); an optional `with` (not with `args`); then exactly one of `expect` or `steps` (`steps` not with `args`). Both, or neither, is a grammar error.
- A step has `now` (a number), `with` and `expect`, all optional. Any other key in a row or a step is a grammar error.
- `call` is a function of the facade; when the facade has an `api`, it is also a key of `api`.

**Input.** `fixture` builds a fresh object each call (not cloned); `input` is a `Utils.clone` of what is written. `with` merges over it: objects merge by key recursively, arrays and scalars replace. The merge builds new objects and never mutates the fixture's output, the row or an earlier step's input; a non-JSON value (a function) is kept by reference. The merged object is the row's **base input**.

**Single call** (`expect`, `call` not a feed): `facade[call](base input)` as built, or the facade's function called with the `args` values spread for an `args` row, then the compare. A `prev` key in the base input stays: it is read and removed only for `steps` rows. The result is reported as step 0.

**`args` rows** are for a positional helper such as `CustomWidgetData.moveItem(list, from, to)`, `SchemaLayout.keyPath(parent, key)` or `OSDParts.partsDue(deadlines, now, grace)`. They are refused against a facade with an `api` (its stages and extras take one record), and take at most 4 values: a function with more positional parameters gets no `args` rows. A one-object helper is called with `input`, never `args: [{…}]`; that is not checked. The runner copies `args` before the call, so the row's array is left unchanged.

**Steps.** The runner keeps a **carried input** per row. It starts as the base input with its `prev` key read and removed. Step k's carried input is step k−1's carried input merged with step k's `with` (step 0: the base input merged with step 0's `with`); then, when the step has `now`, `now` is written into it, and a step without `now` keeps the carried one. The facade is called with a shallow copy of the carried input plus `prev`: for step 0 the base input's `prev` key (a fixture's or a written `input`'s), else `null`; for step k the whole output of step k−1. `prev` is written on every step, `null` included, and is never part of the carried input, so no output is merged into a following step's input. A step without `expect` still runs and compares nothing; a throw in it is still reported.

**Feed rows.** A row whose `call` has `facade.api[call].feeds` naming a stage is a feed row, with or without `steps`; one with `expect` and no `steps` runs as one step whose `now` and `with` are absent.
- The base input is keyed by stage (`{<call>: {…}, <fed>: {…}, prev?: {<call>: …, <fed>: …}}`), a row `with` keyed the same way. Each stage keeps its own carried input (starting from `base[stage]`, or `{}`) and its own `prev` (first `base.prev[stage]`, else `null`). A step's `with` and `expect` are keyed by stage name.
- Per step, `now` is written into both carried inputs; `call` runs once with its carried input plus `prev`; then the fed stage runs once per element of that output's `events` (none when `events` is missing or empty), in order, each with a shallow copy of its carried input plus `prev` (its last output, or its `prev` before the first event) and `event` (that element; never carried).
- The fed stage's `expect` compares its last output in that step, or its unchanged `prev` when no event came. A difference's path is prefixed with the stage name (`reduce.outcomes.x`).
- Stage keys: in a feed row, a written `input`'s top-level keys are the two stage names plus optional `prev`, and `input.prev`'s keys are stage names; a row `with`, each step's `with` and each `expect` have only stage names at the top. `prev` is refused at `with.prev` and `with.<stage>.prev`, and `event` at `with.<fed>.event` and `input.<fed>.event`. A fixture's output is not checked (it is built when the row runs).

**Compare** (`differenceOf(actual, expected)` returns `null`, or the first `{path, expected, actual}`, in the expected keys' order):
- An expected object holds when every key holds in the actual (an actual that isn't a non-null object is a difference at that path). An expected array holds when the actual is an array of the same length whose elements hold in order. A scalar (`null` included) holds when `===`: no number tolerance, no `NaN` equality, no string-to-object `==`.
- Special objects: `{"$count": n}` (array length or object key count), `{"$less": x}` (`actual < x`), `{"$between": [a, b]}` (`a ≤ actual ≤ b`), `{"$absent": true}` (as a key's value: the key is missing or `undefined`; at the top: the actual is `undefined`). A `$` key never mixes with other keys, only these four exist, and each takes its value shape (`$count` and `$less` a number, `$between` an array of two numbers, `$absent` `true`); anything else is a grammar error. Called directly (`tst_OSDSystems` does), `differenceOf` reports a bad `$` object as a difference at its path, with `expected` the object.
- A path is keys joined with `.` and array indices as `[i]` (`ends.start[2].line`); the empty path is written `output` in a message.
- `expect` names at least one literal leaf (a string, number, boolean or `null`; the values of `$count`, `$less` and `$between` count; `$absent` does not): a bare rule key with no value to pin is not a row. `expect: null` is a literal, for a call answering `null`.

**Not a row.** Each of these fails in `data()`: the entry's `error` is set and `run` reports it with one failed `verify`, never a skip.
- A row that isn't an object; `input` not an object; `args` not an array; `steps` not an array, or a step not an object; a `with` (the row's or a step's) that isn't an object; in a feed row, a `with` or `expect` that isn't an object keyed by stage.
- Both `expect` and `steps`, or neither; a step `now` that isn't a number; no `expect` with a literal leaf.
- A repeated id: every entry after the first with that id get the error `repeated id` in place of any other error they have, also when the first is itself malformed; the first runs.
- `call` missing, not a function, or not in `api`; not exactly one of `fixture`, `input`, `args`; `args` with `with` or `steps`; `args` against a facade with `api`; more than 4 `args`; an unknown key; a bad `$` object; a `fixture` name not in `fixtures`; a bad `id` or an empty `why`.
- In a `steps` row, a row or step `with` with a top-level `prev`; in a feed row, a stage-key error above. The runner writes `prev` and `event` itself, so a `with` that set them would be silently ignored.

**Messages.** A failed step reports `<id> step <i>: <path>: expected <e>, got <a>`; a throw, `<id> step <i> threw: <message>`; a grammar error, `<id>: <error>` (`row <index>: <error>` when `id` is missing or not a string; `<index>` is the row's 0-based position in `rows`). The `try` covers only building a step's input and the facade calls of that step; `differenceOf` and `verify` run outside it, so QtTest's own failure throw is never reported as `threw`. `run` returns after the first failed `verify`. There is no expected-failure path.

## The runner
QML has no singleton lookup by string, so each test hands the runner its facade. `tests/EngineRows.qml` is a plain `QtObject` beside `tests/Shared.qml`; it holds no domain code, and one runner serves engine facades and helpers alike.

```qml
// tests/tst_ExampleEngine.qml
import QtQuick
import QtTest
import qs.components.methods.example
import "example/Rows.js" as Rows
import "example/Fixtures.js" as Fixtures

// The example engine's contract rows (tests/example/Rows.js)
TestCase {
  id: root
  name: "ExampleEngine"

  EngineRows {
    id: rows
    testCase: root
    facade: ExampleEngine
    fixtures: Fixtures
    rows: Rows.rows
  }

  function test_rows_data() {
    return rows.data();
  }
  function test_rows(data) {
    rows.run(data);
  }
}
```

- `data()` returns one `_data` entry per row, `{tag, row, error}`: `tag` is `"<id> <why>"` (`row <index>` for a row without a string `id`; a repeated tag gets ` #<index>` appended), `error` is `""` for a well-formed row.
- `run(data)` takes the entry, builds the input (a fixture by name and its `with`, or `args`), calls `facade[call]` per step, and makes one `verify(ok, message)` per compared step through `testCase`.
- `differenceOf(actual, expected)` is the subset compare; `messageOf(where, difference)` is the one failure text.
- A row calls exactly what one owner or adapter calls. A test that sequences calls with logic between them is a missing facade function. The one allowed sequence is a **declared feed**: an extra whose `api` entry says `"feeds": "<stage>"` returns `events`, and the owner hands each event unchanged to that stage. A feed is read from `api`; the runner does the same, as the feed rows above describe.

OSD timelines (`tests/osd/`) are their own format, run by `tst_OSDSystems`, which uses only `differenceOf` and `messageOf`.
