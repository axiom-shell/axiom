# Engines

> **Files:** `tests/EngineRows.qml`, `tests/tst_EngineRows.qml`, `tests/enginerows/`, `scripts/engines.json`, `scripts/manifests.py`, `scripts/check_engines.py`, `scripts/engines-baseline.json`, `scripts/engines-exceptions.json`, `.claude/skills/engine-change/SKILL.md`, `docs/recipes/engine-change.md`, `docs/recipes/new-engine.md`
> **Config:** none
> **Related:** [Testing](../testing.md), [Shared UI pieces](shared-ui-pieces.md) (Pure helpers)

What an engine is, the shape every engine facade takes, the rules that keep an engine readable, and the row format and runner its contract tests are written in. Read it before adding a decision module to `qml/components/methods/`, before writing rule rows for a helper, and before changing `tests/EngineRows.qml`.

No module under `qml/components/methods/` is an engine today. The sections from What an engine is through Errors and logging are the rules a new engine follows; `scripts/check_engines.py` checks the rules listed under Checks, and review holds an engine against the rest of this page. The row format and the runner are code: `tests/EngineRows.qml` fails a row that breaks the format (see Not a row).

## What an engine is
An **engine** is a pure QML decision module in `qml/components/methods/<engine>/`, entered through one facade `<Name>Engine`. The folder is the facade's stem minus `Engine`, lower-cased: `ExampleEngine` lives in `example/`.

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
| **Kit** | pure per-item formulas the engine's own drawing items call per delegate; the manifest's `kits` lists them | `methods/<engine>/` |
| **Feeder** | one owner member that returns the shell values (`env`) or a reducer's `entries`, with a `// reads:` line per config read; it gathers async inputs before the owner runs the engine; the manifest's `feeder` names it | in the owner |
| **Owner** | runs `model` and `reduce` (and `solve` for inputs it gathers and for its own surfaces); keeps lists with `KeptList` and objects with `Utils.keepEqual`; holds a reducer's memory in one `_prev` property; applies `effects` one turn after the run; logs `problems` | an existing `*Manager`, a reader, an editor service, or a per-instance base |
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
Four facade verbs plus two impure steps. Every engine's stages follow this table.

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
- **Rates.** Rates are the table's. `solve` results don't depend on each other, except a child on its parent (`request.parent`) and the members of one set-solved request.
- **Drawn-rate transport is by binding.** A drawn output another adapter or item reads is read through a property binding: never `Qt.callLater`, never an `on…Changed` handler that pushes it on. Membership (which publisher feeds which consumer) changes at rest; values travel by binding.
- **Three deferrals, each marked.** Around an engine (its owner and adapters), `Qt.callLater` is used only to apply reducer `effects` and window, claim or compositor changes (and log `problems`), to coalesce a burst of an owner's changes (`KeptList` with `oncePerTurn`), and for a first-frame animation gate (a `Glide` enabled one turn after creation). In an adapter, each carries `// allowed: apply <what>` or `// allowed: settle <what>`.
- **No output is an input of the same stage.** `prev` is what the owner or adapter stored after the last run. A host animation's current value (`motion.gliding`) is an input: its target is a rest output, its value is the host's `Glide`, never an engine's `drawn` output.
- **Rest in, drawn out.** `state` carries rest values; a zone never follows a claim outcome.
- **Owner-solves for scene inputs.** An input the model needs that only items can measure reaches the owner through one registry as a rest value, and the owner runs every stage that consumes it in one pass.
- **One clock per moving item.** A surface's slide is its host's `SlideAnimation` (`motion.progress`); every other moving item is its host's own `Glide` on a rest target, read as `motion.gliding[<key>]`. A retarget mid-glide is the `Glide`'s. Copies and publishers read the same numbers; none runs a second animation.
- **Known vs estimated is an input flag** (`origin.known`), never mixed silently.
- **No reader carries a service's result.** A reader's shell fact that a service decides is a declared `// set by: <Service>` property that service alone writes; an engine feeder reads the owning service, never the reader's copy.
- **Reducers answer in the call; one assignment per run.** An owner runs `reduce` synchronously inside the call that adds an entry or delivers an event (the whole set each time). A run reads `prev` from the owner's `_prev` at its start and stores its whole output into `_prev` in one assignment, as its last write; every public output is a readonly binding on `_prev`; effects are queued at that assignment in run order. A call arriving while the notifications of that assignment run reads `_prev` from its own run and assigns in turn.
- **Loops at rest are broken only by named intake rules.** Where an engine's output reaches an upstream stage's input through a host or owner, a named rule reads only the field it names, and its contract row shows a fixed point in one step. A back edge with no such rule is a design error.

