# OSD (on-screen displays)

> **Files:** `config/OSDConfig.qml`, `shell/OSD.qml`, `components/surfaces/osd/OSDContent.qml`, `components/surfaces/osd/OSDBar.qml`, `components/surfaces/osd/PipewireVolumeBar.qml`, `components/surfaces/osd/OSDStatusSource.qml`, `components/surfaces/osd/OSDStatusRow.qml`, `components/surfaces/osd/OSDMediaCard.qml`, `components/surfaces/osd/OSDTriggers.qml`, `components/methods/OSDItems.qml`, `components/views/Settings/OSDListCard.qml`
> **Config:** `OSD.*` (reader `OSDConfig`); entries are `definitions/OSDEntry`
> **Related:** [Brightness](brightness.md), [Lock keys](lock-keys.md), [Held off an edge](../popouts/held-off-edge.md), [Edge attach](../popouts/edge-attach.md), [Popout registry](../popouts/registry.md), [Dock](dock.md)

The on-screen displays: levels (volumes, microphone, brightness) as bars, the state of the machine as status icons (lock keys, the keyboard layout, the microphone muted, the output device, toggles, messages), and the track playing. Each OSD is a configurable `EdgePopout` with its own bars, status icons and now playing card, and shows whichever changed last.

### Config (`OSD` section, `OSDConfig`)
- **Section keys:** `scrollToChange`, `scrollStep`, `items` (the OSDs; each has its own `enabled`; the section-wide one went in config v69).
  - `OSDConfig.scrollStep` is the level change per wheel notch (0–1). It is 0 when scrolling is off.
