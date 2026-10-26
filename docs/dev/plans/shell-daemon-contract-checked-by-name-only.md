# The shell–daemon contract is checked by name only

> **Issue:** The shell–daemon contract is checked by name only (replaced in [issues.md](../issues.md) by the items below, from [Pushes and topics don't declare their types](../issues.md#pushes-and-topics-dont-declare-their-types) on)
> **Status:** decided: B (2026-10-26)

**Decision (2026-10-26):** option B, Go reports its own shapes. Option C's runtime strictness warning is not taken, not even as the recommended add-on, so item 5 (the daemon warning about unknown params) is dropped: non-literal call sites stay unchecked and are listed as such in `rpc.md`. Items 1–4 and 6 became issues.md entries, linked from the roadmap's Phase 4.

### Problem
`scripts/gen_docs.py` (`rpc_scan`) finds both sides of the socket by regex: `rpc.Handle(reg, "name"`, `Broadcast("name"`, `topics.Source{Name:` in Go; `BackendManager.call("name"` / `listen` / `acquire` and `// rpc:` notes in QML. It fails a call to a method the daemon lacks, but never looks at what goes inside one. The fields are typed on one side only:

- **Params**: 57 `rpc.Handle` registrations (plus the compositor's `action` helper) decode into Go structs, most local to the handler (`offsetsParams{Zones}` in `backend/internal/daemon/tools.go`, `caffeineParams{On}` in `idle.go`), some from other packages (`lock.State`, `nightlight.Settings`, `ipcroute.CallParams`, `config.Op` inside `setParams`). The shell writes the keys by hand at 40 `BackendManager.call` sites; 37 pass a literal object or `{}`/`null`, the rest a variable (`CompositorConfigManager._send`'s `inputs`, `SavedConfigsManager._apply`'s `params`, `ClipboardManager`'s `(method, params)`), and the four polled topics' requests are `JSON.parse` of a key.
- **Silent on mismatch**: `rpc.Handle` decodes with `json.Unmarshal`, which ignores unknown fields by design ("for older and newer peers"). Renaming `"zones"` to `"zone"` in `TimeZoneManager` gives Go an empty list and the shell an empty answer: no error, no log line.
- **Results and pushes** are read by name in callbacks and listeners (`result.name` in `SavedConfigsManager.save`, `state.repo` in `UpdatesManager`, `merged?.binds` for `compositor.bindsMerged`), often stored whole and read elsewhere (`root._state = state`). On the Go side pushes are `Broadcast(method, params any, …)`: some typed (`configChanged`, `clipboardState`), some `map[string]any`/`map[string]string` (`schema.error`, `schema.changed`), some pre-marshalled bytes (every `compositor.*` push); several results are `json.RawMessage` (`compositor.entries`).
- **The only guard** is `protocol` in `config/json/backend.json`, bumped by hand (once so far, to 2 in #97). It stops a mismatched shell and binary from talking; it can't notice that one tree's two halves disagree.

Who it affects: anyone changing a method. Backend stage 7 is the next big one: `config.set` path ops replace `config.replace`, `config.changed` carries the change instead of the config, and `compositor.inputs` thins out ([backend roadmap](../backend/roadmap.md)). Those reshape params built in helpers and pushes stored whole, the cases a name check can't see.

### Options
#### A. Parse Go in `gen_docs.py`
Extend `rpc_scan` to resolve each handler's `P` and `R` to its struct and read the `json:` tags; check literal-object keys at QML call sites against `P`.
- Costs: no Go changes. But Python must follow types across packages, embedded structs (`StatusResult` embeds `HelloResult`), anonymous structs (the compositor `action` helper), named non-struct types (`config.Path`), slices and maps, `omitempty` and `-`. Each is regex work that drifts from what `encoding/json` really does.
- Leaves out: pushes (`params any`, decided at the call), topic requests (`Fetch` gets `[]json.RawMessage`), anything not a literal at the QML side.

#### B. Go reports its own shapes; `gen_docs.py` checks against them
`rpc.Handle` already knows `P` and `R` as type parameters. The registry keeps `reflect.Type` for each, and a small walker turns them into field trees by `encoding/json`'s own rules (tags, `omitempty`, embedding, nested structs, slices, maps; `json.RawMessage` and `any` shown as opaque). Pushes get the same by declaring each push with its type once (beside the topic constants), and `topics.Source` names its request and state types. A Go program run by `scripts/generate.sh` (it already runs `go run`) writes the shapes as a gitignored JSON; `gen_docs.py` prints each method's params and result in `rpc.md` and checks every literal-object call site's keys against the params.
- Costs: about 150 lines of Go (registry types, walker, dump, push declarations) plus the Python check; the dump must build the daemon's registry without starting it (registration only stores closures, so a registry-only constructor suffices).
- Risks: opaque spots stay opaque until typed (the `compositor.*` pushes are pre-marshalled bytes; typing them is part of the items).
- Leaves out: non-literal params and result reads, which no static check sees reliably.

#### C. Runtime strictness only
`rpc.Handle` decodes the shell's params with unknown fields reported (a warning in the daemon's log, or a refusal), and nothing is generated.
- Costs: a few lines in `backend/internal/rpc/rpc.go`, and one test.
- Risks: catches a renamed key only when that call runs, in the daemon's log, not in CI; a rarely taken call (a takeover, `share.applyShared`) can ship broken.
- Leaves out: results and pushes entirely, and the reference docs stay names only.

### Recommendation
B, with C's check kept as a warning for the call sites B can't see. Go is the only side that knows its types exactly, and the generics in `rpc.Handle` already hand them over, so the shapes come from `encoding/json`'s own rules rather than a Python imitation of them (A). The static check covers the 37 literal call sites in CI; the runtime warning covers the helper-built params that stage 7 reshapes (`config.set` ops, `compositor.inputs`). Results and pushes become documented shapes in `rpc.md` first; checking their reads is a separate, optional item, since most are stored whole and read in other files. Landing it before stage 7 means that stage's new `config.set` and `config.changed` shapes show up, and are checked, in its own diff.

### Items
1. **The registry records each method's shapes.** `rpc.Handle` stores `P`'s and `R`'s `reflect.Type`; a pure walker turns a type into a field tree by `encoding/json`'s rules (name from the tag, `omitempty`, `-` skipped, embedded fields inlined, slices, maps, nested structs; `json.RawMessage`, `any` and types with their own `MarshalJSON` opaque). Table-driven test in `backend/internal/rpc`. (small)
2. **Pushes and topics declare their types.** Each push named once with its param type (beside the topic constants in `backend/internal/daemon/methods.go`), `Broadcast` calls use the declaration; `topics.Source` gains its request and state types. The `compositor.*` pushes get structs instead of pre-marshalled bytes where that's cheap, opaque otherwise. (small)
3. **A shapes dump in the generate step.** A program under `backend/tools/` builds the daemon's registry without starting a daemon and prints methods, pushes and topics with their field trees as JSON; `scripts/generate.sh` writes it to a gitignored file before `gen_docs.py`. (small)
4. **`rpc.md` shows the shapes and `gen_docs.py` checks literal call sites.** Each method lists its params and result fields, each push its fields. A `BackendManager.call` / `notify` whose params are an object literal fails the check on a key the params don't have (`{}` and `null` pass); non-literal call sites are listed as unchecked in `rpc.md`. `docs/dev/backend/protocol.md` › Changing the protocol says what's checked. (small)
5. **Dropped (C not taken):** ~~The daemon warns about unknown params from the shell.~~ `rpc.Handle` decodes the shell connection's params a second time with unknown fields disallowed when the first decode succeeded, and logs one warning per method and key in the daemon's log (no refusal, so additive changes still need no bump). (trivial)
6. **Optional: result reads in inline callbacks.** In `(error, result) => …` and `listen("x", state => …)` arrow callbacks, a first-level `result.key` / `state.key` read is checked against the result or push fields. Worth it only if items 1–4 show such reads are common enough; otherwise deferred. (small)