## Reactivity and budgets
- No memo in `methods/`; memo lives in owners, keyed by identity.
- Owners keep lists with `KeptList` and objects with `Utils.deepEqual` or `Utils.keepEqual` before assignment.
- Adapters expose typed scalars; a pair of related facts comes from one result object ([QML pitfalls](qml-pitfalls.md)). Arrays are consumed by count.
- Budgets (a mean per run): `drawn` at most 0.1 ms per run; `solve` at most 1 ms; `model` at most 2 ms per screen; `reduce` at most 1 ms for 32 entries.

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

- A helper's existing `_data` tables stay and keep passing. A kept table that pins a rule a rows file names prefixes each tag with the row id (`"DEMO-04 strip below 7 em"`); it becomes rows only when its rule changes. New rule rows for a helper go in `tests/flat/<Helper>.js`, run by an `EngineRows` inside the same `tst_<Helper>.qml`.
- A helper that imports `qs.config`, `qs.services.*` or Quickshell gets no rows file: its decision moves into a pure helper first, or stays pinned by its existing test.
- Rows land in the same change as the code they pin, all green; there are no pending or expected-failure rows.
- A row id's prefix is the `prefix` of the manifest entry its file belongs to (an engine's, or a root helper's own `$flat` entry): an upper-case abbreviation, unique across the manifest (`manifests.engines()` reports a repeat).
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

## The manifest
`scripts/engines.json` is the one place tooling learns an engine. It lists only engines whose facade exists and only the domain folders that exist: an engine enters when its facade is built, a domain folder when it is created. There is no lifecycle key; an entry describes the files as they are. `scripts/manifests.py` is its only reader (`engines()`, `flat()`, `domains()`, `tests_for()`, `golden_file()`, `pixel_tests()`, `edit_point_rows()`), and it reports bad JSON, a missing or unknown key, a prefix used twice, a `fedBy` or `intakes` that isn't `{stage: [object]}` and a string or list key of another type (`prefix`, `facade`, `doc`, `folder` and `feeder` are strings; `files`, `owners`, `adapters`, `helpers`, `kits`, `uses`, `itemPaths` and `pluginPaths` lists of strings). Today the manifest lists no engine, one `$flat` entry (`SurfaceContext`), and the domain folders `layer` and `polkit`.

An engine's entry has these keys. Required: `prefix`, `facade`, `files`, `owners`, `adapters`, `tests` and `doc`, plus `editPoints`. Optional, empty by default: `folder`, `helpers`, `kits`, `uses`, `fedBy`, `intakes`, `itemPaths`, `pluginPaths`, `feeder`, `tables` and `alone`.

| Key | Holds |
|---|---|
| `prefix` | the engine's contract-row id prefix, an abbreviation of the engine; nothing else |
| `facade`, `folder` | the facade's name and the engine's folder under `methods/` |
| `files` | the engine's files outside `folder`; an engine is **aligned** when `files` is empty and it has no baseline entry |
| `helpers`, `kits` | files in the folder that are domain helpers, not engine internals; the kits the engine's drawing items call |
| `uses` | the engine or domain folders its files may import |
| `fedBy`, `intakes` | per stage, the cross-engine data edges and the named back edges (The engine graph), each naming its seam |
| `owners`, `adapters`, `itemPaths`, `pluginPaths` | the files that call the facade, by role (Roles); `pluginPaths` are plug-in folders |
| `feeder` | the owner member that gathers a stage's input |
| `tables` | every rules table as `<File>.<property>` with its kind |
| `tests` | `rows`, `golden`, `timeline`, `sweep` and `pixel` |
| `doc`, `editPoints` | the engine's side doc and where each kind of edit goes |
| `alone` | "this decision lives here alone" patterns |

`$flat` holds one entry per root helper that has rows or rules tables, `{prefix, tables}`. `$domains` holds one entry per folder under `methods/` that is not an engine, `{uses, tables}` and a `prefix` where the folder has rows. A prefix is unique across engines, `$flat` and `$domains`.

