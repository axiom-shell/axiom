# Growing and expanding modules

> **Files:** `qml/components/hosts/overlay/ModuleGrid.qml`, `qml/components/hosts/overlay/ExpandedModule.qml`, `qml/components/hosts/overlay/OverlaySlot.qml`, `qml/components/content/base/Card.qml`, `qml/components/content/base/Panel.qml`, `qml/components/content/parts/ExpandButton.qml`, `qml/components/methods/GridPlacement.qml`
> **Config:** module `properties.grow` (Notifications, Agenda, WifiNetworks, BluetoothDevices, AudioMixer)
> **Related:** [Writing modules](writing-modules.md), [Pages and grid](pages-and-grid.md), [Grid canvas](grid-canvas.md), [Edge menu hosts](../edge-menus/hosts.md), [Popout edge attach](../popouts/edge-attach.md)

Two runtime ways a module gets more room than its `place`: **growing** (taking extra rows while its content wants them) and **expanding** (a detail view over the whole grid, like Android's quick settings). Neither changes the config.

### Growing: who and how much
- A module with `properties.grow` takes up to that many rows while its content wants them: Notifications, Agenda, WifiNetworks, BluetoothDevices, AudioMixer.
  - The field is in each one's schema, since forms don't follow `$ref`.
- It says how tall through `wantedHeight` on Card/Panel:
  - its height plus what its scrolling list is short of, or less what it has spare (`DeviceList.overflow`);
  - while compact (nothing laid out to measure), any positive value.
- The grid reads `growHeight`:
  - that, never less than `fullMinHeight` and the padding around it (and at least three rows for one two units wide), so growing reaches the full layout and never shrinks it back to compact;
  - nothing for a module too narrow for its full layout.
- That figure doesn't depend on its own height once laid out, so it settles.

### Growing: layout in `ModuleGrid`
- `ModuleGrid` counts the rows in its ungrown unit (`rowsFor`) and keeps them in `growth`.
  - Set a tick later (`Qt.callLater`), so a module's size never feeds back into itself in one pass.
- It shows `places`, from `GridPlacement.grown(places, growth, growTowards)`. Each grown module:
  1. first takes the free rows in its columns towards the grid's edge;
     - `growTowards` -1: up to row 0, on pages, top or side menus and submenus;
     - `growTowards` 1: down to the last row, on a bottom menu, whose edge is under it;
  2. then grows away from it, pushing what's there along (others stay);
  3. the result is shifted back to row 0.
- Its `bounds` and size follow, so pages and menus grow.
- Only height grows, never width: a page or top menu grows down, a bottom one up, and a side menu down along its edge from where its modules start.
- Slots glide to new places (`animNormal`), the module already at its new size and revealed by its slot.

### Growing: limits and hosts
- Growth is runtime only: the config keeps `place`.
- The layouts canvas draws the most a module can take alone as a dashed outline round it (`GridPlacement.growthAround` → `CanvasModule.growth`).
- Not on a bounded grid (the lock screen, the greeter).
- A floating top or bottom menu keeps room for its deepest (`EdgeMenuBody.maxGrownHeight` → `EdgePopout.maxContentDepth`).
- An integrated menu's zone follows it, so windows move.

### Expanding: API
- `expand(type, properties, from)` on `Card` / `Panel`. Call `canExpand(type)` first, to offer it only where it works.
- It goes through `expander`, the hosting `ModuleGrid` (passed down by `OverlaySlot`).
  - `expander` is null on the lock screen and greeter, and for types the host's `x-hosts` don't take.

### Expanding: `hosts/overlay/ExpandedModule`
- Grows a card box out of `from` (an item in the module; the whole module when left out) to the grid's rect less an `inset` on every side (the grid's gap), with `animNormal`.
- A header holds only a back button, over `content/<type>/<type>.qml` (which names itself).
- The content is loaded at its full size, bare but padded (`host.padded`, which keeps SlotContext's `pad`).
  - The grid's whole bounds are its `slotRect`, and it gets no `expander`, so it isn't compact and can't expand again.
- It's revealed by the box rather than resized.
- The modules under it dim (still seen around it) and take no input.
- Content that draws its own box (`drawsBox`, NowPlaying's blurred cover) starts below the back button's row; other content tucks up under it.
- Back, Escape (the layer takes the keyboard and gives it back) or a click beside the box shrink it into `from`, and it unloads. So it acquires and releases as any module does.
- It stays inside the grid: an edge menu's window, blur shape and footprint don't change, and a small menu shows the detail's compact form.
- The box is opaque and outlined even in a menu without module borders, as it floats over the dimmed modules.

### Expanding: who expands
- `QuickActions`:
  - Wi-Fi → WifiNetworks
  - Bluetooth → BluetoothDevices
  - Do not disturb → Notifications
  - Brightness → Brightness on every monitor: an `opensOnly` action, which a tap opens since it has nothing to switch.
  - The trigger is a pill from beside its icon, or a tile on a right click or long press.
- As a strip, each into its full form:
  - AudioMixer: its slider row's `parts/ExpandButton`;
  - Network → WifiNetworks;
  - NowPlaying: a tap on the track;
  - Brightness: its expand button, while some of its sliders are scrolled out of sight.
