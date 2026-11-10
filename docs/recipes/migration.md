# Adding a config migration step

A migration step rewrites config that users already have: it renames, moves, reshapes or re-defaults a key. Every config of an older version runs it on load (config.json, saved configs, imports, the examples). At the end you have a Go step, its test, the new `version`, and readers that expect only the new shape. A purely additive key needs no migration, only a schema default ([setting](setting.md)).

**Copy from:** `backend/internal/migrate/steps/v104.go` + `v104_test.go` (a section rename plus reshaped values, in its own file), the inline `Version: 83` and `Version: 80` steps in `steps.go` (the small cases), `backend/internal/migrate/steps/v83_test.go` for the `runStepCases` helper.
**Background:** [the axiom binary](../dev/backend/README.md), [config manager](../dev/core/config-manager.md) (the load pipeline), [config.json format 2](../dev/core/config-manager.md#the-shape-of-configjson-format-2)

Format 1 is frozen: its migrations (versions 1 to 75, `backend/internal/migrate/legacy/legacy.js`, hash-checked together with `schema-v75.json`) and its conversion to format 2 (version 76, `backend/internal/migrate/convert`) never change. Every new reshape is a **format-2 step**, and a format-1 file runs it after being converted.

## Files
1. `backend/internal/migrate/steps/steps.go`: append `{Version: N, Run: …}` to `all`, N one past the last step. A longer `Run` goes in its own `v<N>.go`, referenced as `{Version: N, Run: v<N>}`, with a comment above the entry saying what it did.
2. `qml/config/schema/index.yaml`: the `default` of `version`, set to N.
3. The schema change itself (`qml/config/schema/`), and every reader and editor of the moved key.
4. `backend/internal/migrate/steps/v<N>_test.go` (or the same file as the step's tests): `runStepCases(t, N, []stepCase{…})`, a row per shape the step meets. The helper also checks that the step reports a change when it made one and that a second run changes nothing.

A short skeleton, for a step that moves `Foo.bar` to `Foo.baz.bar`:
```go
{Version: N, Run: func(cfg *jsonx.Object) []string {
	foo := object(cfg, "Foo")
	if foo == nil {
		return nil
	}
	bar, ok := foo.Get("bar")
	if !ok {
		return nil
	}
	baz := object(foo, "baz")
	if baz == nil {
		baz = jsonx.NewObject()
		foo.Set("baz", baz)
	}
	baz.Set("bar", bar)
	foo.Delete("bar")
	return []string{"Foo.bar moved to Foo.baz.bar"}
}},
```
`object(cfg, path…)` (in `steps.go`) returns the nested object or nil when any part isn't one.

## Steps
1. Change the schema first, then write the step, then its test: the old shape in and the new shape out, a config without the key (nothing to do), one already migrated (unchanged), and odd shapes (a list where an object should be).
2. Bump `version` in `index.yaml`. `TestSchemaVersionIsCurrent` fails until it matches the last step.
3. Change the readers to the new shape. They use no `??` fallbacks, because the step and the schema defaults fill everything.
4. Run the checks.

## Watch out for
- A step runs before unknown keys are pruned and before defaults are filled, so check each value's shape (`.(*jsonx.Object)`, `.(*jsonx.Array)`) and leave what doesn't fit alone. Hand-edited configs hold anything.
- It must be idempotent, because a config may meet it twice (a saved copy, an import). Running it on its own output must change nothing and report nothing.
- Match a collection item by its `id`, never by its position.
- A setting moved out of `x-scope: machine` is missing from older shared files, so applying one would reset it to its default. `share.KeepMovedKeys` keeps the user's value, but its list (`backend/internal/share/movedkeys.go`) was generated once for format 1 and is frozen. A format-2 move needs that mechanism extended to format-2 versions first.
- The running shell's axiom loaded the schema at its start. Test the step with `axiom config validate <file>` (read-only) on a scratch copy of the config, and look at the new shape in `scripts/dev/nested.sh`. Don't write the real config.json.

## Check it
- `scripts/check_go.sh` (the steps' tests and `TestSchemaVersionIsCurrent`), or just `go -C backend test ./internal/migrate/steps`
- `scripts/dev/verify.sh`
- `axiom config validate <scratch copy of config.json>`: it lists the step's changes and says the file is valid.

## Docs to update
- The section's reference doc in `docs/dev/config/` is generated. A doc that names the old key needs a manual edit: `grep -rn 'Section.oldKey' docs/`.