`python3 scripts/manifests.py --tests-for <path>...` prints the tests of every engine that holds one of the paths (its folder, `files`, `helpers`, `itemPaths`, `pluginPaths`, `adapters`, `owners` or rows folder): the facade's test, its `sweep`, `golden` and `pixel` names. `scripts/dev/verify.sh` runs it on the changed files, so editing a file of a listed engine runs that engine's tests.

`scripts/gen_docs.py` renders the manifest (`scripts/generate.sh` runs it; built, never committed): `docs/dev/generated/engine-manifest.md` (a row per listed engine with its facade, owners, adapters, `fedBy` and `intakes`; each engine's edit points; the rules tables; and › Graph), `docs/dev/generated/engines/<Facade>.md` (a facade's `api`: each stage's or extra's `in` keys, its `extra`, `plugins`, `feeds` and `unfed`, and its `out` producers) and `docs/dev/generated/rules/<File>.<property>.md` (one per `tables` entry of an engine, `$flat` or `$domains`: kind, axes and rows with their `why`). With no engine listed, the manifest page says so and holds only the rules tables `$flat` and `$domains` list.

## The engine graph
Nodes are `<engine>.<stage>`. The edges are:
- the signature edges every engine has: `model` to `solve`, `solve` to `drawn`;
- each `fedBy` entry: data a stage reads from another engine, naming its seam;
- an `api` entry's `feeds`: an extra whose events a stage consumes inside one engine;
- each `intakes` entry: a named back edge an owner or adapter builds. A cross-engine one names its seam; one whose `from` is its own engine names none.

The rendered graph is `docs/dev/generated/engine-manifest.md` › Graph: every edge of the listed engines in three groups, REST (edges into a stage other than `drawn`), INTAKE (the `intakes` entries, each with its rule and seam) and DRAWN (edges into a `drawn` stage). Each line is `<from> ──> <to>` for a forward edge (signature, `fedBy` or `feeds`), followed by ` (feeds)` for a `feeds` edge or ` (<seam>)` for a `fedBy` entry that names one, or `<from> ⇢ <to>` for an intake, followed by its rule and ` (<seam>)` when it names one.

`check_engines` › `dag` holds the manifest and this page to each other:
- the forward graph (signature edges, `fedBy`, `feeds`) is acyclic over all stage nodes, so a loop at rest is either broken by a declared intake or fails (Timing and flow: "Loops at rest are broken only by named intake rules");
- no edge runs from a `drawn` node into another stage;
- an owner or adapter file that calls two stages of one engine has an edge between them in that engine's graph, or the stage's `api` entry lists the other under `unfed` (the owner runs both and carries nothing from one into the other), so an owner-built feed cannot stay invisible;
- every `fedBy` entry and every cross-engine `intakes` entry names a seam that is a row of the Seam register, and every register row between stages of two listed engines is such an entry;
- every `intakes` rule is pinned by a row of the engine's rows file;
- a cycle among the `uses` of domain folders, or among the files of one engine folder, fails.

## Checks
`python3 scripts/check_engines.py` runs these rules over `qml/components/methods/` and the engines the manifest lists. It runs in `scripts/dev/verify.sh` and `scripts/check_all.sh`.