- **Each OSD** (`definitions/OSDEntry`):
  - `id`, `name`, `enabled`;
  - `screen` (monitors);
  - `edge`, `position`;
  - `detached`, `gap`;
  - `openOnHover`, `timeout`;
  - `bars`: `orientation`, `alongEdge` (its `x-showIf` reads the entry's `edge` through `../`), `showPercent`, `items` (the bars);
  - `statuses`: `row` (`notable` | `all` | `changed`), `items` (the status types shown, chips with `x-enumIcons`), `quiet` (of those, the ones that don't open the OSD; `x-enumFrom: items`);
  - `media`: `enabled`, `onTrackChange`, `onPlayPause`.
  - Until config v86 the bars were `bars`; v86 made them one `items` list with the statuses and media, and v87 split that into these three (a status's own icon went: its icon is what it shows; lock keys became one type per key; an OSD whose items were the default only has its layout keys moved under `bars`).
- **Rebuilds:** the OSDs are read through a JSON string (`_osdsJson`), so a reload that leaves the list unchanged doesn't rebuild them.
- **Reader helpers:**
  - `shownIds` (the enabled ones, by id);
  - `osdById(id)`;
  - `labelOf(osd)` (its tab name: its own, else its bars', else its status icons', else Now playing);
  - `excludedApps`;
  - `messageOsd(id)` (where `axiom ipc osd message` goes: that OSD, else the first showing Messages, else the first).

### Bars (`bars.items`)
Each is `{ type, icon, showOsd, … }`; `icon` empty follows what it shows (the un-muted icon: muted, it's struck through), `showOsd` off lists it without opening the OSD (a change still shows on, and keeps open, an open one). A volume or microphone bar's icon mutes it on a click (`StyledVolumeBar.iconClickable`; an app's bar mutes the streams it matches). Drawn by `OSDBar`:
- **`master`:** the default output's volume; its icon is `AudioManager.outputIcon` (the device's kind, muted, the level), as the Volume widget's.
- **`other`:** the first playing stream that no App bar matches. Other apps skips the App bars of every OSD (`excludedApps`).
- **`app`:** the streams its `apps` match, by name.
- **`microphone`:** the default input's volume.
- **`brightness`:** this screen's brightness, left out when the screen has no controller. With `allMonitors` it covers every monitor at once, showing their mean (see [Brightness](brightness.md)).
- **Default:** Other apps, then System volume.

### Status icons (`statuses`)
Each type is a tile (`OSDItems.tile(type, state)`: `{ icon, label, caption, on, slash, notable, hidden }`), drawn by `OSDStatusRow`: the icon in a rounded square, filled while `on`, faint while off; the one that just changed is the accent and pops in. **One slash style:** `icon` is always the feature's base icon, never its `_off` form, and a toggle that's off (the microphone muted, on battery) is that icon struck through (`slash`, drawn by `SlashedIcon`), as a muted bar's icon is.
- **Clicks:** hovering a tile lightens it and names it and its state in a tooltip; a click flips the ones its source `canToggle` (`OSDStatusSource.toggle`: the layout to the next, the microphone, power saver, caffeine, do not disturb, night light, Wi-Fi, Bluetooth, airplane mode). A click comes while the OSD is open, so its change keeps the part shown (as any status change then does). The type clicked is `OSDContent._held`: the tile stays in the row while the OSD is open, though it turned back to ordinary; closing releases it and the highlight (`OSDContent.hostOpen` turning false). Text only where an icon can't say it: a layout's code drawn in place of the icon (`label`), and beside the row, only as it changes, a device's name or a message (`caption`).
- **`capsLock`, `numLock`, `scrollLock`:** the LED (`LockKeysManager`, held while the source exists, so the LEDs are polled the whole session as with the LockKeys widget); hidden without LEDs. Num Lock on is never unusual (on on most desktops, missing on most laptops).
- **`keyboardLayout`:** its code (`KeyboardLayoutManager`, as the KeyboardLayout widget shows it); hidden with one layout, unusual past the first. A changed list of layouts is a config reload, not a switch.
- **`micMute`:** the input device's icon, unusual while muted (not a device switching).
- **`outputDevice`:** the output device's kind; never unusual, its name shown as it switches from one device to another.
- **`powerProfile`** (`BatteryManager.profile`; unusual off balanced), **`caffeine`**, **`dnd`**, **`nightLight`**, **`airplane`** (unusual while on), **`wifi`** (unusual while off), **`bluetooth`** (never), **`charger`** (`BatteryManager.onBattery`; unusual on battery).
- **`message`:** marks the OSD `axiom ipc osd message <icon> <text>` goes to; a message shows as its icon and text, only as it comes, and opens the OSD unless `message` is in `quiet`.
- **Which show** (`OSDItems.rowTypes`, by `row`): `notable` the unusual ones, `all` every one not hidden, `changed` none; the one that just changed always, in its place.
- **Default:** Caps Lock, Num Lock, the keyboard layout, the microphone muted and the output device, `notable`.

### Now playing (`media`)
The card (`OSDMediaCard`: the cover, title, artist, playing or paused), on a new track (`onTrackChange`) and optionally on play and pause (`onPlayPause`). Off by default.

### What shows (`OSDContent`)
- **One part at a time**, whichever changed last (`shown`):
  - `level` (a bar changed): the bars, with the status icons `row` picks beside them (after them, along the edge's other axis);
  - `status` (a status changed): the status icons alone, the change highlighted (`changed`). Not while the OSD is already open on its bars (`hostOpen`): they stay, the change highlighted in their row, so its shape never changes under the cursor;
  - `media`: the card.
  - With none changed yet, the bars, else the status icons, else the card.
- **Bars' layout:** vertical bars side by side; horizontal bars as rows; or, along its edge, one line parallel to it (end to end when the bars run along it too).
- **Airplane mode keeps the highlight:** Wi-Fi or Bluetooth switching within `OSDItems.radioQuiet` of airplane mode is its own doing and doesn't take the highlight (`OSDItems.replaces`).
- **Its size:** each part's own; the host keeps room for the deepest across its edge (`maxDepth`: the bars and icons together, the icons alone, the card; → `EdgePopout.maxContentDepth`), the icons counted at their largest (`OSDStatusRow.maxDepth`: a tile, along a left or right edge a caption's width), so it isn't resized as it swaps or as icons come and go.
- **Sources** (`OSDStatusSource`, one per status type and one for the card): a Loader building only its type's watcher, so an OSD without a type never wakes its service. Its `tile` follows the state (read only from its own type's service), and `fired` reports the user's changes, never a first reading or a device appearing (each type's own guard, as the microphone bar skips a device switch), and nothing for its first 1.5 s while services settle. Lock key and layout changes are judged by `OSDItems.lockKeyChanged` / `layoutSwitched`. A change opens the OSD unless its type is in `quiet`. The Repeater's model is `_watchKey` (the types as a string), so an edit to any OSD doesn't rebuild the watchers.

### Surface (`shell/OSD`)
- One `EdgePopout` per enabled OSD (`OSDConfig.shownIds`), on each screen its `monitors` puts it on (`General.screensFor(monitors, monitor)`).
- It is keyed by id, so editing an OSD's settings updates it in place instead of rebuilding every OSD.
- Placed at its `edge` / `position`. With `detached` / `gap` it is held off the edge, as a dock is (see [Held off an edge](../popouts/held-off-edge.md)).
- **Popout claim:** it uses `overNamespace: "axiom-osd"` and claims as kind `osd` (`claimKey` `osd:<id>:<screen>`), so it closes under a higher popout and won't open under one (see [Popout registry](../popouts/registry.md)).
- `keepLoaded: true`: the items report their own changes, so they must exist while the OSD is closed.
- Hiding is the host's own hover-aware dismiss timer (`timeout`).

### What opens it (`OSDTriggers`)
- A change opens every OSD holding that item, on the target screen (the focused one), or on all of them in "all" mode. The same item in two OSDs opens both.
- `poke(force)` opens or keeps open, restarting the countdown.
- The settings page's Show button (and `axiom ipc osd show <id>`) goes through `ShellManager.showOsd(id)`: the OSD opens on its bars, else on its status icons as they are, else the card (`OSDContent.preview`).
- `axiom ipc osd message <icon> <text>` / `messageTo <id> <icon> <text>`: `ShellManager.osdMessage`, shown as a status icon and its text on `OSDConfig.messageOsd`'s OSD.
- When an OSD opens, `BrightnessManager.refresh` picks up brightness changed outside axiom on the monitors its brightness bars show (every one for an `allMonitors` bar; none without a brightness bar).

### Editing
- On the section's `x-card` `views/Settings/OSDListCard`:
  - tabs, one per OSD (named by `labelOf`);
  - an edge picker with presets;
  - a Show button;
  - its `sections`, each folding (`EntryListCard`): Status icons (the row's mode, then the status types as a grid of icon chips, then which of them stay quiet), Now playing, then the other settings ("Place and timing"), and Bars last (`lastSections`): their layout and list.
- The App field's chips come from `x-suggestions: "audioApps"` (`SettingsManager.suggestionsFor`).
