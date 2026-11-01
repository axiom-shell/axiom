# OSD (on-screen displays)

> **Files:** `config/OSDConfig.qml`, `shell/OSD.qml`, `components/surfaces/osd/OSDContent.qml`, `components/surfaces/osd/OSDBar.qml`, `components/surfaces/osd/PipewireVolumeBar.qml`, `components/surfaces/osd/OSDStatusSource.qml`, `components/surfaces/osd/OSDStatusLine.qml`, `components/surfaces/osd/OSDMediaCard.qml`, `components/surfaces/osd/OSDTriggers.qml`, `components/methods/OSDItems.qml`, `components/views/Settings/OSDListCard.qml`
> **Config:** `OSD.*` (reader `OSDConfig`); entries are `definitions/OSDEntry`
> **Related:** [Brightness](brightness.md), [Lock keys](lock-keys.md), [Held off an edge](../popouts/held-off-edge.md), [Edge attach](../popouts/edge-attach.md), [Popout registry](../popouts/registry.md), [Dock](dock.md)

The on-screen displays: levels (volumes, microphone, brightness), statuses (lock keys, the keyboard layout, the microphone muted, the output device, toggles, messages) and the track playing. Each OSD is a configurable `EdgePopout` holding a list of items, and shows whichever of them changed last.

### Config (`OSD` section, `OSDConfig`)
- **Section keys:** `scrollToChange`, `scrollStep`, `items` (the OSDs; each has its own `enabled`; the section-wide one went in config v69).
  - `OSDConfig.scrollStep` is the level change per wheel notch (0–1). It is 0 when scrolling is off.
- **Each OSD** (`definitions/OSDEntry`):
  - `id`, `name`, `enabled`;
  - `screen` (monitors);
  - `edge`, `position`;
  - `detached`, `gap`;
  - `orientation`, `alongEdge` (the levels' layout only);
  - `openOnHover`, `timeout`, `showPercent`;
  - `items` (`bars` until config v86, whose step renames it and gives an OSD still on the old default, Other apps then System volume, the new default's four statuses after them).
- **Rebuilds:** the OSDs are read through a JSON string (`_osdsJson`), so a reload that leaves the list unchanged doesn't rebuild them.
- **Reader helpers:**
  - `shownIds` (the enabled ones, by id);
  - `osdById(id)`;
  - `labelOf(osd)` (its tab name: its own, else its levels', else its other items');
  - `excludedApps`;
  - `messageOsd(id)` (where `axiom ipc osd message` goes: that OSD, else the first with a Messages item, else the first).

### Items
Each item is `{ type, icon, showOsd, … }`; `icon` empty follows what it shows, `showOsd` off lists it without opening the OSD (a change still shows on, and keeps open, an open one). Their **shape** is `OSDItems.shapeOf(type)`:
- **Levels**, drawn by `OSDBar`:
  - **`master`:** the default output's volume; its icon is `AudioManager.outputIcon` (the device's kind, muted, the level), as the Volume widget's.
  - **`other`:** the first playing stream that no App bar matches. Other apps skips the App bars of every OSD (`excludedApps`).
  - **`app`:** the streams its `apps` match, by name.
  - **`microphone`:** the default input's volume.
  - **`brightness`:** this screen's brightness, left out when the screen has no controller. With `allMonitors` it covers every monitor at once, showing their mean (see [Brightness](brightness.md)).
- **Statuses**, one line each (`OSDStatusLine`: the icon and a short text, as tall as a horizontal bar, cross-fading to the next):
  - **`lockKeys`:** Caps, Num or Scroll Lock toggled (its `caps`, `num`, `scroll` say which; `LockKeysManager`, held while the item exists, so the LEDs are polled the whole session as with the LockKeys widget).
  - **`keyboardLayout`:** the layout switched (`KeyboardLayoutManager`); its name. Silent with one layout, and a changed list of layouts is a config reload, not a switch.
  - **`micMute`:** the default input muted or unmuted (not a device switching).
  - **`outputDevice`:** the default output switched from one device to another; its name and kind's icon.
  - **`powerProfile`** (`BatteryManager.profile`), **`caffeine`**, **`dnd`**, **`nightLight`**, **`wifi`**, **`bluetooth`**, **`airplane`**, **`charger`** (`BatteryManager.onBattery`): on or off, or the profile.
  - **`message`:** marks the OSD `axiom ipc osd message <icon> <text>` goes to; its `icon` stands in for a message without one.
- **Media** (`media`): the now playing card (`OSDMediaCard`: the cover, title, artist, playing or paused), on a new track (`onTrackChange`) and optionally on play and pause (`onPlayPause`). Not in the default.
- **Default:** Other apps, System volume, then lock keys, the keyboard layout, the microphone muted and the output device.

### What shows (`OSDContent`)
- **One part at a time:** the levels, the status line or the card, whichever changed last (`shown`). A level change shows the levels; a status the line, never beside the bars. With none changed yet, the levels, else the first part it has.
- **Levels' layout:** vertical bars side by side; horizontal bars as rows; or, along its edge, one line parallel to it (end to end when the bars run along it too).
- **Statuses don't cut in on airplane mode:** Wi-Fi or Bluetooth switching within `OSDItems.radioQuiet` of an airplane mode line is airplane mode's own doing and doesn't replace it (`OSDItems.replaces`).
- **Its size:** each part's own; the host keeps room for the deepest across its edge (`maxDepth` → `EdgePopout.maxContentDepth`), so it isn't resized as it swaps.
- **Sources** (`OSDStatusSource`, one per status or media item): a Loader building only its type's watcher, so an OSD without a type never wakes its service. It reports the user's changes as a line, never a first reading or a device appearing (each type's own guard, as the microphone bar skips a device switch), and nothing for its first 1.5 s while services settle. Lock key and layout changes are judged by `OSDItems.lockKeyChange` / `layoutSwitched`; the texts come from `OSDItems.status` and are translated by the source.

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
- The settings page's Show button (and `axiom ipc osd show <id>`) goes through `ShellManager.showOsd(id)`: the OSD opens on its levels, or with none, on what its first status (or the card) shows now (`OSDContent.preview`).
- `axiom ipc osd message <icon> <text>` / `messageTo <id> <icon> <text>`: `ShellManager.osdMessage`, shown as a status line on `OSDConfig.messageOsd`'s OSD.
- When an OSD opens, `BrightnessManager.refresh` picks up brightness changed outside axiom on the monitors its brightness bars show (every one for an `allMonitors` bar; none without a brightness bar).

### Editing
- On the section's `x-card` `views/Settings/OSDListCard`:
  - tabs, one per OSD (named by `labelOf`);
  - an edge picker with presets;
  - a Show button.
- The App field's chips come from `x-suggestions: "audioApps"` (`SettingsManager.suggestionsFor`).