| Rule | Applies to | Fails |
|---|---|---|
| `placed` | `methods/**` | a folder under `methods/` that is neither a listed engine's `folder` nor a `$domains` key; a listed `folder`, `files` or `helpers` path that does not exist; a listed engine whose facade file is missing |
| `purity` | `methods/**` | an import other than `QtQuick`, `qs.components.methods` and the folders the file's engine or `$domains` entry `uses` (a root file has no `uses`, a listed engine's `files` included); `Timer {`; `Date.now(`; `new Date()`; `Math.random`; `console.`; `Qt.callLater` |
| `facade-only` | listed engines (callers anywhere under `qml/`) | outside the engine's files: a use of an internal file; `model` or `reduce` called outside `owners`, `solve` outside `owners` and `adapters`, `drawn` outside `adapters` (Stages › Caller); a kit used outside `itemPaths`; an extra called from a file under `pluginPaths` when its `api` entry has `"extra": true` and no `"plugins": true` |
| `api` | listed engines | in the facade: `api` not JSON; `api` not the first member; a root function no `api` key names, or an `api` key with no function; a function in the one form whose destructure keys differ from its `in`; an `out` producer that is not `<File>.<member>` of an engine file with that member |
| `shape` | listed engines | in the facade: an `api` key that is neither a stage nor an extra; an `in` key the verb does not allow (Stages) or a required group missing; a stage or an extra not in the one form (`function <name>(input) {`, then `const {…} = input;`). In every engine file: a facade over 200 lines, another file over 500, a function over 60, an expression with two or more ternaries |
| `dag` | listed engines, `$domains` | the graph rules above |
| `tables` | listed engines, `$flat`, `$domains` | an owner's `tables` that is not an object; an entry that is not `<File>.<property>` of an existing file with a `kind` of `cell`, `ordered` or `rank`; a table that is not a JSON literal; a cell table with no `axes`; a row with the wrong keys, an empty or missing `why`, or a repeated id; a cell `when` outside `axes`; an ordered `when` that is not a root function of the file; a cell with no row or with two; an ordered table whose last row's `when` is not `true`; a `"rule": "<id>"` literal in an engine file that names neither a table row nor a function |
| `alone` | listed engines (matches anywhere under `qml/`) | a match of an entry's regex in a file outside its `only` paths; a regex that does not compile; `alone` that is not a list |
| `contract` | listed engines | in the rows file: not `var rows = <JSON array>;`; an `api` key no row calls; a rule id (a table row id or a `"rule"` literal of an engine file) no row's `expect` pins; a row whose `call` is not an `api` key; a row with `args` |
| `edit-points` | listed engines | an `editPoints` symbol that is not an engine file's stem, or `<Stem>.<member>` of one of its root members; `editPoints` that is not an object |
| `doc` | listed engines | the `doc` file empty or missing; a heading of The side doc missing or out of order |
| `apply` | an engine's `adapters` and `itemPaths` | a `Qt.callLater` without `// allowed: apply <what>` or `// allowed: settle <what>` on its line; an `onContactsChanged`, `onStretchChanged`, `onCoverChanged`, `onPillsChanged` or `onRequestsChanged` handler; a `setRequest(` call |
| `trace` | everywhere under `qml/` | EngineTrace used in any form but `.record(`, `.forget(` or `.tracing`, or used in an engine's folder or `files` |

