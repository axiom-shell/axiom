# Writing overlay modules

> **Files:** `components/content/<Type>/<Type>.qml`, `components/content/base/SlotContext.qml`, `components/content/parts/`, `components/methods/GridPlacement.qml`, `config/json/config.schema.json` (`definitions.OverlayModule`)
> **Config:** `Overlay.items[].layout.modules[]`, `EdgeMenus.items[].layout.modules[]` (`{ type, place, properties }`)
> **Related:** [Content roots](content-roots.md), [Pages and grid](pages-and-grid.md), [Growing and expanding](grow-expand.md), [Utility modules](utility-modules.md), [Shared UI pieces](../core/shared-ui-pieces.md)

How a module adapts to any size, the shared parts in `content/parts/`, where data comes from, and how to try a new module safely on the live shell.

### Adding a module type
- The file `content/<type>/<type>.qml` plus an `…OverlayModule` definition in `OverlayModule.oneOf`, with a `"place": { "$ref": "#/definitions/GridPlace" }` property like the others.
- Every module takes every size, from one unit up.
  - `x-defaultSize` is only the size it's added at (left out, a card: `OverlayConfig.defaultSize`).
  - `x-minSize` is only how far a drop into a gap shrinks it.
- Helpers used only by content go in `content/parts/` (subfolders for groups, e.g. `parts/settings/`).
- New types show up in the pickers automatically (see [Layouts editor](layouts-editor.md), module and view pickers).

### Any size
- `Card` and `Panel` (and `TitledCard`) take what they derive from their place from `base/SlotContext`, and expose:
  - `slotRect` (`[x, y, w, h]`)
  - `cols` / `rows` (grid units, four to a card)
  - `shape`: `square` while the longer side is under 1.5× the shorter, else `horizontal` / `vertical` (`GridPlacement.slotShape`)
  - `compact`, plus `pad`.
- A unit is 25 to 140 px depending on the screen or menu (`OverlayGrid`; an edge menu uses its screen's overlay's), and text doesn't scale with it.
  - So a module sets `fullMinWidth` / `fullMinHeight`, the px its full layout needs.
  - `compact` is a quarter card or less (`cols <= 2 && rows <= 2`) or, once laid out, smaller than those.
- Compact shows the key figure: a `compactContent`, usually a `CompactFigure`, on Card, Panel or TitledCard.
- Otherwise the module picks its layout from `shape` and its px room:
  - side by side when wide, stacked when tall;
  - sections dropped or rearranged where they don't fit (Weather's hours and days, ClockCalendar's calendar, Disks' header and columns);
  - a one-row form for strips where it has one (NowPlaying, AudioMixer's slider, Network).
- Thresholds that depend on text are in px from `Appearance.fontSize`, not grid units.
- An edge menu's units aren't square. A layout choice that must match the slot's real proportions reads `innerWidth` / `innerHeight` rather than `shape` (NowPlaying's side-by-side).
- A bare edge menu module drops its padding, unless it draws a box of its own (`drawsBox`, e.g. NowPlaying's blurred cover), which keeps it inside that box.
- On an overlay page with `Overlay.moduleBorders` off a module is bare too, but keeps its padding (`host.padded`).

### Shared parts (`content/parts/`)
- `ModuleHeader`, `Sparkline`, `StatFigure`, `RateLabel`.
- `TileGrid`: lays out `reusable/ActionTile`s (the icon-well tiles the power menu also uses), or `ActionPill`s with a `minAspect`.
- `ExpandButton`: a strip's button growing its detail, hidden where it can't (see [Growing and expanding](grow-expand.md)).
- Radio menus, shared by WifiNetworks and BluetoothDevices:
  - `RadioHeader`
  - `DeviceList`: fixed-height in a popout, off and empty states. A ListView, so only the rows in view are built (Wi-Fi can see dozens of networks); its rows are `DeviceRow`s, as wide as the list.
  - `DeviceRow`: confirm-to-forget, connect; extras beside the title and content under it. Content under it that only shows while `expanded` goes in a Loader active then (as Wi-Fi's password field), or every row builds it.
- `ItemRow`: a plain list entry. An icon or rounded thumbnail, a title of `titleLines`, a muted subtitle, `activated` on a click, and its children as buttons on the right, faint until hovered. Used for clipboard clips, calculator answers, recordings.
- `KeybindSection` (a section of binds as a card, grouped by modifiers), `KeybindRow` (keys first), `KeyCap`, `ModifierCap` and `KeyCluster` draw keybinds read-only, for the Keybinds page and the Cheatsheet module.
- `FigureValue`: the bold value + unit row of `StatFigure` and `CompactFigure`.
- `CompactFigure`: fills its box (inside `pad`).
  - Icon, value and label stacked, or the icon beside them in a wide box.
  - Drops the label and then the icon as room runs out, shrinking the value to fit.
- `EmptyState`: takes an `availableHeight` and drops to its icon when short.
- `PasswordField` is the lock screen's field and `LoginField` the greeter's box (see [Lockscreen](../features/lockscreen.md)); `FocusKeeper` keeps the keyboard on them.
- Generic controls: see [Shared UI pieces](../core/shared-ui-pieces.md).

### Data sources
- `SystemManager` adds:
  - `history: true` (60-sample ring buffers);
  - a `net` metric (`/proc/net/dev` rates; the connection itself is `NetworkingManager.netInfo`);
  - a `processes` metric (`/proc/<pid>/stat`, %CPU since the last sample; `kill(pid)` sends SIGTERM through axiom's `system.kill`).
- Weather comes from `WeatherManager` (`acquire(owner)`, read `weather`, `current`, `condition`, `place`, …).
  - Fetched by axiom (the `weather` topic, `backend/internal/weather`) for the Weather settings' location, units and refresh interval (`WeatherConfig`), shared by every bar widget, module and forecast popout; the greeter's axiom serves the topic too.
  - It fetches only while acquired and keeps its last data when released or when a fetch fails.
- Acquire in `Component.onCompleted`, release in `onDestruction`: modules only exist while their page is shown. (Rule: AGENTS.md › Services, polled data.)

### Repeater models
(Rule: AGENTS.md › UI conventions.)
- For a derived set, use `model: rows.length` with the delegate reading `rows[index] ?? fallback`.
- An `int` / `string` only notifies when it actually changes, so delegates (and Canvases) survive each sample or keystroke.

### Testing
Testing a module safely on the running shell:
- The running shell only picks up schema changes on a QML reload, and a reload only fires when a file it has *loaded* changes. A new module file doesn't count until something uses it.
- A config checked against a stale schema fails validation, and the whole shell falls back to defaults until it's fixed.
- So confirm the schema was reloaded after your edit before putting a new module into `config.json`.
- Add modules one at a time and watch `qs`'s RSS.
