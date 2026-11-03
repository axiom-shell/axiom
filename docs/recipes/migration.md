# Recipe: a config migration step

> **Use when:** renaming, moving, reshaping or re-defaulting a key that existing configs already have. A purely additive key needs no migration ([setting](setting.md)).
> **Copy from:** `backend/internal/migrate/convert/convert.go` (helpers that move and rename keys of a format-1 config: the same work, once).
> **Docs:** [the axiom binary](../dev/backend/README.md), [config-manager](../dev/core/config-manager.md) (load pipeline), [config v2](../dev/core/config-v2.md)

The format-1 migrations (versions 1 to 75) are **frozen** and kept only until format 1 is retired: the binary runs `backend/internal/migrate/legacy/legacy.js` (the shell's old migrations, converted once) on configs from before it took the config over, then converts them to format 2 (version 76, `migrate/convert`). None of those files changes; `legacy.js` and `schema-v75.json` are hash-checked, and their frozen cases (`legacy/testdata/`) check the output.

A reshape now is a **format-2 step** in `backend/internal/migrate/steps/`: every config of an older version runs it on load (config.json, saved configs, imports, examples), and a format-1 file runs it after its conversion.

## Files to touch
1. `backend/internal/migrate/steps/steps.go`: a `Step{Version: N, Run: …}` appended to `all`, N one past the last (the first is 77). Put a longer `Run` in its own file, `v<N>.go`.
2. `qml/config/schema/index.yaml`: `version`'s `default` to N.
3. The schema change itself (`qml/config/schema/`), and the readers and editors that read the moved key.
4. `backend/internal/migrate/steps/steps_test.go` (or `v<N>_test.go`): `runStepCases(t, <N>, []stepCase{…})`, a row per shape the step meets (it also checks a second run changes nothing).

## Skeleton
```go
// v77 moved Foo.bar into Foo.baz.bar
{Version: 77, Run: func(cfg *jsonx.Object) []string {
	foo, _ := cfg.Value("Foo").(*jsonx.Object)
	if foo == nil {
		return nil
	}
	bar, ok := foo.Get("bar")
	if !ok {
		return nil
	}
	baz, _ := foo.Value("baz").(*jsonx.Object)
	if baz == nil {
		baz = jsonx.NewObject()
		foo.Set("baz", baz)
	}
	baz.Set("bar", bar)
	foo.Delete("bar")
	return []string{"Foo.bar moved to Foo.baz.bar"}
}},
```

## Steps
1. Change the schema, then write the step, then its test: the old shape in, the new shape out, plus a config without the key (nothing to do) and one already migrated (unchanged).
2. Bump `version` in `index.yaml` (`TestSchemaVersionIsCurrent` fails until it matches).
3. Change the readers to the new shape (no `??` fallbacks: the step and the defaults fill it).
4. Verify.

## Gotchas
- A step runs before unknown keys are pruned and defaults filled: check each value's shape (`.(*jsonx.Object)`, `.(*jsonx.Array)`) and leave what doesn't fit alone.
- It must be idempotent: running it on its own output changes nothing.
- A collection item is matched by its `id`, never its position.
- A setting moved out of `x-scope` `machine` isn't in older shared files, so applying one would reset it to its default. `share.KeepMovedKeys` keeps the user's value for format-1 files only (its list is frozen): a format-2 move needs it extended to format-2 versions first.
- The live shell's axiom loaded the schema at its start: test the step with `axiom config validate <file>` (read-only) on a scratch copy, and the new shape in `scripts/dev/nested.sh`.

## Verify
- `scripts/check_go.sh` (the steps' tests, `TestSchemaVersionIsCurrent`)
- `scripts/dev/verify.sh`
- `axiom config validate <scratch copy of config.json>`: the step's change is listed, and the file is valid.

## Docs to update
- The section's generated doc updates itself (`docs/dev/config/`); a doc describing the old key by name: `grep -rn 'Section.oldKey' docs/`.
