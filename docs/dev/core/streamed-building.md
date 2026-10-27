# Streamed building

> **Files:** `services/core/BuildQueueManager.qml`, `components/reusable/StreamedLoader.qml`, `components/views/base/BaseView.qml`, `components/hosts/overlay/ModuleGrid.qml`, `components/hosts/overlay/OverlayPages.qml`, `components/hosts/overlay/OverlayPage.qml`, `services/core/ConfigDraft.qml`, `scripts/dev/bench_overlay.sh`
> **Config:** none
> **Related:** [Overlay pages and the module grid](../overlay/pages-and-grid.md) (Loading), [Shared UI pieces](shared-ui-pieces.md), [Editors pattern](editors-pattern.md), [QML pitfalls](qml-pitfalls.md), [Testing](../testing.md)

How the overlay shows a page at once and fills it in over the next frames, instead of freezing while everything on it is built. QML builds synchronously: whatever a page instantiates is built in the frame it appears, and before the window has even mapped when the overlay opens. On a slow laptop a page of 34 small modules once took 8.4 s to open this way. Read this before adding a tool page, a heavy panel or a long list.

### The queue (`BuildQueueManager`)
- One queue for the whole shell. A caller queues a job (`request(owner, job, label)`: a function that builds something) and drops its jobs when it goes away (`cancel(owner)` from `onDestruction`).
- A Timer runs jobs every 16 ms while any are waiting, within a 6 ms budget a step, and always at least one, however long it takes. A single job can't be split, so a job's own size is the frame it costs.
- Jobs whose owner is `visible` go first: the page on screen fills in before its hidden neighbours.
- A job is dropped from the queue once it has run, not before, so `pending` stays above 0 while the last job builds and what it makes still streams.
- A job taking over 16 ms logs `Built <label> in X ms` (`scripts/log.sh --debug`): a hitch to look at.

### `StreamedLoader` (`reusable/`)
A Loader that queues its own build, then fades in. Use it for a page's panels, cards, sections and anything built hidden.
- Lay it out as its content would be: `Layout.*`, `x`/`y`/`width`/`height` or anchors go on the loader. It takes the item's implicit size, and sizes the item to its own when it has one, so give it a size (e.g. `Layout.preferredWidth: root.sideWidth`) where the page's box mustn't change size as it fills in.
- Data goes in from the loader's properties: a Repeater's `required` ones are declared on the loader, and the content reads `loaderId.modelData` (with `pragma ComponentBehavior: Bound`).
- `wanted: false` doesn't build it, or unbuilds it, as `active`. Use it for content shown only in some mode (Keybinds' keyboard reference, the editing inspector), with the mode's own condition, never `visible`: an item on a hidden neighbour page is not `visible`, so `wanted: visible` would build it only once on screen and drop it whenever the page slides away.
- `label` names it in the slow-job log.
- Anything can be loaded, a `Popup` included (Keybinds' presets): it's parented to the loader, so put the loader where the popup's `x`/`y` are measured from. Call into it as `(loader.item as Type)?.fn()`.
- Ids inside it are out of reach from outside. Something the page calls by id (`month.showDay`) or reads through an alias stays outside; stream its insides instead (`MonthGrid` streams its day cells, `GridCanvas` its tiles).

### When a loader streams
- While its page is first being built: the nearest ancestor with a `buildStreaming` property (`BaseView`'s) says so when the loader is made. `BaseView.buildStreaming` is true from the page's creation until the queue first drains (or at once, if the page queued nothing).
- Made later (a search narrowing a list, a tab switch, a selection), it builds at once like a plain Loader, so the page doesn't fade parts of itself in again while it's being used.
- `always: true` streams whenever it's made: the settings cards (a category switch builds a whole category), except while listing search results, where typing would fade every card in again.
- With no `BaseView` above it (a bar popout, an edge menu), it always streams.
- `stream: false`: never.

### Overlay pages
- Opening or switching builds only the page shown, and its neighbours after it has slid in (`OverlayPages._settled`): see [pages-and-grid › Loading](../overlay/pages-and-grid.md).
- A Custom page's `ModuleGrid` has `stream: true`: its modules are queued in reveal order, top left to bottom right (`GridPlacement.revealOrder`), and fade in (`OverlaySlot.active` / `ready`). The grid is sized from the places, so only a module that grows (`grow`) moves the ones below it as it arrives, since its height is known once it's built. Once all have arrived, modules added later build at once (`_streamed`).
- Every tool page streams its parts. A page's own synchronous build (`Overlay page N built in X ms`) is what's left: the page's frame, what it calls by id, and the first frame of each loader.
  - **Settings**: the sidebar, then each card of the category, and each `SchemaPropertiesForm` field.
  - **BarEditor**: the bars panel (each field group, each field), the sections board, the widget inspector.
  - **Layouts**: the side panel, the canvas's tiles, the module library.
  - **Keybinds**: the header chips, each bind section, the presets popup; the keyboard reference and the editing inspector only in their modes.
  - **Themes**: the wallpaper picker, theme picker, palette and look settings.
  - **Monitors**: the canvas and the inspector.
  - **CalendarPage**: the month's day cells (`MonthGrid`, shared with the Clock/Calendar module).

### Editors reopening
- Pages are rebuilt on every open, so each editor's `ensureLoaded()` used to reload its draft every time: a clone of its config section, then every binding on it evaluated again.
- `ConfigDraft.loadIfStale()` reloads only when the draft has no unsaved edits and is empty or the config isn't the object it was loaded from (`ConfigManager` makes a new config object on every change). Settings and Keybinds use it.
- Editors that also clear their selection or history on reopening (layouts, edge menus, screen layouts) still `load()`.

### What made pages slow (keep these out)
- **Content built hidden.** A `visible: false` item is still built. Gate it with a Loader (`wanted`, `active`) or a `StreamedLoader`. A compact `Card`/`Panel` still builds its full layout under its `compactContent`: see [issues.md](../issues.md).
- **Unbounded lists in a Repeater.** Wi-Fi saw 52 networks, and a row each (with a password field) took 1.8 s. Use a ListView, which builds only the rows in view (`DeviceList`), and build a row's expansion only while expanded (Wi-Fi's password field).
- **Repeater models of whole objects.** Key by count and read the object by index (`model: list.length`), as AGENTS.md says: an object model is copied for every delegate, and rebuilds them on any change.
- **Data reloaded on open.** See Editors reopening.

### Measuring
- `scripts/dev/bench_overlay.sh [-w SECONDS] [-n CYCLES] [-p PID] [--mem] [PAGE…]` opens the overlay, switches to each page given, closes it, and prints for each step how long the IPC call blocked (a no-op call is ~25 ms) and the log lines from the build: `Overlay page N built in X ms` (the page's synchronous build, `OverlayPage`), `Overlay modules streamed in X ms (N modules)` (`ModuleGrid`), and `Built <label> in X ms` (a slow job). `-n` repeats the cycle, `-p` drives a nested qs instead of the live one, `--mem` adds a [memory reading](memory.md) after each cycle.
- Wait long enough for the neighbours (`-w`, default 1.5 s): a neighbour built during the next step's IPC call shows in that step.
- A temporary `console.log(Date.now() - t)` around a suspect, bisected, finds what a slow job holds; remove it after.
