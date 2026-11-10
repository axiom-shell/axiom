# Adding an OSD system

An OSD system is one feature's contribution to the on-screen display: a status icon (tile), a level bar, a card saying what changed, or a mix. Users add it to an OSD from the Add picker in Settings. At the end you have a folder with a pure definition of what each change shows, a watcher that feeds it from services, and timeline tests that pin the behaviour down.

**Copy from:** `qml/components/surfaces/osd/systems/Caffeine/` (a toggle: one tile and a four-line watcher) with its rows in `tests/osd/Caffeine.js`; `systems/Privacy/` (a set of members, its card built by the engine from `roles` and `groups`); `systems/Drives/` (events: `model: "event"`, `pulse()`, a clickable card handled in the watcher).
**Background:** [OSD](../dev/features/osd.md) (its **Engine** section is the contract), [actions](../dev/core/actions.md); generated: [config/OSDSystems](../dev/config/OSDSystems.md)

## Files
1. `qml/components/surfaces/osd/systems/<Type>/<Type>.qml`: the **definition**, an `OSDSystem`. It is pure, and the folder name is the type.
2. `qml/components/surfaces/osd/systems/<Type>/<Type>Watch.qml`: the **watcher**, an `OSDWatch`. It is the only file that reads services.
3. `qml/components/surfaces/osd/systems/<Type>/schema.yaml`: the system's item in an OSD's `systems` list. The build expands it over `qml/config/schema/definitions/kinds/OSDSystemBase.yaml` (which adds `quiet` and the optional `tile` and `card` switches) and registers it; nothing else to list.
4. `tests/osd/<Type>.js` and its `.import` plus `files` entry in `tests/osd/index.js`. Rows that span systems go in `tests/osd/Cross.js`.
5. Optionally `systems/<Type>/design/<File>.qml`: a view only this system uses, named by `design` on an `exposes` entry.
6. If clicking a tile should run something new, add the action first ([actions](../dev/core/actions.md) › Adding an action), then name it in `action` on the `exposes` entry.

Translation files need nothing: the pre-commit hook adds new strings to every language.

## Steps
1. Decide what each change shows, by the card rule. A card when the icon alone can't say what changed (something new with details, such as a device's name, or an unexpected or partial departure, such as a VPN dropping by itself). Just the icon for an expected departure and for a plain toggle. Write this down as timeline rows first.
2. Pick the model: `scalar` (`{ value }`: a toggle, a device), `set` (`{ members: [{ id, … }] }`: apps, VPNs) or `event` (`{ event, seq }` through the watcher's `pulse()`: something that happens rather than a state). A bar's state is `{ level, muted }` whatever the model.
3. Write the rows in `tests/osd/<Type>.js` and list the file in `index.js`. Cover the first reading (nothing shows), each change, a change made on screen (`byUser: true` gives `opens: false`), `quiet`, and every guard (unavailable, a reload, a gap). The row format is in osd.md › Engine › Timelines.
4. Write `schema.yaml`: `label`, `icon`, `group` (one of the OSD groups at the end of `x-libraryGroups` in `qml/config/schema/index.yaml`), `tile: standard` and/or `card: standard`, and `settings` for the system's own keys. A system with bars also writes `barNames`, which `tst_OSDSystems` checks against `exposes` (see the Audio and Brightness schemas). A card-only system names no part.
5. Write the definition: `exposes` (a binding over `options` when settings choose what shows), the model, the policies (`onAdd`, `onChange`, `onUpdate`, `onRemove`, `onUnexpectedRemove`, `onEvent`), the declarations it needs (osd.md › Engine › The definition lists them all), `tile()`, and `card()` for what its card reads. English strings are declared in a comment as `I18n.tr("…")` calls.
6. Write the watcher: `state` keyed by exposed key and bound to its services. Add `holds` for a polled service, `settled()` if a service settles after it changes, `available: false` while there is nothing to judge, and `activate(change)` for a click on a clickable card.
7. Run `scripts/run_tests.sh OSDSystems` until the rows pass, then add the system to an OSD in Settings in a nested shell and make it change.

## Watch out for
- **No `judge()` without a reason.** Every shipped system is declarations. A behaviour the engine lacks becomes a new generic declaration in `OSDEngine` (with a `tst_OSDEngine` case and a line in osd.md › Engine), never a system's name in the engine or in `OSDHost`. A one-off `judge()` says why above it.
- The definition imports only `QtQuick`, `qs.components.methods` and `qs.components.surfaces.osd.engine` (`check_structure`), so the test can load it; anything that reads a service goes in the watcher.
- No file of the folder names another (`check_structure`), because they are loaded by URL. A design file is named by `design`, not imported.
- Keys in `exposes` are unique and are the marks for changes made on screen. A widget or module that changes the value calls `ActionsManager.run(id, { fromScreen: true })` (the action's `osdKind`) or `ShellManager.onScreen(<key>)`, so a change made there doesn't open a shut OSD. A connection that settles slowly needs a longer `userWindow`.
- The watcher's first 1.5 seconds only move its state on, while services settle. Event models and keys declaring `countsWithin` are the exceptions and show at once, so don't expect a state change at the start to be seen.
- An event model's state needs its `seq` (`pulse()` counts it), so the same event twice shows twice, and a re-read with another field changed isn't a new event.
- An event that becomes a notification where no OSD shows its card goes through `NotificationManager.announce(system, key, notify, …)`, which picks the OSD or a notification by `OSDConfig.routeOf` (`OSDEngine.cardRoute`; see osd.md › Where events go). The service sets its event only when the route is the OSD, as `DrivesManager` does.
- Repeater models and `holds` come from config only, never live values.

## Check it
- `scripts/run_tests.sh OSDSystems` for the timelines, and `scripts/run_tests.sh OSDEngine` if the engine changed.
- `scripts/dev/verify.sh` (`check_structure` checks the folder, `tst_Config` the schema defaults).
- In `scripts/dev/nested.sh`, add the system under Settings › OSD, make it change, and check `scripts/log.sh` stays clean.

## Docs to update
- [OSD](../dev/features/osd.md) › Systems: a short section for the system (its key, what each change shows, its declarations and anything custom).
- The doc of the feature the system shows, with a line linking the OSD.
