# OSD (on-screen displays)

> **Files:** `config/OSDConfig.qml`, `shell/OSD.qml`, `components/surfaces/osd/OSDContent.qml`, `components/surfaces/osd/OSDBar.qml`, `components/surfaces/osd/PipewireVolumeBar.qml`, `components/surfaces/osd/OSDTriggers.qml`, `components/views/Settings/OSDListCard.qml`
> **Config:** `OSD.*` (reader `OSDConfig`); entries are `definitions/OSDEntry`
> **Related:** [Brightness](brightness.md), [Held off an edge](../popouts/held-off-edge.md), [Edge attach](../popouts/edge-attach.md), [Popout registry](../popouts/registry.md), [Dock](dock.md)

The volume, microphone and brightness on-screen displays. Each OSD is a configurable `EdgePopout` holding one or more bars.

### Config (`OSD` section, `OSDConfig`)
- **Section keys:** `scrollToChange`, `scrollStep`, `osds` (each OSD has its own `enabled`; the section-wide one went in config v69).
  - `OSDConfig.scrollStep` is the level change per wheel notch (0–1). It is 0 when scrolling is off.
- **`osds`:** an array of `definitions/OSDEntry`. Each entry has:
  - `id`, `name`, `enabled`;
  - `monitors` / `monitor`;
  - `edge`, `position`;
  - `detached`, `gap`;
  - `orientation`, `alongEdge`;
  - `openOnHover`, `timeout`, `showPercent`;
  - `bars`.
- **Rebuilds:** `osds` is read through a JSON string (`_osdsJson`), so a reload that leaves the list unchanged doesn't rebuild the OSDs.
- **Reader helpers:**
  - `shownIds` (the enabled ones, by id);
  - `osdById(id)`;
  - `labelOf(osd)` (its tab name: its own, else its bars');
  - `excludedApps`.

### Bars
Each bar is `{ type, apps, icon, allMonitors, showOsd }`, drawn by `surfaces/osd/OSDBar`, laid out in `OSDContent`. The types:
- **`master`:** the default output's volume.
- **`other`:** the first playing stream that no App bar matches. Other apps skips the App bars of every OSD (`excludedApps`).
- **`app`:** the streams its `apps` match, by name.
- **`microphone`:** the default input's volume.
- **`brightness`:** this screen's brightness, left out when the screen has no controller. With `allMonitors` it covers every monitor at once, showing their mean (see [Brightness](brightness.md)).

**Layout** (`OSDContent`):
- vertical bars side by side;
- horizontal bars as rows;
- or, along its edge, one line parallel to it (end to end when the bars run along it too).

### Surface (`shell/OSD`)
- One `EdgePopout` per enabled OSD (`OSDConfig.shownIds`), on each screen its `monitors` puts it on (`General.screensFor(monitors, monitor)`).
- It is keyed by id, so editing an OSD's settings updates it in place instead of rebuilding every OSD.
- Placed at its `edge` / `position`. With `detached` / `gap` it is held off the edge, as a dock is (see [Held off an edge](../popouts/held-off-edge.md)).
- **Popout claim:** it uses `overNamespace: "axiom-osd"` and claims as kind `osd` (`claimKey` `osd:<id>:<screen>`), so it closes under a higher popout and won't open under one (see [Popout registry](../popouts/registry.md)).
- `keepLoaded: true`: the bars report their own changes, so they must exist while the OSD is closed.
- Hiding is the host's own hover-aware dismiss timer (`timeout`).

### What opens it (`OSDTriggers`)
- A change opens every OSD holding that bar, on the target screen (the focused one), or on all of them in "all" mode.
- `poke(force)` opens or keeps open, restarting the countdown.
- The settings page's Show button goes through `ShellManager.showOsd(id)`.
- When an OSD opens, `BrightnessManager.refresh(screen)` picks up brightness changed outside axiom.

### Editing
- On the section's `x-card` `views/Settings/OSDListCard`:
  - tabs, one per OSD;
  - an edge picker with presets;
  - a Show button.
- The App field's chips come from `x-suggestions: "audioApps"` (`SettingsManager.suggestionsFor`).
