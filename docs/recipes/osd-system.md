# Recipe: a new OSD system

> **Use when:** the OSD should show something new: a status icon (tile), a level bar or a card for a feature it doesn't cover yet (it shows up in an OSD's Add picker).
> **Copy from:** `qml/components/surfaces/osd/systems/Caffeine/` (a toggle: one tile, a four-line watcher), `systems/Privacy/` (a set of members: its card made by the engine from `roles`, `groups`, "still" cards), `systems/Drives/` (events: `model: "event"`, `pulse()`, a clickable card handed to its watcher); their rows in `tests/osd/Caffeine.js`, `Privacy.js`, `Drives.js`.
> **Docs:** [OSD](../dev/features/osd.md) (its Engine section is the contract), rules in `qml/components/surfaces/osd/AGENTS.md`; generated: [config/OSDSystems](../dev/config/OSDSystems.md).

## Files to touch
1. `qml/components/surfaces/osd/systems/<Type>/<Type>.qml`: the **definition**, an `OSDSystem`, pure. The folder's name is the type.
2. `qml/components/surfaces/osd/systems/<Type>/<Type>Watch.qml`: the **watcher**, an `OSDWatch`, the only file that reads services.
3. `qml/components/surfaces/osd/systems/<Type>/schema.yaml`: its item in an OSD's `systems` list. The build finds it (`index.yaml`'s `kinds`), expands it over `definitions/kinds/OSDSystemBase.yaml` and adds it to `OSDSystem`'s `oneOf`: nothing else to list.
4. `tests/osd/<Type>.js`: its timeline rows, and its line in `tests/osd/index.js` (the `.import` and the `files` entry). Rows across systems go in `tests/osd/Cross.js`.
5. Optionally `systems/<Type>/design/<File>.qml`: a view only it uses (a bar or card of its own), named by an `exposes` entry's `design`.
6. If a tile's click runs something new: its action ([Actions](../dev/core/actions.md) › Adding an action), then `action` on its `exposes` entry.
7. `qml/config/i18n/*.json`: nothing to do: the pre-commit hook adds the new keys.

## Skeleton
```qml
pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Foo on the OSD: one tile, lit and unusual while on; either way its icon
// (FooWatch reads FooManager)
OSDSystem {
  // I18n.tr("Foo")
  exposes: [
    {
      "key": "foo",
      "part": "tile",
      "icon": "toggle_on",
      "label": "Foo",
      "action": "foo"
    }
  ]
  // No tile(): the default lights a toggle (`value` true) and marks it
  // unusual
}
```
```qml
pragma ComponentBehavior: Bound
import QtQuick
import qs.services.system
import qs.components.surfaces.osd.engine

// Foo's state for the OSD: whether it's on
OSDWatch {
  state: ({
      "foo": {
        "value": FooManager.enabled
      }
    })
}
```
```yaml
label: Foo
icon: toggle_on
group: Power        # one of the OSD groups in index.yaml's x-libraryGroups
tile: standard      # its tiles or bars: the item's `tile` switch
# card: standard    # cards beside its tiles: the item's `card` switch (a card-only system names no part)
# settings:         # its own keys, each with a default; one only its tile uses: x-showIf: {tile: true}
```
```js
.pragma library
// Foo's timelines: a toggle, its icon either way
var rows = [
  { "name": "turned on: its icon, lit and unusual",
    "steps": [
      { "at": 0, "state": { "foo": { "value": false } } },
      { "at": 3000, "state": { "foo": { "value": true } },
        "expect": { "key": "foo", "show": "tile", "kind": "add", "tile": { "on": true, "notable": true }, "host": "ring", "opens": true } } ] }
];
```

