# Singletons doing several jobs

> **Issue:** [Singletons doing several jobs](../issues.md#singletons-doing-several-jobs)
> **Status:** proposed

### Problem
Four services each hold several jobs, so each file is long, its header no longer describes it, and a change to one job means reading the others. Counts are from `main` at 3810528 (files = QML files outside the service that reference it).

- **`services/ui/ShellManager.qml`** (354 lines, 67 files, 49 public members). Its header still says "manages global options and signals". It holds five concerns:
  - the signal bus and link navigation (`openPowerMenu`, `toggle*`, `openOverlayPage`, `showOverlayPage`, `closeOverlay`, `showOsd`, `followLink*`, `linkOrigin`, `openModule`): 20 files;
  - screen targeting (`modeFor`, `targetFor`, `isTarget`, `everywhere`, `showsOn`): 14 files, and named in AGENTS.md › UI conventions;
  - the surface registry (`surfaceShown`, `surfaceWindows`, `openSurfaces`, `grabPartners`, `captureWindows` / `captureFrozen`, modals, step-aside, `borderOpenings`, the bar panels and `barOn`): 34 files;
  - screen layouts' required fields (`requiredFields`, `reportRequiredField`, `newSurfaceKey`): 4 files;
  - session actions (`sessionAction`, `sessionActionInfo`, `destructiveActions`): 6 files. They are the file's only Quickshell.Io use: `execDetached` for `systemctl`, the reason it's in `scripts/quickshell-io-allowlist.json`.
- **`services/ui/EdgeMenuManager.qml`** (829 lines, 31 files). It is the menus' runtime: open and pinned state in `PersistentProperties` and `StateManager`, anchors, claim kinds, reveal, frames the running menus report, and the `edgeMenu` IPC target (9 files). It is also the layouts editor's working copy of `EdgeMenus`: the `ConfigDraft`, selection, the `GridEditor`, add/move/remove, references, previewing, nudging, `showingOthers`, about 550 lines read by 12 files. Then it adds two more things. `cardUnitOf` / `gapOf` / `zoomOf` read only `OverlayConfig` and `GridPlacement`, so they are reader-shaped (8 files, `EdgeMenusConfig` among them). The integrated menus' reserved zones and the `*On` edge measures are the last (12 files).
- **The bar ↔ edge menu cycle.** `BarManager.barStartOn` and `surfaceEnd` add `EdgeMenuManager.zoneOn`. `EdgeMenuManager.reservedOn` / `frameLineOn` / `cornerLineOn` add the same zones to `BarManager.reservedOn` / `frameLine` / `cornerLine`. So one screen edge's geometry is split over two services that call each other, and 22 files call one half or the other. `BarManager` (613 lines) has the same problem as `EdgeMenuManager`: it is the bar editor plus the running bars (`bars`, `edgesFor`, `detachedGaps`, …). `ShellManager.barOn` is a third piece of the same geometry.
- **`services/ui/LauncherCommands.qml`** (1096 lines). The `/config` entry's browser is `_configOptions`, `_configRun`, `_communityOptions`, `_configShow` and `_savedConfigNames` (lines 689–915, about 225 lines). It reads `SettingsManager`, `SavedConfigsManager` and `CommunitySetupsManager`, and nothing else in the file uses it.
- **`services/compositor/KeybindManager.qml`** (1448 lines) is out of scope here. Splitting it into its reader, a `KeybindEditor` and page state goes with [backend stage 7](../backend/roadmap.md) (`compositor.inputs`: Go reads binds and profiles from the config it owns), which changes what the reader half is. Stage 7 designs it.

This affects only contributors: nothing changes for users.

### Options
#### A. Facades: split the code, keep every old name
New singletons hold the code, and `ShellManager` / `EdgeMenuManager` / `BarManager` forward each moved member. No caller changes. The cost is two names for every member and about 150 lines of forwarding. Signals can't be aliased, so they need relays or have to stay. Each "god object" also stays as an index that new code keeps reaching through. It hides the problem more than it fixes it.

#### B. Split by concern, the most-used concern keeps the name
Each concern moves to a service named for it. The concern most callers use keeps the old name, so the busiest call sites don't change:
- `ShellManager` keeps the bus, link navigation and screen targeting (34 files and the AGENTS.md rule untouched). The surface registry and required fields go to a `SurfaceManager`, and the session actions to a session service.
- `EdgeMenuManager` keeps the runtime and the IPC target. The editor becomes a non-singleton `EdgeMenuEditor` beside `GridEditor`, held by `OverlayManager` (which already is the layouts editor and points its `editTarget: "menu"` at this draft). The card-unit helpers go to `EdgeMenusConfig`.
- One new owner of screen-edge geometry holds the running bars, the menu zones, every edge measure and the bar panels. `BarManager` becomes only the bar editor, and the cycle ends.
- The `/config` browser becomes a non-singleton part held by `LauncherCommands`.

Callers of moved members are renamed mechanically, one move per PR with no logic in it. The cost is about 80 caller edits spread over the moves, plus doc updates. The risk is low: every move is a rename that `check_structure` (unknown `FooManager.`) and qmllint catch when one is missed. One alternative for the geometry: `BarManager` takes the menu zones instead of a new owner. That makes fewer edits, but `BarManager` stays editor plus runtime.

#### C. Minimal: headers and the two clear extractions
Reword `ShellManager`'s header, extract the `/config` browser, and move the menu zones into `BarManager` to break the cycle. Leave the rest, with section comments. It is cheap (three small PRs), but it leaves `ShellManager`'s registry and `EdgeMenuManager`'s editor where they are, so the issue mostly stays open.

### Recommendation
B. It fixes the issue the way Phase 3 states it ("each file has one job") while keeping the busiest APIs (the bus and targeting, the menus' runtime) under their names. Every move is mechanical and gets its own PR. Facades (A) would keep the wide surface the issue complains about. C leaves two of the four problems. Holding the edge-menu editor in `OverlayManager` follows the `GridEditor` precedent, and avoids a singleton that would break the `*Manager` naming rule.

### Items
In order. Each is one PR (a move goes alone). Each updates the docs it touches and runs `scripts/check_structure.py`.

1. **Session actions run through `CommandManager.runDetached`** (logic): `systemctl` calls stop using `Quickshell.execDetached`, and `ShellManager` leaves the Quickshell.Io allowlist. Trivial.
2. **Move the session actions to a new `SessionManager` in `services/session/`** (move): `sessionAction`, `sessionActionInfo`, `destructiveActions`. 6 callers renamed (power menu, QuickActions, launcher). Check the name against Quickshell's singletons first. Small.
3. **Move the surface registry to a new `SurfaceManager` in `services/ui/`** (move): surface windows and open surfaces, grab partners, capture windows, modals, step-aside, border openings, required fields and surface keys (not the bar panels, item 4). About 36 callers. `ShellManager`'s header becomes "the shell's signals, link navigation and screen targeting", and `docs/dev/core/shell-manager-targeting.md` sends registry readers to the new doc section. Small (mechanical, wide).
4. **One owner of screen-edge geometry** (move): a new `ScreenEdgeManager` in `services/ui/` takes `BarManager`'s running bars and edge measures (`bars`, `edgesFor`, `barStartOn`, `surfaceEnd`, `screenEdgeOpen`, `reservedOn`, `frameLine`, `cornerLine`, `detachedGaps`), `EdgeMenuManager`'s zones and `*On` measures (`setZone`, `zoneOn`, `reservedOn` → a distinct name, `frameLineOn`, `cornerLineOn`, `heldInset`), and `ShellManager`'s bar panels and `barOn`. The function bodies move as they are. About 28 callers, plus `docs/dev/bar/composition.md`, `edge-menus/hosts.md` and `popouts/held-off-edge.md`. The two `reservedOn`s (bars only, menus included) need two clear names here. Small.
5. **`cardUnitOf` / `gapOf` / `zoomOf` to `EdgeMenusConfig`** (move): they read only readers and methods. 8 callers. Trivial.
6. **The edge-menu editor becomes a new `EdgeMenuEditor` in `services/ui/`, held by `OverlayManager` as `menus`** (move): the draft, selection, `layout`, previewing, references, placement and nudging, `showingOthers`. `EdgeMenuManager` keeps open/pin state, anchors, claim kinds, reveal, reported frames and the IPC target. 12 callers, plus `EditsManager`'s lists, `docs/dev/core/editors-pattern.md`, `overlay/layouts-editor.md` and `services/AGENTS.md`'s non-singleton list. Small.
7. **Extract the `/config` browser to a new `LauncherConfigBrowser` in `services/ui/`**, held by `LauncherCommands` (move): the five `_config*` / `_communityOptions` / `_savedConfigNames` functions. The `config` entry calls it. Add it to `services/AGENTS.md`'s non-singleton list and `docs/dev/features/launcher.md`. Trivial.

The `KeybindManager` split is not an item here: it stays on the issue's stage-7 path.
