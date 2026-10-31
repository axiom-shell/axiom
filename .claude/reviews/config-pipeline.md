# config-pipeline
reviewed: b519ddd 2026-10-31  (full)

Sound: the tree, strict YAML reader, schema build, conversion and format-2 steps are tight and tested. One damage path (a format-2 config without a version reruns every step) and a contract gap (no shared fixtures for the condition grammar); the rest is small deletions.

## Open findings
- Major: [A format-2 config without a version runs every step again](../../docs/dev/issues.md#a-format-2-config-without-a-version-runs-every-step-again)
- Major: [The condition grammar has no shared fixtures](../../docs/dev/issues.md#the-condition-grammar-has-no-shared-fixtures)
- Cleanup: [Format-1 secrets plumbing nothing fills or reads](../../docs/dev/issues.md#format-1-secrets-plumbing-nothing-fills-or-reads)
- Cleanup: [The validator and the schema check carry patternProperties nothing uses](../../docs/dev/issues.md#the-validator-and-the-schema-check-carry-patternproperties-nothing-uses)
- Cleanup: [Every step test copies the same case runner](../../docs/dev/issues.md#every-step-test-copies-the-same-case-runner)
- Cleanup: [The config Pipeline interface has one implementation](../../docs/dev/issues.md#the-config-pipeline-interface-has-one-implementation)
- Minor: `backend/internal/schema/yamlsrc/check.go:11` says the validator reads every keyword it accepts; `multipleOf` is never validated.
- Minor: `docs/dev/core/config-v2.md` › Schema source's Weather example lacks `label` and shows old `colors`/`popout`; › Duplicated information removed still lists the root description.
- Minor: the issues.md entry "The schema root's description contradicts the annotations doc" is fixed by the code (no root description in index.yaml or the built schema): remove it.
- Minor: `backend/internal/migrate/steps/v81.go:118` cuts a name at 40 bytes, possibly mid-rune (frozen step).

## Contract
Holds: format 1 is v1–75, converted once (frozen chain to v75, then convert to v76); unknown formats and newer versions are refused; `version` counts on from 76; `meta` replaces `_example`; types in folders found through `kinds`, no definitions list, no per-module default `x-hosts`, no root description; tree order and JS bytes pinned by frozen and shared fixtures; strict.go's refusals hold; every step tested twice; legacy.js and schema-v75.json hash-frozen; every movedKeys path but niri's hotCorner (known) is in the schema. Broken: rule 9's shared fixtures for conditions.

## Coverage
Read deeply: backend/internal/config/ (pipeline, format, ops, load, locate), migrate/steps/ (all), migrate/legacy/legacy.go, schema/ (schema, conditions), yamlsrc strict.go, check.go, assemble.go (core), kinds.go (expand), share/zz_generated_movedkeys.go, config/schema/index.yaml. · Outlined: migrate/convert/convert.go (helpers, compositor, ids, overlayViews read), jsonx/ (fixture-pinned), kinds.go's parts/inherits/extensions, pattern.go. · Skipped: legacy.js (frozen), schema-v75.json (data).

## History
- 2026-10-31 full: 6 findings (2 Major, 4 Cleanup) + 4 Minor; recorded
