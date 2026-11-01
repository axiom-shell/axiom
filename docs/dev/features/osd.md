# OSD (on-screen displays)

> **Files:** `config/OSDConfig.qml`, `shell/OSD.qml`, `components/surfaces/osd/OSDContent.qml`, `components/surfaces/osd/OSDBar.qml`, `components/surfaces/osd/PipewireVolumeBar.qml`, `components/surfaces/osd/OSDStatusSource.qml`, `components/surfaces/osd/OSDStatusRow.qml`, `components/surfaces/osd/OSDCard.qml`, `components/surfaces/osd/OSDMediaCard.qml`, `components/surfaces/osd/OSDStatusCard.qml`, `components/surfaces/osd/OSDTriggers.qml`, `components/methods/OSDItems.qml`, `components/views/Settings/OSDListCard.qml`
> **Config:** `OSD.*` (reader `OSDConfig`); entries are `definitions/OSDEntry`
> **Related:** [Brightness](brightness.md), [Screenshots and recording](screenshots-recording.md), [Lock keys](lock-keys.md), [Held off an edge](../popouts/held-off-edge.md), [Edge attach](../popouts/edge-attach.md), [Popout registry](../popouts/registry.md), [Dock](dock.md)

The on-screen displays: levels (volumes, microphone, brightness) as bars, the state of the machine as status icons (lock keys, the keyboard layout, the audio output and the microphone, toggles, the VPN, a recording, the camera and a screen share, messages), and the track playing. Each OSD is a configurable `EdgePopout` with its own bars, status icons and now playing card, and shows whichever changed last.

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
  - `statuses`: `row` (`notable` | `all` | `changed`), `cards` (the detail cards below; off, those changes show as their icon), `items` (the status types shown, chips with `x-enumIcons`), `quiet` (of those, the ones that don't open the OSD; `x-enumFrom: items`);
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
- **`master`:** the default output's volume; its icon is `AudioManager.outputIcon` for the device's kind, never its muted form (muted, it's struck through), as the Volume widget's.
- **`other`:** the first playing stream that no App bar matches. Other apps skips the App bars of every OSD (`excludedApps`).
- **`app`:** the streams its `apps` match, by name.
- **`microphone`:** the default input's volume.
- **`brightness`:** this screen's brightness, left out when the screen has no controller. With `allMonitors` it covers every monitor at once, showing their mean (see [Brightness](brightness.md)).
- **Default:** Other apps, then System volume.

### Status icons (`statuses`)
Each type is a tile (`OSDItems.tile(type, state)`: `{ icon, label, caption, on, slash, notable, hidden }`), drawn by `OSDStatusRow` (a tile per type it may show, built from config, shown while in `OSDItems.rowTypes`): the icon in a rounded square, filled while `on`, faint while off; the one that just changed is the accent and pops in. **One slash style:** `icon` is always the feature's base icon, never its `_off` form, and a toggle that's off (the microphone muted, on battery) is that icon struck through (`slash`, drawn by `SlashedIcon`), as a muted bar's icon is.
- **Clicks:** hovering a tile lightens it and names it and its state in a tooltip; a click flips the ones its source `canToggle` (`OSDStatusSource.toggle`: the layout to the next, muting the audio or the microphone, power saver, caffeine, do not disturb, night light, Wi-Fi, Bluetooth, airplane mode, the VPN last used up or down, and a running recording stopped: a recording's `canToggle` is a binding, true only while it runs, so `OSDContent.toggleable` is one too). A click comes while the OSD is open, so its change keeps the part shown (as any status change then does). The type clicked is `OSDContent._held`: the tile stays in the row while the OSD is open, though it turned back to ordinary; closing releases it and the highlight once the OSD has slid away (`OSDContent.hostOpen`, the host's `occupied`, turning false), so the tile stays as it goes; a quiet change with the OSD shut changes nothing. Text only where an icon can't say it: a layout's code drawn in place of the icon (`label`), and beside the row, only as one comes, a message (`caption`). A device's name is its card's (below), and its tile's tooltip (as are the VPN's and the capturing apps').
- **`capsLock`, `numLock`, `scrollLock`:** the LED (`LockKeysManager`, held while the source exists, so the LEDs are polled the whole session as with the LockKeys widget); hidden without LEDs. Num Lock on is never unusual (on on most desktops, missing on most laptops).
- **`keyboardLayout`:** its code (`KeyboardLayoutManager`, as the KeyboardLayout widget shows it); hidden with one layout, unusual past the first. A changed list of layouts is a config reload, not a switch.
- **`audio`, `microphone`:** the default output's / input's device, by its kind's icon, struck through and unusual while muted; a click mutes it. A mute shows the icons; a switch from one device to another shows the device's card (`OSDStatusCard`) instead (`fired(card)`). Hidden with no device. The device is the physical one (`AudioManager.deviceKey`: `device.id`, else the Bluetooth address, else the node), judged once the new node has bound, and the last one is kept through a gap with none: a Bluetooth headset's profile switch (A2DP ↔ headset, which replaces its nodes) is no switch. Its name (`AudioManager.deviceLabel` → `OSDItems.deviceName`): the node's nick unless a sound chip's generic one, else its description without the profile it ends with, else (a built-in chip) the kind's name; the profile ("Analog Stereo") on the card's second line.
- **`powerProfile`** (`BatteryManager.profile`; unusual off balanced), **`caffeine`**, **`dnd`**, **`nightLight`**, **`airplane`** (unusual while on), **`wifi`** (unusual while off; joining a network shows its card: the Wi-Fi device turning connected (`wifiDevice.connected`, steadier than the scanned list, which can drop the network joined for a moment), the network's name and signal filling in as the list catches up; another network is reached through disconnected, so it's a card too), **`bluetooth`** (never), **`charger`** (`BatteryManager.onBattery`; unusual on battery; plugging in shows its card: the level, Charging / Fully charged / Plugged in, and the time to full).
- **`vpn`:** whether a VPN is up (`VpnManager.anyActive`; one coming up shows its card, a drop the struck-through icon; Tailscale is one of its rows, so the source `acquire`s VpnManager, which polls Tailscale while held: [the issue](../issues.md#tailscales-state-is-polled-where-it-could-be-pushed)); unusual while up, hidden with no VPN. Unlike the toggles, every change shows, the user's or not (a drop, an autoconnect): `OSDItems.vpnStep` keeps each VPN's last settled state, so up and down are judged across `connecting` / `disconnecting`, and a row appearing (Tailscale's first status) isn't one.
- **`drive`:** removable drives (`DrivesManager`: `count`, and `lastEvent`, set only by a real plug-in, a mount from the shell or an eject, never by a drive there at login). Each event shows its card: the drive's name, Connected, Mounted (the mount point as its detail) or Safe to remove (after an eject, the icon `eject`). Never unusual; hidden with no drive (or no udisks2), so a drive ejected and gone still shows as it changes. Not in the default list ([Drives](drives.md)).
- **`recording`** (`ScreenshotManager.recording`; unusual while on, hidden with no recorder): a click stops it.
- **`camera`, `micUse`, `screenShare`:** the apps using a camera / a microphone / sharing the screen (`PrivacyManager.cameraCaptures` / `AudioManager.micCaptures` / `PrivacyManager.screenCaptures`, also the Privacy widget's; axiom's own recording isn't a share, it's `recording`; an app opening the camera's device itself isn't seen: [the issue](../issues.md#an-app-reading-the-camera-through-v4l2-never-shows-as-using-it); video comes from a `Video/Source` or a program's `Stream/Output/Video` (niri makes its screencast one, which Quickshell gives no type: PrivacyManager also tracks links between two Untracked nodes and reads their media class once bound), into an app's `Stream/Input/Video`; a camera is a source backed by a device (`device.api` v4l2 or libcamera), any other one a share); unusual while on, never hidden, no click. A stream starting shows its card (`OSDItems.captureChange` "started", judged by node id: an app's name read after its stream starts isn't another app), the last one stopping the struck-through icon, one of several stopping nothing. One app on the camera and the microphone at once (a call) is one card, "Using the camera and microphone", whichever came first (`OSDItems.card`; `replaces` keeps it against the other's card from the same app). A capture that stops while its card shows (a picker's preview: Electron apps such as Vesktop open the portal and stream a thumbnail before their own picker, then stop it) keeps naming the apps (`OSDStatusSource._lastApps`, the tile's `last`) with "Stopped sharing the screen" (or the camera's, the microphone's), not an empty title.
- **`message`:** marks the OSD `axiom ipc osd message <icon> <text>` goes to; a message shows as its icon and text, only as it comes, and opens the OSD unless `message` is in `quiet`.
- **Which show** (`OSDItems.rowTypes`, by `row`): `notable` the unusual ones, `all` every one not hidden, `changed` none; the one that just changed always, in its place.
- **Default:** Caps Lock, Num Lock, the keyboard layout, the microphone and audio, `notable`. (v87 turned v86's `micMute` and `inputDevice` into `microphone`, `outputDevice` into `audio`.)

### Now playing (`media`)
The card (`OSDMediaCard`: the cover, title, artist, playing or paused), on a new track (`onTrackChange`) and optionally on play and pause (`onPlayPause`). Off by default.

### What shows (`OSDContent`)
- **One part at a time**, whichever changed last (`shown`):
  - `level` (a bar changed): the bars, with the status icons `row` picks beside them (after them, along the edge's other axis);
  - `status` (a status changed): the status icons alone, the change highlighted (`changed`). Not while the OSD is already open on its bars (`hostOpen`): they stay, the change highlighted in their row, so its shape never changes under the cursor;
  - `card` (a change of one of `OSDItems.cardTypes` that has its card: `audio` or `microphone` switched device, a VPN came up, an app started using the camera or sharing the screen, the charger was plugged in, Wi-Fi joined a network, a drive was plugged in, mounted or ejected): its status's card (`OSDStatusCard`, showing `OSDItems.card`: the status's icon, a title, what happened and a detail; a device's name, what it's now used for ("Output and input" when both device statuses hold the same device) and its profile; a VPN's name, Connected and its address; the apps and what they started; the battery's level, its state and the time to full; a network's name, Connected and its signal). Its role is English from the helper, translated by `OSDContent.cardContent`. Not while open on the bars, as for `status`. The card keeps its status (`_cardType`) as the OSD closes;
  - `media`: the now playing card.
  - Both cards (the status card, the now playing card) are `OSDCard`s (a square picture, a title, a faint line, an optional status icon).
  - With none changed yet, the bars, else the status icons, else the card.
- **Bars' layout:** vertical bars side by side; horizontal bars as rows; or, along its edge, one line parallel to it (end to end when the bars run along it too).
- **Knock-on changes keep the highlight** (`OSDItems.replaces`, within `OSDItems.quietWindow`): Wi-Fi or Bluetooth switching just after airplane mode is its own doing; the output and the input switching to the same device together (a headset connecting) are one change, the first one's card; a mute just after a device switch is the new device's own state coming in (`sourceSettled` can't always tell: the mute may arrive after the node binds), so the card stays; and any card stays against its own status changing again without one (the other half of a VPN switch, a capture stopping as it starts), unless a VPN, Wi-Fi or the charger turned off (the card would say Connected or Plugged in), and the camera's and microphone's cards from one app are one. `OSDContent._changedCard` says whether the highlight showed a card.
- **Its size:** each part's own; the host keeps room for the deepest across its edge (`maxDepth`: the bars and icons together, the icons alone, the card; → `EdgePopout.maxContentDepth`), the status card with a status that has one, the icons counted at their largest (`OSDStatusRow.maxDepth`: a tile, along a left or right edge a caption's width when the OSD shows messages), so it isn't resized as it swaps or as icons come and go.
- **Sources** (`OSDStatusSource`, one per status type and one for the card): a Loader building only its type's watcher, so an OSD without a type never wakes its service. Its `tile` follows the state (read only from its own type's service), and `fired` reports the user's changes (anyone's for the VPN, the camera and a screen share), never a first reading or a device appearing (each type's own guard; the system volume and microphone bars and the audio and microphone statuses count a level or mute change only while `AudioManager.sinkSettled()` / `sourceSettled()`: the default device unchanged and bound since before it and still bound, so a device switching, appearing, binding or going away (Quickshell unreadies a removed node, then clears its volumes to 0 while it's still the default), or a Bluetooth profile switch, isn't the user), and nothing for its first 1.5 s while services settle. Lock key, layout, VPN and capture changes are judged by `OSDItems.lockKeyChanged` / `layoutSwitched` / `vpnStep` / `captureChange`. A change opens the OSD unless its type is in `quiet`. The Repeater's model is `_watchKey` (the types as a string), so an edit to any OSD doesn't rebuild the watchers.

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
- The settings page's Show button (and `axiom ipc osd show <id>`) goes through `ShellManager.showOsd(id)`: the OSD opens on its bars, else on its status icons as they are (every one when none would show, `OSDContent._previewAll`, until it closes), else the card (`OSDContent.preview`).
- `axiom ipc osd message <icon> <text>` / `messageTo <id> <icon> <text>`: `ShellManager.osdMessage`, shown as a status icon and its text on `OSDConfig.messageOsd`'s OSD.
- When an OSD opens, `BrightnessManager.refresh` picks up brightness changed outside axiom on the monitors its brightness bars show (every one for an `allMonitors` bar; none without a brightness bar).

### Editing
- On the section's `x-card` `views/Settings/OSDListCard`:
  - tabs, one per OSD (named by `labelOf`);
  - an edge picker with presets;
  - a Show button;
  - its `sections`, each folding (`EntryListCard`): Status icons (the row's mode, then the status types as a grid of icon chips, then which of them stay quiet), Now playing, then the other settings ("Place and timing"), and Bars last (`lastSections`): their layout and list.
- The App field's chips come from `x-suggestions: "audioApps"` (`SettingsManager.suggestionsFor`).