## Steps
1. **Decide what each change shows, by the card rule:** a card when the icon alone can't say what changed (something new that needs details: a device's name, a network joined; an unexpected or partial departure: a VPN dropping by itself, one app of several stopping); just the icon for an expected departure and a plain toggle. Write it down as rows first.
2. Pick the model: `scalar` (`{ value }`: a toggle, a device), `set` (`{ members: [{ id, … }] }`: apps, VPNs) or `event` (`{ event, seq }` through the watcher's `pulse()`: something that happens, not a state). A bar is `{ level, muted }` whatever the model.
3. Write the rows in `tests/osd/<Type>.js` and list the file in `index.js`: the first reading (nothing shows; `tiles` checks the tile), each change, a change made on screen (`byUser: true` → `opens: false`), `quiet`, and every guard (unavailable, a reload, a gap). Cross-system ones (a knock-on of airplane mode, a card that takes another's in) in `Cross.js`.
4. Write `schema.yaml` (`label`, `icon`, `group`, its parts, its `settings`).
5. Write the definition: `exposes` (a binding over `options` where its settings pick what it shows), the model and policies (`onAdd`, `onChange`, `onUpdate`, `onRemove`, `onUnexpectedRemove`, `onEvent`), the declarations it needs (osd.md › Engine › The definition: `anyone`, `settledKinds`, `resetBy`, `countsWithin`, `ignoreWithin`, `keepThroughGap`, `memberState`, `carriesEvents`, `alertKinds`, `ownerField` + `groups`, `roles`, `takesIn`, `retractsCardWhenOff`, `yieldsCard`, `knockOnOf`, `userWindow`, …), `tile()`, and `card()` for what its card reads. English strings, declared in a comment as `I18n.tr("…")` calls.
6. Write the watcher: `state` by exposed key, bound to its services; `holds` for a polled service; `settled()` if a service settles after it changes (or, for a change that counts only just after the user's own set, its time in the state and the definition's `countsWithin`); `available: false` while there's nothing to judge; `activate(change)` for a click on a `clickable` card.
7. Run `scripts/run_tests.sh OSDSystems` until its rows pass, then add it to an OSD in Settings and look in a nested shell.

## Gotchas
- **No `judge()` without a reason.** Every shipped system is declarations; a behaviour the engine lacks is a new generic declaration in `OSDEngine` (with a `tst_OSDEngine` case and an osd.md › Engine line), never a type name in the engine or `OSDHost`. A `judge()` that's truly one-off says why above it.
- The definition imports only `QtQuick`, `qs.components.methods` and `qs.components.surfaces.osd.engine` (`check_structure`); anything reading a service goes in the watcher.
- No file of the folder names another (`check_structure`): they're loaded by URL. A design file is named by `design` on its `exposes` entry, not imported.
- Keys are unique in `exposes` and are the on-screen marks by default: a widget or module that changes it calls `ActionsManager.run(id, { fromScreen: true })` (its action's `osdKind`) or `ShellManager.onScreen(<key>)`, so a change made there doesn't open a shut OSD. A connection settling takes longer: raise `userWindow`.
- The watcher's first 1.5 s only moves the state on (services settling), but for an `event` model's events and a key declaring `countsWithin` (it gates itself), which show at once: don't count on a state change at the start being seen.
- An event model's state needs its `seq` (`pulse()` counts it), so the same event twice shows twice and the state read again with another field changed isn't a new one.
- A card-only system (Monitors, Screenshot, Message, Media) names no part in its schema: its item has no switches, only `quiet`.
- An event that's a notification where no OSD shows its card: its service says it through `NotificationManager.announce(system, key, notify, …)`, naming the system and its key (`"Drives", "drive"`), so `OSDConfig.routeOf` (`OSDEngine.cardRoute`) picks the OSD or a notification ([OSD](../dev/features/osd.md) › Where events go). The service sets its event only when the route is the OSD.
- Repeater models and `holds` come from config only, never live values.

## Verify
- `scripts/run_tests.sh OSDSystems` (the timelines) and `scripts/run_tests.sh OSDEngine` if the engine changed.
- `scripts/dev/verify.sh` (`check_structure` checks the folder; `tst_Config` the schema's defaults).
- In a nested shell (`scripts/dev/nested.sh`), add it to an OSD in Settings → Dock & OSD and make it change; `scripts/log.sh` stays clean.

## Docs to update
- [OSD](../dev/features/osd.md) › Systems: a short section for it (its key, what each change shows, its declarations and anything custom).
- Its feature's own doc, a line linking the OSD.
- `docs/dev/live-checks.md`, for what only the real machine shows.