A message reads `<file>: <rule> <symbol>: <what>`. The symbol is the enclosing root member and the matched token, `<member>:<token>` (the file's name when no member encloses it); a second instance in one file is numbered `<member>:<token>#2`.

**Baseline.** `scripts/engines-baseline.json` is `{file: {rule: [symbol, ...]}}`: keyed by file and symbol, never a line number. It only shrinks. The check fails on a hit not in it, on an entry whose hit is gone (the change that fixes a hit deletes the entry), and on an entry added since the base. The base is `HEAD^1` in CI, where the checks job fetches two commits, and the merge-base with `origin/main` locally; `--base REF` names another. An entry added since the base is allowed only when its rule is absent from the base's rule list or its file belongs to an engine absent from the base's manifest. `--update-baseline` writes entries only in those cases and otherwise only removes entries whose hit is gone; nobody writes the file by hand.

**Exceptions.** `scripts/engines-exceptions.json` holds permanent exceptions: a file pattern, the rules it waives and the reason, quoting an architect ruling in plain words. An exception that waives nothing fails.

## Editing an engine
Every edit to an engine is one kind below. The table gives where the edit goes, who does it, the side-doc section it updates and the check that catches drift.

| Kind | Edit point (code; manifest key) | Route | Side-doc section updated | Check that catches drift |
|---|---|---|---|---|
| case | a row in the rules table (`tables`; `editPoints.case`) | `/engine-change` | none (Rules links the table's page) | `tables` (one row per cell), `contract` (rule pinned) |
| rule | a function named for the rule, or a table, in its stage's internal file, called by name from the stage (`editPoints.rule`) | `/engine-change` | Rules | `contract`, `tables` (rule literal) |
| input | the feeder (`// reads:`) or the owner's `state`; `api.<stage>.in` (`feeder`; `editPoints.input`) | `/engine-change` | Inputs | `api` (`in` = the destructure line) |
| output | the stage's return with its `rule`; `api.<stage>.out` with its producer (`editPoints.output`) | `/engine-change` | Outputs | `api` (the producer exists) |
| renaming a non-seam output field | the stage's return, `api.<stage>.out`, its readers in the engine's adapters | `/engine-change` | Outputs | `api` |
| consumer | the host (`editPoints.consumer`) | `/engine-change` | Owners, adapters, hosts | `facade-only` |
| adapter or drawing item | the item (`adapters`, `itemPaths`) | `/engine-change` | Owners, adapters, hosts | `facade-only` |
| tuning value | `<Facade>.tuning` (`editPoints.tuning`) | `/engine-change` (a product value's row states the user's answer in its `why`) | Inputs | the engine's rows (`scripts/run_tests.sh <Facade>`); review (Readability › Named numbers) |
| enum value | the cell table's `axes` | `/engine-change` (with the rows completeness then needs) | none (Rules links the table's page) | `tables` (uncovered cell) |
| plug-in | its folder (`pluginPaths`) | its kind's recipe (`/bar-widget`, `/osd-system`, …) | the plug-in's area doc | `facade-only` (plug-in extras) |
| seam change or intake rule | both engines' `api`, `fedBy`/`intakes`, the Seam register row | `/orchestrate` with an architect | Seams of both docs | `dag`, `contract` on both sides |
| moving a stage run to another owner | `owners`; both owners | `/orchestrate` with an architect | Owners, adapters, hosts | `facade-only` |
| moving a rule between engines | the old row removed, the new added with a new id | `/orchestrate` with an architect | Rules of both docs | `contract` |
| new stage or extra | the facade's `api` and function | `/orchestrate` with an architect | Stages | `shape`, `api` |
| file split | split by stage or by rule family | `/engine-change` | Stages | `shape` (lines) |
| helper | the file; `helpers` | `/methods-helper` | Stages | `placed`, `purity`, `dag` |
| exception | a `scripts/engines-exceptions.json` entry with its reason | architect only | Checks | an exception that waives nothing fails |
| kit change | the kit file and its `itemPaths` users (`kits`) | `/engine-change` | Owners, adapters, hosts | `facade-only` |
| rule rename | never: a new id, the old removed with its rows | — | — | `contract` |
| rule removal | the table row or function and its rows, in one change | `/engine-change` | Rules | `contract` |

A facade opens with `api`, then `tuning`, the stages in order, the extras; an internal file opens with its tables.

An engine's edit points are read on its section of `docs/dev/generated/engine-manifest.md` › Edit points, built from the entry's `editPoints`; a rules table's rows on `docs/dev/generated/rules/<File>.<property>.md`. Both pages are generated: an edit goes to the manifest or the table.

The contract grows with the code:
- an edit that adds a case, a rule or an output adds its row in the same change, written first;
- a row id is never reused: a new rule or case takes the next `<prefix>-<nn>`, and a removed one's id stays retired;
- a row for a product answer states the user's answer in its `why`;
- a removed rule removes its rows in the same change.

The recipes: [engine-change](../../recipes/engine-change.md) (run as `/engine-change`) for the kinds routed there, [new-engine](../../recipes/new-engine.md) for a new engine, which is a cross-system change.

## The side doc
Each listed engine has a side doc, the file its manifest `doc` names: `docs/dev/<area>/<engine>-engine.md`, or an `## Engine` section in the area's doc. It describes the engine as it is, and holds the eleven headings below, in this order, each as a `## <n> <Heading>` line (`doc` checks them with `missing_headings`):

| n | Heading | Holds |
|---|---|---|
| 1 | Role | what the engine decides, for whom |
| 2 | Inputs | what reaches each stage and from where (the feeder), and the tuning values |
| 3 | Stages | the stages the engine has, and its helpers and file split |
| 4 | Outputs | the fields each stage returns, and which carry a `rule` |
| 5 | Rules | the rules, and a link to each table's page `docs/dev/generated/rules/<File>.<property>.md` |
| 6 | Owners, adapters, hosts | who calls each stage, the adapters, the drawing items and consumers |
| 7 | Seams | the seams to other engines (Seam register) |
| 8 | Tests | the rows file, the runner test and the other tests |
| 9 | Checks | the checks that hold the engine, and any exception with its reason |
| 10 | Edit points | a link to the engine's section of `docs/dev/generated/engine-manifest.md` › Edit points; never hand-written |
| 11 | Known gaps | what the engine does not do right, stated as it stands |

## Seam register
Every field or flow that crosses between two listed engines is a row here; ids are lowerCamel like a rule id, and the Producer and Consumers cells name stages as backticked `<engine>.<stage>`.

| Id | Field / flow | Shape | Rate | Producer | Consumers | Rule owner |
|---|---|---|---|---|---|---|

