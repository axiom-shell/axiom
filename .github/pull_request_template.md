## What this changes

<!-- What and why, in a few lines. Link the issue: "Fixes #123" closes it on merge, "Part of #123" doesn't. Something bigger with no issue yet? Open one first (a New feature or component request) so the shape is agreed before the code. -->

Fixes #

## Kind

<!-- Tick one; it matches the issue forms. -->

- [ ] Bug fix
- [ ] New feature or component
- [ ] Small feature or improvement
- [ ] Bar widget or module
- [ ] App theme integration
- [ ] Compositor or distribution support
- [ ] Translation
- [ ] Docs, checks or tooling only

## How it was tested

<!-- What you did to check it: reloaded the shell and opened the page, tried it on which compositor(s), ran which tests. Add a screenshot for anything visual (`scripts/dev/shot.sh` takes one). -->

## Checklist

- [ ] `scripts/dev/verify.sh` prints `verify ok` (it formats changed QML and runs the checks the change touches)
- [ ] `scripts/log.sh` shows no new warnings after a reload
- [ ] User-visible text goes through `I18n.tr()` (the pre-commit hook adds the new keys to `qml/config/i18n/`)
- [ ] New settings are in the schema's YAML (`qml/config/schema/`) with a default, plus a reader property
- [ ] A change to the layout of existing config bumps `version`, with a format-2 step (`backend/internal/migrate/steps/`) and a test
- [ ] New side effects (processes, files, sockets) go through the shared services or the `axiom` binary, not a new `Process`/`FileView` (`check_structure` says if not)
- [ ] A change to what an existing shell ↔ binary method or push means bumps `protocol` in `qml/config/json/backend.json` (a new one needs no bump)
- [ ] The docs that verify.sh lists still describe the change (`docs/dev/`, and `docs/` for anything users see)
- [ ] Unrelated problems found along the way are reported as issues, not fixed here
