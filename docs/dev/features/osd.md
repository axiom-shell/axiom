# OSD (on-screen displays)

> **Files:** `qml/config/OSDConfig.qml`, `qml/shell/OSD.qml`, `qml/components/surfaces/osd/OSDHost.qml`, `qml/components/surfaces/osd/OSDTriggers.qml`, `qml/components/surfaces/osd/design/`, `qml/components/views/Settings/OSDListCard.qml`, `qml/components/methods/OSDEngine.qml`, `qml/components/methods/OSDParts.qml`, `qml/components/surfaces/osd/engine/OSDSystem.qml`, `qml/components/surfaces/osd/engine/OSDWatch.qml`, `qml/components/surfaces/osd/engine/OSDSystemHost.qml`, `qml/components/surfaces/osd/systems/`, `qml/config/schema/definitions/kinds/OSDSystemBase.yaml`, `tests/tst_OSDSystems.qml`, `tests/osd/`
> **Config:** `OSD.*` (reader `OSDConfig`); entries are `definitions/OSDEntry`
> **Related:** [Brightness](brightness.md), [Screenshots and recording](screenshots-recording.md), [Lock keys](lock-keys.md), [Held off an edge](../popouts/held-off-edge.md), [Edge attach](../popouts/edge-attach.md), [Popout registry](../popouts/registry.md), [Dock](dock.md)

The on-screen displays: levels (volumes, microphone, brightness) as bars, the state of the machine as status icons (lock keys, the keyboard layout, the audio output and the microphone, toggles, the VPN, a recording, the camera and a screen share, messages), and the track playing. Each OSD is a configurable `EdgePopout` with its own bars, status icons and now playing card, and shows whichever changed last.

### Config (`OSD` section, `OSDConfig`)
- **Section keys:** `scrollToChange`, `scrollStep`, `onScreenChanges` (see What opens it), `cardsToHistory` (see Status icons › Where events go), `items` (the OSDs; each has its own `enabled`; the section-wide one went in config v69).
  - `OSDConfig.scrollStep` is the level change per wheel notch (0–1). It is 0 when scrolling is off.
- **Each OSD** (`definitions/OSDEntry`):
  - `id`, `name`, `enabled`;
  - `screen` (monitors);
  - `edge`, `position`;
  - `detached`, `distance`, `animation` (Slide or Fade);
  - `openOnHover`, `timeout`;
  - `openTogether` (off by default), `iconsPlace` (`outside` | `inside`), `holdStill` (see What shows);
  - `barLayout`: `orientation`, `alongEdge` (its `x-showIf` reads the entry's `edge` through `../`), `showPercent`;
  - `row` (`notable` | `all` | `changed`: which icons show);
  - `cardsEnabled` (off: no card at all; the icons' changes show as their icon, and a drive, low battery, monitor, screenshot or message is a notification instead), `cardTimeout` (how long a card stays out);
  - `systems`: what it shows, in order (the icons' and the bars' order), each an `OSDSystem` item (Engine › A system's folder): `{ type, tile, card, quiet, …its own settings }`. Audio's `bars` (`master` / `other` / `app` / `microphone`, each with `apps`, `icon`, `showOsd`) and `tiles` (`audio`, `microphone`); Brightness's `allMonitors`, `icon`, `showOsd`; LockKeys' `keys`; Privacy's `kinds`; Battery's `tiles`; Media's `onTrackChange` / `onPlayPause`. Default: Audio, LockKeys, KeyboardLayout, Dnd, Caffeine, NightLight, Recording, Drives, Message (the entry's `systems` default).
  - Until config v86 the bars were `bars`; v86 made them one `items` list with the statuses and media, and v87 split that into `bars`, `statuses` and `media` (a status's own icon went: its icon is what it shows; lock keys became one type per key; an OSD whose items were the default only has its layout keys moved under `bars`). v91 gave the cards their own object: `statuses.cards` / `cardTimeout` became `cards.enabled` / `timeout`, the card-only types moved from `statuses.items` to `cards.items` (a quiet one dropped: it was a notification already), `media.enabled` became `media` in that list with its two options, and messages, which went to the first OSD whether it listed them or not, stay on the OSDs listing them, else the first enabled one gets them (unless quiet there). v101 made the three one ordered list, `systems` (`v101.go`'s comment has the mapping: each system once, where its first type was, the bars' first; an item quiet only when every key it took was), with `barLayout`, `row`, `cardsEnabled` and `cardTimeout` beside it.
- **Rebuilds:** the OSDs are read through a JSON string (`_osdsJson`), so a reload that leaves the list unchanged doesn't rebuild them.
- **Reader helpers:**
  - `shownIds` (the enabled ones, by id);
  - `osdById(id)`;
  - `labelOf(osd)` (its tab name: its own, else its bars', else its systems' with icons, else Now playing), `nameOf(type)` (a system's label, from the `OSDSystem` kind's `oneOf`);
  - `excludedApps`;
  - `messageOsd(id)` (where `axiom message` goes as a card: the OSD of that id, else (`id` "") the first, of those showing Messages (`OSDEngine.opensCard`); "" with none, so it's a notification);
  - `routeOf(type, notify)` (where its event goes: "osd", "notification" or ""; `OSDEngine.cardRoute` by the event type's system: `drive` Drives, `battery` Battery (only where its `tiles` hold `battery`), `monitor` Monitors, `screenshot` Screenshot, `bluetooth` Bluetooth), `cardsToHistory`.

### Bars (`bars.items`)
Each is `{ type, icon, showOsd, … }`; `icon` empty follows what it shows (the un-muted icon: muted, it's struck through), `showOsd` off lists it without opening the OSD (a change still shows on, and keeps open, an open one). A volume or microphone bar's icon mutes it on a click (`StyledVolumeBar.iconClickable`; an app's bar mutes the streams it matches). Drawn by `OSDBar`:
- **`master`:** the default output's volume; its icon is `AudioManager.outputIcon` for the device's kind, never its muted form (muted, it's struck through), as the Volume widget's.
- **`other`:** the first playing stream that no App bar matches. Other apps skips the App bars of every OSD (`excludedApps`).
- **`app`:** the streams its `apps` match, by name.
- **`microphone`:** the default input's volume.
- **`brightness`:** this screen's brightness, left out when the screen has no controller. With `allMonitors` it covers every monitor at once, showing their mean (see [Brightness](brightness.md)).
- **Default:** Other apps, then System volume.

### Status icons (`statuses`)
Each type is a tile (`OSDItems.tile(type, state)`: `{ icon, label, tone, on, slash, notable, hidden }`), drawn by `OSDStatusRow` (a tile per type it may show, built from config, shown while in `OSDItems.rowTypes`): the icon in a rounded square, **on the accent while `on`**, faint and unfilled while off; the one that just changed is ringed and pops in, the ring fading in and out: the foreground with a gap in the background inside it, so it reads on the accent fill too (`borderFocus` is the accent in most themes). The fill glides between on and off in the accent's own colour (off is the accent at alpha 0, so the glide changes no hue). `icon` is always the feature's base icon, never its `_off` form: off is told by the fill alone, and only a mute (audio, microphone) is also struck through (`slash`, drawn by `SlashedIcon`), as a muted bar's icon is, since a plain speaker doesn't read as muted.
- **Clicks:** hovering a tile lays the ink faintly over it, at once (a layer, not the fill: an eased fill left tiles easing back behind the pointer, and lightening barely shows on a pale accent; a slash's cutout follows it on a lit tile) and names it and its state in a tooltip; a click flips the ones whose system names an action (`OSDSystemHost.actionOf`; `OSDHost.toggle` marks the tile's `mark` and runs it, as its key would ([Actions](../core/actions.md)): the layout to the next, muting the audio or the microphone, power saver, caffeine, do not disturb, night light, Wi-Fi, Bluetooth, airplane mode, the VPN last used up or down, and a running recording stopped: a recording's action is there only while it runs, so `OSDHost.toggleable` is a binding). A click comes while the OSD is open, so its change keeps the part shown (as any status change then does). A clicked tile stays in the row though it turned back to ordinary, as every tile shown does (`OSDHost._kept`, below); a quiet change with the OSD shut changes nothing. Text only where an icon can't say it: a layout's code drawn in place of the icon (`label`). A device's name is its card's (below), and its tile's tooltip (as are the VPN's and the capturing apps').
- **`capsLock`, `numLock`, `scrollLock`:** the LED (`LockKeysManager`, held while the source exists, so the LEDs are polled the whole session as with the LockKeys widget); hidden without LEDs. Unusual while on, Num Lock too.
- **`keyboardLayout`:** the input source in use, by its label and its kind's icon (`InputSourceManager`, as the KeyboardLayout widget shows them: a layout's code, an input method's own あ), so an input method's switch shows it too; hidden with one source, unusual past the first. A changed list of sources is a config reload, not a switch; a change within `OSDItems.focusFollowMs` of the focused window changing (`CompositorManager.activeWindowId`) is that window's own input method coming back (fcitx5 keeps one per window with `shareState` off), unless axiom switched in that time too (`InputSourceManager.switchedAt`). fcitx5's own switch popup is off while `Input.keyboard.method.showSwitchPopup` is ([input sources](input-sources.md)).
- **`audio`, `microphone`:** the default output's / input's device, by its kind's icon, struck through and unusual while muted; a click mutes it. A mute shows the icons; a switch from one device to another shows the device's card (`OSDStatusCard`) instead (`fired(card)`). Hidden with no device. The device is the physical one (`AudioManager.deviceKey`: `device.id`, else the Bluetooth address, else the node), judged once the new node has bound, and the last one is kept through a gap with none: a Bluetooth headset's profile switch (A2DP ↔ headset, which replaces its nodes) is no switch. Its name (`AudioManager.deviceLabel` → `OSDItems.deviceName`): the node's nick unless a sound chip's generic one, else its description without the profile it ends with, else (a built-in chip) the kind's name; the profile ("Analog Stereo") on the card's second line.
- **`powerProfile`** (`BatteryManager.profile`; unusual off balanced), **`caffeine`**, **`dnd`**, **`nightLight`**, **`airplane`** (unusual while on), **`wifi`** (unusual while off; joining a network shows its card: the Wi-Fi device turning connected (`wifiDevice.connected`, steadier than the scanned list, which can drop the network joined for a moment), the network's name and signal filling in as the list catches up; another network is reached through disconnected, so it's a card too), **`bluetooth`** (never), **`charger`** (`BatteryManager.onBattery`; unusual on battery; plugging in shows its card: the level, Charging / Fully charged / Plugged in, and the time to full).
- **`vpn`:** whether a VPN is up (`VpnManager.anyActive`; one coming up shows its card, a drop the unlit icon; Tailscale is one of its rows, so the source `acquire`s VpnManager, which polls Tailscale while held: [the issue](../issues.md#tailscales-state-is-polled-where-it-could-be-pushed)); unusual while up, hidden with no VPN. Unlike the toggles, every change shows, the user's or not (a drop, an autoconnect): `OSDItems.vpnStep` keeps each VPN's last settled state, so up and down are judged across `connecting` / `disconnecting`, and a row appearing (Tailscale's first status) isn't one.
- **`drive`:** removable drives (`DrivesManager`: `count`, and `lastEvent`, set by what happens to a drive, a mount by a file manager too, never by a drive there at login). Each event shows its card (`OSDItems._driveCards`): the drive's name, and Connected, Locked (`lock`), Mounted (the mount point as its detail), Unmounted, Safe to remove (`eject`), Disconnected (`usb_off`), Unplugged without ejecting, In use, or Couldn't eject. Set only while an OSD lists it, which takes those events from notifications (Where events go; [Drives](drives.md) › Who says what). Its card takes a click (`OSDItems.clickableCards`, run by the source's `activate`): `DrivesManager.activate` opens the drive, asks for its passphrase, or shows the Drives module. Unusual while a drive is plugged in; hidden with no drive (or no udisks2), so a drive ejected and gone still shows as it changes. In the default list.
- **`battery`:** the battery dropping to low, then to critical (`BatteryManager.levelEvent`, set by `_sayLevel` as `level` turns `low` / `critical` at `Battery.lowThreshold` / `criticalThreshold`, once settled, never at the start): its card, the level, Battery low or Battery critically low, and the time left; critical's on the warning colour (`tone: "warning"`). The tile is lit and unusual while low or critical (`battery_low`, `battery_alert` when critical, else `battery_full` unlit); hidden with no battery. A critical battery also sends an urgent notification beside its card (`NotificationManager.announce`: `urgency` `critical`), unless `Battery.notify` is off.
- **`monitor`** (picked under `cards`): a monitor connected or removed (`MonitorManager.lastEvent`, from comparing its reads of `CompositorManager.withOutputDetails` by connector, disabled ones included, so turning one off isn't unplugging it; never what's there at the start; needs `supports.monitors`): its card, its description (else its connector), Connected or Disconnected (`desktop_access_disabled`), and the connector and resolution. Only ever its card (the tile is always hidden: it shows as it changes).
- **`screenshot`** (picked under `cards`): a screenshot taken (`ScreenshotManager.lastShot`, from `_sayTaken`; not one opened in the annotator, nor one taken for a caller): its card, the picture in place of the icon (`OSDItems.card`'s `image`, drawn by `OSDStatusCard` cropped, decoded at its size), Screenshot saved, Copied to the clipboard and the folder. Its card takes a click: `ScreenshotManager.open` opens the picture. Only ever its card. Recordings are `recording`.
- **`recording`** (`ScreenshotManager.recording`; unusual while on, hidden with no recorder): a click stops it.
- **`camera`, `micUse`, `screenShare`:** the apps using a camera / a microphone / sharing the screen (`PrivacyManager.cameraCaptures` / `AudioManager.micCaptures` / `PrivacyManager.screenCaptures`, also the Privacy widget's; axiom's own recording isn't a share, it's `recording`; a camera's also lists the apps holding its device open themselves, which PipeWire never sees (Chromium and Electron apps such as Vesktop read `/dev/video*` through V4L2): the daemon's `camera.state` (`backend/internal/camera`: inotify on the devices, and on `/dev` for one coming, going or getting its access, which a camera plugged in gets from udev only after it appears; then who holds one open in `/proc`, PipeWire and WirePlumber left out, an app's processes counted once by its flatpak id or else its process name), each one shaped as a node with the id `device:<key>` and its desktop entry's name; video comes from a `Video/Source` or a program's `Stream/Output/Video` (niri makes its screencast one, which Quickshell gives no type: PrivacyManager also tracks links between two Untracked nodes and reads their media class once bound), into an app's `Stream/Input/Video`; a camera is a source backed by a device (`device.api` v4l2 or libcamera), any other one a share); unusual while on, never hidden, no click. A stream starting shows its card (`OSDItems.captureChange` "started", judged by node id: an app's name read after its stream starts isn't another app), the last one stopping the unlit icon, one of several stopping nothing. One app on the camera and the microphone at once (a call) is one card, "Using the camera and microphone", whichever came first (`OSDItems.card`; `replaces` keeps it against the other's card from the same app). A capture that stops while its card shows (a picker's preview: Electron apps such as Vesktop open the portal and stream a thumbnail before their own picker, then stop it) keeps naming the apps (`OSDStatusSource._lastApps`, the tile's `last`) with "Stopped sharing the screen" (or the camera's, the microphone's), not an empty title.
- **`message`** (picked under `cards`): what `axiom message <icon> <text>` and `ShellManager.refuse` send, as a card (`OSDItems.card`: its icon, the text as the title, `detail` as the faint line, the picture on `Theme.warning` for a refusal, `tone: "warning"`), only as it comes, on the OSD `OSDConfig.messageOsd` picks: one with its cards on that picks Messages. With none `ShellManager` sends it as a notification instead, refusals too (a refusal's isn't kept: `transient`). It has no source (`ShellManager.osdMessage` brings it), shows beside whatever else is out, and gives way within `quietWindow` only to another card, so its text gets read.
- **Where events go** (`OSDConfig.routeOf(type, notify)`, applied by `NotificationManager.announce`): an event of `drive`, `battery`, `monitor` or `screenshot` shows as its card on the OSDs that open it (`OSDEngine.cardRoute` / `opensCard`: an enabled OSD with `cardsEnabled`, listing the event's system (Drives, Battery with `battery` in its `tiles`, Monitors, Screenshot) with its `card` on and not `quiet`); with none (a quiet one never opens the OSD, and with its cards off there is no card) it's a notification, as without the OSD, unless its section's switch is off (`Drives.notify`, `Battery.notify`, `Monitors.notify` (off by default), `Screenshots.notify`), with the buttons it always had (a screenshot's Edit in …, a mount's Open / Eject); else nothing. A critical battery notifies beside its card too. Each service sets its event (`lastEvent`, `levelEvent`, `lastShot`) only when the route is the OSD.
- **`OSD.cardsToHistory`** (default on): an event card shown on an OSD (a drive, the battery, a monitor, a screenshot, a message, not a refusal) is also filed in the notification history's Quiet section: `sendNotification`'s `silent`, which puts an entry straight there (`NotificationManager._file`: no toast, not counted on the badge, its buttons run by its desktop entry's handler, a path icon its picture; [Notifications](notifications.md) › Levels), one per key (a drive's, a monitor's, the last screenshot's). Device switches, the VPN, Wi-Fi, the charger and capture cards stay transient.
- **Which show** (`OSDItems.rowTypes`, by `row`): `notable` the unusual ones, `all` every one not hidden, `changed` none; plus `kept`, always, in its place: the one that just changed and **every one the row has shown since the icons came out** (`OSDContent._kept`, gathered by `_keepRow` as the icons open and as a change rings, in every mode; emptied as they fold back or the OSD closes). So a tile that turns ordinary stays until the icons go: Caps Lock off, then Num Lock off, shows both, unlit, with `changed` too (each change joins the ones before it).
- **Unusual** (`notable`, from `OSDItems.tile`):

  | Status | Unusual while |
  |---|---|
  | `capsLock`, `numLock`, `scrollLock` | on |
  | `keyboardLayout` | past the first input source |
  | `audio`, `microphone` | muted |
  | `powerProfile` | power saver or performance |
  | `caffeine`, `dnd`, `nightLight`, `airplane`, `recording` | on |
  | `wifi` | off |
  | `bluetooth` | never |
  | `vpn` | a VPN up |
  | `drive` | a drive plugged in |
  | `charger` | on battery |
  | `battery` | low or critical |
  | `camera`, `micUse`, `screenShare` | an app using it |
  | `monitor`, `screenshot`, `message` | never (only ever a card) |
- **Default:** Caps Lock, Num Lock, the keyboard layout, the microphone and audio, do not disturb, caffeine, night light, screen recording, removable drives, `notable`. (v87 turned v86's `micMute` and `inputDevice` into `microphone`, `outputDevice` into `audio`.)

### Now playing (`media` in `cards.items`)
The card (`OSDMediaCard`: the cover, title, artist, playing or paused), on a new track (`cards.onTrackChange`) and optionally on play and pause (`cards.onPlayPause`), while the OSD's cards are on. Not picked by default.

### What shows (`OSDContent`)
- **Three parts, each shown for its own change and on its own time** (`OSDItems.parts`):
  - `level` (a bar changed): the bars alone;
  - `status` (a status changed without a card): the status icons `row` picks, the change ringed (`changed`);
  - `card`: a status's card (a change of one of `OSDItems.cardTypes` that has its card: `audio` or `microphone` switched device, a VPN came up, an app started using the camera or sharing the screen, the charger was plugged in, Wi-Fi joined a network, something done to a drive, the battery dropped to low or critical, a monitor came or went, a screenshot was taken, a message came), or the now playing card (`_cardKind`). A status's card (`OSDStatusCard`, showing `OSDItems.card`: the status's icon, a title, what happened and a detail; a device's name, what it's now used for ("Output and input" when both device statuses hold the same device) and its profile; a VPN's name, Connected and its address; the apps and what they started; the battery's level, its state and the time to full; a network's name, Connected and its signal; its role English from the helper, translated by `OSDContent.cardContent`) shows **alone**: the change's icon turns lit quietly, ringed only if the icons happen to be out. The card keeps its status (`_cardType`) as it folds back and the OSD closes.
  - Both cards are `OSDCard`s (a square picture, a title, a faint line, an optional status icon), sized to their text: the longer line's width, at least 160 and at most 400 px (`minTextWidth` / `maxTextWidth`, scaled). Past it the title (one line) ends in "…" and the faint line wraps, up to three lines (`subtitleLines`, the last elided), the card growing taller as it does (at least 64 px, scaled, with one line); its slot and the box read its height as it is, and the window keeps room for it at its largest (`OSDCard.maxShown`: its widest beside a side edge, else three faint lines, in `OSDContent.maxDepth`).
  - **Opened with nothing out** (its hover strip) and the Show button bring out the bars and the icons (`_expose`; every icon when none would show, `_previewAll`, until they close); with neither, the now playing card. Never a status's card. The pointer moving onto an OSD already open (catching a change, a card) brings out nothing new: it only holds what's there.
- **Stacked out from the edge, in one box** (`_order`, `OSDItems.partOrder`): the bars nearest the edge and the icons past them (`iconsPlace` `outside`, the default; `inside` puts the icons by the edge), the card always last; with `holdStill` and the pointer on the OSD, it goes after the other instead (still inside the card), so nothing under the pointer moves, and that order stays while both are out (a card under the pointer still moves out as the bars or icons come in: rare, left so). **`openTogether`** (default off): a change to a bar or an icon brings out both (`_boxParts`, where the OSD has both; the icons with none to show show every one, `_previewAll`, as `_expose` does); off, only the one that changed. A part slides out from under the one before (its `_*Reveal`, eased over `animNormal`, a slot clipped to it); one opening on a shut OSD is simply there as it slides in (`_snapping`, set before the order changes, since the eased length reads it).
- **One box, as long as its longest part,** attached or held off the edge alike: a card shorter than the bars runs as long as them (centred in its slot), a longer one makes the box as long as it. The length eases (`_lengthEased`, toward `_lengthTarget`: the longest open part, a folding one giving its room up as it goes; closing, every one still out; over `animNormal`): the box's ends run out to meet a longer part as it slides out and back as it folds, and a part's own length changing while shown (an icon joining the row, a card's text) eases too. Contents are centred on whole pixels (`_farX` / `_farY`), as `EdgePopout.aligned` is, else a half pixel flipping as the length eased shimmered them.
- **Times:** the bars and the icons `timeout`, the card `cards.timeout` (`_deadlines`, one Timer). **Shared** (`OSDItems.sharedDeadlines`): the bars and the icons, while both are out, take the later of theirs, so they close together; the card keeps its own, neither holding them nor held by them (it says what happened once), so with the pointer away they fold back without it, or it without them. Times within `grace` (750 ms) of each other end together (`OSDItems.partsDue`). The pointer on the OSD holds the bars and the icons; the card only while it's on the card itself (`cardHovered`, a `HoverHandler` on each card): pointing at the bars, a card still folds at its time. Let go, a held part gets its time anew (`_renew`). When the last ones go together (`_close`), the OSD slides away whole (`collapse`). While a part is out the content's `hovered` holds the host's own countdown.
- **Changes during a close** (`_closing`, from the time being up until the host has slid away): anything coming in waits (`_queued` → `_pending`) and comes in once the OSD is gone, the OSD opening again for it (a quiet one is dropped; the host itself reopens only after closing).
- **Bars' layout:** vertical bars side by side; horizontal bars as rows; or, along its edge, one line parallel to it (end to end when the bars run along it too).
- **Knock-on changes** (within `OSDItems.quietWindow`): against the ring (`OSDItems.replaces`), Wi-Fi or Bluetooth switching just after airplane mode is its own doing. Against a card out, another card swaps in unless it's the same change (`replaces`: the output and the input switching to the same device together, a headset connecting, are one change, the first one's card; the camera's and microphone's cards from one app are one), and a change without one (`OSDItems.besideCard`) shows nothing when it's the card's own knock-on (a mute just after a device switch, the new device's own state coming in, which `sourceSettled` can't always tell; the other half of a VPN switch; a capture stopping as it starts), folds the card back when it would say what no longer holds (a VPN, Wi-Fi or the charger turned off), and else shows on the icons beside the card.
- **Its size:** each part's own as far as it's out, gaps between (`gap`: the host's padding inside its stroke, `contentPadding` less the border, so parts are as far apart as the outer ones are from the outline, and the nearest from the screen edge, which `EdgePopout.attachExtra` keeps the same; measured between what shows: a part's own empty margin, `_inset` (a card's round its picture, `OSDCard.inset`; not a bar's, whose margin holds its muted highlight: run on into the gap it sat cramped), runs on into the gap or the padding instead of adding to it); the host keeps room for every part out at once across its edge (`maxDepth`: the bars, the icons at their largest (`OSDStatusRow.maxDepth`: a tile), the deeper card it may show at its largest (`OSDCard.maxShown`: beside a side edge its widest, else its faint line wrapped to three lines, so its text changing never resizes the window), and the gaps; → `EdgePopout.maxContentDepth`), so its window isn't resized as parts come and go: the host sizes its window from `AttachedSurface.depthFor(maxContentDepth + padding)`, the surface's depth at its largest (or the surface's own, should it be deeper), never from the surface's depth less the content's (two bindings a pass apart as a part eases: they wobbled a few pixels a frame, each wobble resizing the layer window, a stutter on a 240 Hz monitor). Along the edge it's the longest part's, as far as it's out (`_lengthNow`). The hover strip's `triggerLength` is the open parts' full length (`_lengthTarget`), not the eased one, so its window resizes once per part, not every frame. **Whole pixels:** each part's depth, its gap and `_lengthNow` are rounded (`_layout`), and the host's window depth is ceil'd: a fraction left the content a pixel off its outline, and a bottom or right OSD's window flipping a pixel taller and back moved everything in it.
- **Sources** (`OSDStatusSource`, one per status type and one for the card): a Loader building only its type's watcher, so an OSD without a type never wakes its service. Its `tile` follows the state (read only from its own type's service), and `fired` reports the user's changes (anyone's for the VPN, the camera and a screen share), never a first reading or a device appearing (each type's own guard; the system volume and microphone bars and the audio and microphone statuses count a level or mute change only while `AudioManager.sinkSettled()` / `sourceSettled()`: the default device unchanged and bound since before it and still bound, so a device switching, appearing, binding or going away (Quickshell unreadies a removed node, then clears its volumes to 0 while it's still the default), or a Bluetooth profile switch, isn't the user), and nothing for its first 1.5 s while services settle. Lock key, layout, VPN and capture changes are judged by `OSDItems.lockKeyChanged` / `layoutSwitched` / `vpnStep` / `captureChange`. A change opens the OSD unless its type is in `quiet`. The Repeater's model is `_watchKey` (the types as a string), so an edit to any OSD doesn't rebuild the watchers.

### Surface (`qml/shell/OSD`)
- One `EdgePopout` per enabled OSD (`OSDConfig.shownIds`), on each screen its `monitors` puts it on (`General.screensFor(monitors, monitor)`).
- It is keyed by id, so editing an OSD's settings updates it in place instead of rebuilding every OSD.
- Placed at its `edge` / `position`. With `detached` it is held off the edge, `distance` across the free screen, sliding or fading in (`animation`), as a dock is (see [Held off an edge](../popouts/held-off-edge.md)).
- **Popout claim:** it uses `overNamespace: "axiom-osd"` and claims as kind `osd` (`claimKey` `osd:<id>:<screen>`), so it closes under a higher popout and won't open under one (see [Popout registry](../popouts/registry.md)).
- `keepLoaded: true`: the items report their own changes, so they must exist while the OSD is closed.
- Hiding: the parts' own times (`OSDContent`'s `collapse` → `hide()`, see What shows › Times); the host's own countdown (`timeout`) only runs while nothing is out (opened from its hover strip with nothing to show).

### What opens it (`OSDTriggers`)
- A change opens every OSD holding that item, on the target screen (the focused one), or on all of them in "all" mode. The same item in two OSDs opens both.
- `poke(force)` opens or keeps open, restarting the countdown.
- **Changes made on screen don't open it** (unless `OSD.onScreenChanges`): the UI marks a change right before it calls the setter (`ShellManager.onScreen(kind)`, most through `ActionsManager.run(id, {fromScreen: true})` and its `osdKind` ([Actions](../core/actions.md)): the Volume and Microphone widgets, the Bluetooth, Notifications, Vpn, IdleInhibitor, KeyboardLayout, ScreenRecord and Button widgets, the AudioMixer, VolumeDials, Brightness, QuickActions, NightLightControls, Caffeine, WifiNetworks and BluetoothDevices modules, `VpnRow`, `NotificationHeader`, the night light settings card), and `OSDContent.opensFor(type)` turns a change of that kind within its window into a `force` false one: it updates an open OSD, never opens a shut one. Kinds and windows are `OSDItems.onScreenKind` / `onScreenWindow` (`audio` for every output level and the output device, `microphone`, `brightness`, else the status type; 2 s, longer for a connection settling: 8 s for Wi-Fi, Bluetooth and airplane mode, 15 s for a VPN). Never a service: keys come in through IPC and automation (idle, schedules) calls the setters too, and both must still open it. Launcher commands aren't marked (typed, and the launcher closes).
- The settings page's Show button (and `axiom ipc osd show <id>`) goes through `ShellManager.showOsd(id)`: the OSD opens on its bars and its status icons as they are (every one when none would show, `OSDContent._previewAll`, until they close), else the now playing card (`OSDContent.preview`).
- `axiom message [--detail <text>] [--osd <id>] <icon> <text>` (`backend/internal/cli/message.go`) calls the `osd` target's `message(id, icon, text, detail)` with all four, `""` for a flag not given (IPC functions take no optional arguments; the CLI is the documented way in, the IPC function its plumbing): `ShellManager.osdMessage`, shown as a message card on `OSDConfig.messageOsd`'s OSD.
- `_message` files it in the notification history's Quiet section with `OSD.cardsToHistory` (a refusal isn't filed), and sends a notification instead where no OSD picks Messages (`messageOsd` ""); `ShellManager.confirm(icon, title, detail)` is an answer to something just done (the calendar's "Added …"), never filed, a toast that isn't kept where no OSD picks Messages; `ShellManager.refuse(icon, title, detail)` sends it as a refusal (`tone: "warning"`: the card's picture on the warning colour, the icon the base one of what was refused, the title what, the detail why: "Night light" / "Not available here"). An IPC action that can't run here says why with it (screen recording without wf-recorder, no VPN to toggle, night light unavailable, no other audio output), since a bind or hot corner has no button to grey out.
- When an OSD opens, `BrightnessManager.refresh` picks up brightness changed outside axiom on the monitors its brightness bars show (every one for an `allMonitors` bar; none without a brightness bar).

### Editing
- On the section's `x-card` `views/Settings/OSDListCard`:
  - tabs, one per OSD (named by `labelOf`);
  - the screen picker every placed surface has (its nine spots and a drag);
  - a Show button;
  - its `sections`, each folding (`EntryListCard`): Status icons (the row's mode, then the status types as a grid of icon chips, then which of them stay quiet), Now playing, then the other settings ("Place and timing"), and Bars last (`lastSections`): their layout and list.
- The App field's chips come from `x-suggestions: "audioApps"` (`SettingsManager.suggestionsFor`).

## Engine
The OSD runs on **systems** (one folder per feature) and one engine that judges every change alike: `OSDHost` builds an `OSDSystemHost` per item of an OSD's `systems` and shows what they report. This section is the contract the pieces follow; the sections above describe the behaviour they keep (their older names, `OSDContent`, `OSDStatusSource`, `OSDItems`, are the files this replaced).

### A system's folder
`qml/components/surfaces/osd/systems/<Type>/` (`check_structure` holds each to it):
- `<Type>.qml`, the **definition**: an `OSDSystem` (`engine/OSDSystem.qml`), pure. It imports only `QtQuick`, `qs.components.methods` and `qs.components.surfaces.osd.engine`, so `tst_OSDSystems` loads it.
- `<Type>Watch.qml`, the **watcher**: an `OSDWatch` (`engine/OSDWatch.qml`), the only file of the system that reads services (with `design/`).
- `schema.yaml`: its item in an OSD's `systems` list, a type of the schema kind `OSDSystem` (`index.yaml` › `kinds`, base `definitions/kinds/OSDSystemBase.yaml`, `x-settingsAt: /properties`): `label`, `icon`, `group` (an `x-libraryGroups` name, checked as a bar widget's), its own `settings`, and the parts it has: `tile: standard` adds the switch `tile` (its icons in the row, default on), `card: standard` the switch `card` (its cards, default on). Every item has `type` and `quiet` (its changes don't open the OSD).
- Until a system is ported its folder holds stubs: a definition declaring only its `exposes` and `stub: true` (the timelines skip it), and a watcher with an empty `state`.
- `design/` (optional): visuals only it uses, loaded by URL (`Paths.osdSystemUrl("<Type>/design/<File>")`).
- **No file of the folder names another** (`check_structure`): each is loaded by its URL (`Paths.osdSystemUrl(type)`, `Paths.osdWatchUrl(type)`; a name with a slash names another file of the folder), and `OSDSystemHost` hands the watcher its definition as a property. So qs never has to scan the folder as a module (qml-pitfalls › URL-loaded files): what the files import is what must be reached from `qml/shell.qml`, `qs.components.surfaces.osd.engine` (the host that builds `OSDSystemHost` imports it) and the services and helpers, which are. Until a reached file imports the engine, `check_structure` warns instead of checking that reach. A system's view of its own (a design file) is loaded by URL the same way; anything two systems share goes in `surfaces/osd/design/`, imported by the host.

### The definition (`OSDSystem`)
A definition is mostly declarations: the engine does the hard parts (gaps, settling, reloads, focus-follow, owners across keys, the cards' memory) from them, and `judge()` is a last resort for something truly one-off. Properties (each policy and `model`, `updateFields`, `mark`, `userWindow`, `action`, `call`, the declarations below but `groups`, `takesIn` and `ownerField` may also be set on one `exposes` entry, overriding the system's for that key: `OSDEngine.policy(def, key, name)`):
- `type` (its folder's name; set by its loader), `options` (its item: `{ type, tile, card, quiet, …own settings }`).
- `exposes`: `[{ key, part: "bar" | "tile" | "card", icon, label, group, mark?, opens?, action?, call?, design?, preview?, roles?, …overrides }]`, a binding over `options` where the item's settings pick what it shows. Keys keep the old type names (`audio`, `microphone`, `capsLock`, `camera`, `master`, `other`, …), unique in `exposes`: the microphone's bar is `micLevel` (mark `"microphone"`; its tile keeps `microphone`), an App bar `app:<its index in bars>` (mark `"audio"`). `opens: false`: a change of that key never opens a shut OSD (an Audio bar's or Brightness's `showOsd` off; `OSDEngine.opens`). `mark` is the on-screen mark a change of it is judged by (`ShellManager.onScreen`'s kind; default the key: Audio's bars say `"audio"`). `action` / `call`: what a click on the tile runs (`ActionsManager.run(id, { call })`, call `"toggle"` by default; it was `ActionsManager`'s own list). `design`: a file of the system's own drawing that key (`Paths.osdDesignUrl(type, design)`: a file of its `design/` by name, `"VolumeBar"`, or a path from the systems' folder, `"Audio/design/VolumeBar"`): a bar's is kept handed its `entry`, `orientation` and `showPercent` (Audio's `VolumeBar`, which reads and sets its service itself); a card's is an `OSDCard` (`design/`) kept handed `card` and `change`, which sets its own `title`, `subtitle`, `status` and `picture` (Now playing's `MediaCard`). `preview: true` on a card key: the card an OSD with no bars or icons opens on (its hover strip, the Show button: Now playing's). `roles` (a set's key): `{ add, still, stopped }`, the engine makes its card (`OSDEngine.cardOf`, below).
- `model`: `"scalar"` (state `{ value, … }`), `"set"` (`{ members: [{ id, … }], … }`) or `"event"` (`{ event, seq }`). A bar's state is `{ level, muted }` whatever the model.
- Policies, each `"card"`, `"icon"` or `"none"`: `onAdd` (default `"icon"`), `onChange` (`"icon"`), `onUpdate` (`"icon"`), `onRemove` (`"icon"`; also `"still"`), `onUnexpectedRemove` (`""`: onRemove's).
- `updateFields` (`["icon", "label"]`): besides `on` and `slash`, which always count, the tile fields whose change with the value the same is an `update`. Audio's is `["label"]`: a Bluetooth profile switch changes the device's icon, which isn't a change of its own.
- `anyone` (false): count changes the watcher calls unsettled (`settled()` false) too.
- `settledKinds` (null: every kind): the change kinds that count only while the watcher calls them settled. Audio's `["update", "level"]`: a device switch counts as its new node binds (never settled), a mute or a level only once it has. `anyone` makes it none.
- `resetBy` (`[]`): state fields whose change makes a change of the key nobody's, so nothing shows (a reload, not a switch: KeyboardLayout's `ids`, Audio's stream bars' `streams`).
- `ignoreWithin` (null): `{ after, ms, unlessAfter }`, state fields holding times (`Date.now()` ms, 0 for never): a change within `ms` after `after` shows nothing, unless within `ms` after `unlessAfter` too. KeyboardLayout's focus-follow: `{ after: "focusedAt", ms: 1000, unlessAfter: "switchedAt" }` (a window's own input method coming back on focus, unless axiom switched then).
- `keepThroughGap` (false; scalar): a value going empty is a gap, not a removal, and the watcher judges the next value against the one before the gap (`OSDEngine.remember`). Audio's devices: a Bluetooth headset's profile switch replaces its node, often with none between; the device it comes back as isn't a switch.
- `takesIn` (`"key"`): what changes without a card its card out takes in within the quiet window (`sameChange`'s default): `"key"` its own key's (a capture stopping as it starts), `"system"` any of its keys' (Audio: a new device's mute, its level arriving late).
- `ownerField` (`""`; set): the member field naming who a member belongs to (Privacy's `"app"`): what a set's card names and what `groups` match by (a member without it, its id).
- `groups` (`[]`): `[{ keys, role }]`, keys whose changes of one owner make one card. A key's owners are a set's members' `ownerField`, once each, or a scalar's value (`OSDEngine.ownersOf`); a grouped key's tile carries them (`owners`). Three things follow:
  - a card of one key coming within the quiet window of another's card out, an owner in common, is kept (Arbitration rule 3);
  - the card of an arrival (`add`, `change`, not `still`) whose owner another listed key of the group holds says the group's `role` (Audio's "Output and input", Privacy's "Using the camera and microphone"), re-read as the state changes;
  - under `onRemove: "still"`, a set's last member of an owner leaving one key while the owner stays on another listed key of the group is a still card (`kept` that key): Privacy's "Vesktop / Still using the microphone" as a call app drops its camera.
- `userWindow` (2000): ms after its mark a change is the pointer's (8000 Wi-Fi, Bluetooth, airplane mode; 15000 a VPN).
- `retractsCardWhenOff` (false), `knockOnOf` (`[]`, system names): see Arbitration.
- Functions, each overridden by a definition declaring its own (the base calls them through `root`, so its own `actionOf` sees an override):
  - `tile(key, state)` → any of `{ icon, label, tone, on, slash, notable, hidden, name, nameOnly, … }` (`name` a device's, a VPN's or the apps': the tooltip's value; `nameOnly` a tile whose on and off say nothing, named alone in its tooltip: the power profile) (`state` is that key's; `OSDEngine.tileOf` fills the rest, the icon from `exposes`).
  - `card(change, state)` → `{ icon, image, title, role, detail, tone, clickable }` or null (`state` is the system's, by key; English, translated by the view, its strings declared in a comment as `I18n.tr("…")` calls; `OSDEngine.cardOf` fills the rest, the icon from the tile).
  - `judge(before, after, ctx)` → `undefined` (leave it to the engine), `null` (nothing), or `{ kind, show, … }` (its extra fields kept). `ctx`: `{ key, part, model, at, byUser, settled, before, after }` (`before` / `after` the whole states). It's asked only past the first reading and `available` (rule 2 and 3 below), and reads `ctx.settled` itself. It may set `alert: true` (Bluetooth's battery low or critical). A last resort, for what no declaration says (lock-key availability, VPN transitional states): Audio, KeyboardLayout and Privacy declare everything. It runs before the engine's own guards and declarations.
  - `sameChange(shown, incoming)` → bool; default `incoming.card !== true && shown.key === incoming.key`.
  - `absorbs(own, other)` → bool; default false.
  - `actionOf(key, state)` → `{ id, call }` or null; default from `exposes`.
  - `activate(change)` → an `ActionsManager` id, or `""` to hand the click to the watcher's `activate(change)`.

### The judgement (`OSDEngine.judge(def, key, before, after, ctx)`)
- Returns null (nothing shows) or `{ key, part, model, kind, show, card, still, unexpected, alert, added, removed, left, at, byUser }`. `alert` (false unless the definition's `judge()` sets it): it opens the OSD even when made on screen (`OSDEngine.opens`). `kind`: `"add"`, `"remove"`, `"change"`, `"update"`, `"event"`, `"level"`. `show`: `"card"`, `"tile"`, `"level"` (`card` is `show === "card"`).
- `members` (a set's change): the members as the change saw them, those after an arrival, those before a departure. It's the card's memory: a host keeps the change of its card out, so the card still names who came once they're gone (a picker's preview stream stopping under its card: "Stopped sharing the screen"; was `OSDStatusSource._lastApps`). `kept`: a group's still card's key the owner stays on.
- `ctx`: `{ at, byUser, settled, before, after }`.
- In order:
  1. **The same state** (`OSDEngine.same(model, before, after)`: an event's by the event object and its `seq`, any other by value): null.
  2. **The first reading** (`before` missing): null.
  3. **Not available**: `before.available` or `after.available` is `false`: null (the LEDs appearing, Wi-Fi or Bluetooth with no service).
  4. **The definition's own** `judge()`, when it doesn't return `undefined` (it sees `ctx.settled`; nothing below applies to it).
  5. **The declarations:** a field of `resetBy` changed with it, or it came within `ignoreWithin`: null.
  6. **The model** (each kind it finds counts unsettled only if `settledKinds` leaves it out, or with `anyone`):
     - A bar: `level`.
     - `event`: a non-null `after.event` is `event`, shown by `onAdd`.
     - `set`, by member id: any added is `add` (`onAdd`; `added`); else any removed is `remove` (`removed`, `left` the ids still there; `kept` when a group's key keeps the owner).
     - `scalar`: `value` empty → not is `add` (`onAdd`), not → empty is `remove` (a gap with `keepThroughGap`: null), one → another is `change` (`onChange`). Empty is `undefined`, `null`, `""`, `false` or `[]`. The tile's look changing (its `on`, `slash` and `updateFields`; not its name or a signal) is `update` (`onUpdate`). When both happen, the stronger show wins (card, then tile): Wi-Fi turned off loses its network (`remove`, none) and its look (`update`, the icon).
  7. **A removal:** `unexpected` is `!ctx.byUser`. Its policy is `onUnexpectedRemove` when unexpected and set, else `onRemove`. `"still"` shows a card while some are left, or a group's key keeps the owner (`still: true`), the icon for the last.
  8. **A policy of `"none"`**: null.
- **Who made it** (`byUser`): the watcher asks `ShellManager.fromScreen(mark, userWindow)`. `fromScreen(kind, window)`: marked (`ShellManager.onScreen(kind)`) less than `window` ms ago, never from the future; `ActionsManager._osdKinds` gives each action's mark. `OSD.onScreenChanges` stays the host's (an on-screen change still opens it with the switch on). A click on the OSD's own tile marks its kind (`OSDHost.toggle`; the OSD is open, so it still shows), so a VPN taken down there is expected.

### The watcher (`OSDWatch`)
A `QtObject` (an Item's `state` is taken); what it declares inside (Connections, Timers) goes in its default `data`.
- `definition` (set by `OSDSystemHost`), `options`, `screen` (the OSD's screen, a ShellScreen: Brightness reads its monitor, with `allMonitors` all of them), `osdId` (the OSD's id: Message takes only its own OSD's `ShellManager.osdMessage`).
- `holds`: services acquired (`acquire(watch)`) on completion and released on destruction.
- `state`: by exposed key, bound to its services; the definition's model's shape. `available: false` holds judgement.
- `settled(key, before, after)`: false while its service is still settling (Audio: `AudioManager.sinkSettled()` / `sourceSettled()`); a change then only moves the state on.
- `events` and `pulse(key, event)`: an event model's state (`"drive": watch.events.drive ?? ({ event: null })`), `seq` counting each one, so one like the last still counts.
- `activate(change)`: a card's click the definition hands back.
- `opened()`: its OSD opened on this screen (`OSDHost.open`): picks up what nothing pushes (Brightness `refresh`es the monitors its bar shows; was `OSDTriggers`').
- `setLevel(key, level)` / `iconClicked(key)`: a bar with no `design` (`OSDLevelBar`'s plain `StyledVolumeBar`) dragged or scrolled, or its icon clicked (clickable while its state has `muted`).
- `tiles` (readonly): `OSDEngine.tileOf` of each tile key.
- `change(what)` (signal): each judged change, `OSDEngine.judge`'s with `{ system }`, in `exposes` order.
- How it runs:
  - A state change is judged once it's all in (`Qt.callLater`), every key against the state last judged (`OSDEngine.remember(def, before, after)`: a `keepThroughGap` value kept through a gap; `state`, `snapshot` and the tiles stay as they are).
  - For its first 1.5 s nothing is reported: the changes only move the state on, while services settle.
  - A watcher for a toggle is a few lines: `state: ({ "caffeine": { "value": IdleManager.caffeine } })`.

### The host of one system (`OSDSystemHost`)
- **Inputs:** `type`, `options`, `screen`, `osdId` (the last two handed to the watcher, and kept up to date). It loads the definition (`Paths.osdSystemUrl(type)`, given `type` and `options`), then the watcher (`Paths.osdWatchUrl(type)`, given `definition` and `options`). Both load anew only as `type` changes; `options` reaches both in place.
- **Exposes:**
  - `definition`, `watch`;
  - `snapshot` (the watcher's `state`), `tiles`;
  - `change(what)` (relayed);
  - `card(what)` (`OSDEngine.cardOf` over `snapshot`), `actionOf(key)`;
  - `opens(what)` (`OSDEngine.opens` with the item and `OSD.onScreenChanges`: whether the change opens a shut OSD);
  - `activate(what)` (returns the id for the caller to run, else hands the click to the watcher).
- **The card out is re-read from the live state:** the host keeps the change that brought the card out and shows `card(change)`, bound to `snapshot`, so it says what holds now (the apps left after another stops, a network's name filling in, "Stopped …" as a capture stops under its card), never a copy taken as it came.
- **Opening:** `OSDEngine.opens(item, def, change, onScreenChanges)`: never with the item `quiet` or the key's `opens: false`; else unless made on screen (`byUser`), which `OSD.onScreenChanges` or the change's `alert` overrides. A change that doesn't open the OSD still shows on an open one.

### The OSD's host (`OSDHost`)
- **Systems:** a Repeater over the `systems` items' types as a string (an edit of an item's own settings reaches its `OSDSystemHost` in place; a type added, removed or moved rebuilds them), each given its item, the OSD's `screen` and `osdId`. No system is named in the host.
- **Parts from the systems:** the bars are each shown system's `exposes` bars (`OSDLevelBar`, by count), the row its tiles by id `"<type>/<key>"` (`OSDTileRow` / `OSDTile`, named by each entry's `label`), the card `OSDSystemHost.card(change)` of the change it keeps (`OSDCard`, or the key's `design`). A system's bars and tiles show only with its item's `tile` on.
- **A change** (`OSDSystemHost.change`): `OSDEngine.shownAs` says what it shows on this OSD (a level only with the item's `tile` on); it's made whole (`system`, `tile` now, `card`), `OSDSystemHost.opens` says whether it opens the OSD shut, and it's asked in the order below (Arbitration): a card against the card out, a bar against the card out (the late level's fix), a tile against the card out then the ring.
- **Opening:** `open` (the host's `isOpen`) calls each watcher's `opened()`; `OSDTriggers` only pokes the host and answers the Show button.

### Arbitration (`OSDEngine.arbitrate(shown, incoming, elapsed, defs)`)
`shown` / `incoming`: whole judged changes (`judge()`'s: `key`, `part`, `kind`, `card` (bool), `still`, `unexpected`, `alert`, `added`, `removed`, `left`, `at`, `byUser`), each with its `system` and `tile` (that key's tile now); `sameChange` and `absorbs` read any of it. A host keeps the whole change of its card and of its ring for this; `elapsed` ms since `shown` came; `defs` the definitions by system. Returns:
- **Against a card out** (`shown.card`):
  - a card: `"replace"` (it swaps in) or `"keep"` (the same change: the first card says it);
  - a change without one (a tile or a bar): `"retract"` (the card folds back, the change shows), `"suppress"` (nothing shows) or `"beside"` (it shows beside the card).
- **Against the ringed tile** (`shown.card` false; only a tile change without a card asks): `"replace"` (it takes the ring) or `"keep"` (nothing shows).

The rules, in order:
1. **Retract:** against a card, a change of the same system and key without a card, with the system's `retractsCardWhenOff` and its tile not `on`, is `"retract"`, at any age.
2. **Past the quiet window** (`elapsed >= OSDEngine.quietWindow`, 2000): no knock-on.
3. **A knock-on**, within the window: `incoming`'s system lists `shown`'s in `knockOnOf`; or another system that `shown`'s `absorbs(shown, incoming)`; or (against a card only) the same system, whose `sameChange(shown, incoming)` says so, or with a card of its own: a still card against its own key's still card (several leaving one after another: the card out, re-read, names those left), or a card of another key of `shown`'s group, an owner in common (the tiles' `owners`). It makes a card `"keep"`, a change without one `"suppress"`, and the ring `"keep"`.
4. **Else** a card `"replace"`s, a change without one shows `"beside"`, and a tile takes the ring.

A host asks in this order (`tst_OSDSystems` simulates it):
- **A card:** with no card out it opens; else arbitrate against the card.
- **A bar:** against a card out (`"suppress"` or `"beside"`), else it opens.
- **A tile:**
  - against a card out first (`"suppress"` ends it, `"retract"` folds it back);
  - then against the ring (`"keep"` ends it);
  - else it takes the ring.
- **No ring** for a key without a tile part (a message).

**How each old branch maps** (`OSDItems.replaces` / `besideCard`, `OSDContent.showStatus`):

| Old branch | Declaration |
|---|---|
| `elapsed >= quietWindow` → replaces | rule 2 |
| `shown === "message"` card: gives way only to a card | default: the Message system's `sameChange` is the default (same key, no card), and a message never comes without its card, so a card replaces it and anything else shows beside; no tile, so no ring |
| airplane ringed, `wifi` / `bluetooth` within the window → keep the ring | Wifi and Bluetooth `knockOnOf: ["Airplane"]` |
| `shownCard` false → replaces (the ring) | rule 4 |
| same type, no card, `vpn` / `wifi` / `charger` off → retract (`besideCard`, any age) | `retractsCardWhenOff: true` on Vpn, Wifi and Battery (Battery's `battery` key never comes without its card) |
| same type, no card, still on → suppress (the other half of a VPN switch, a capture stopping as it starts, Wi-Fi still on) | default `sameChange` (same key, no card) |
| camera ↔ micUse cards from one app → keep (one card says both) | Privacy's `groups: [{ keys: ["camera", "micUse"] }]` by `ownerField: "app"` (rule 3) |
| a capture stopping beside another capture's card → beside | the default `sameChange`: the same key only |
| (new) a still card just after its key's still card → keep | rule 3 |
| audio ↔ microphone cards, same device → keep (a headset) | Audio's `groups: [{ keys: ["audio", "microphone"] }]`, matched by value (rule 3) |
| audio ↔ microphone card, another device, or the same key again → replace | no owner in common |
| audio / microphone no card (a mute) after a device card → suppress | Audio's `takesIn: "system"`: any of its keys |
| (new) a device's level arriving late after its card → no bars beside it | the same: a bar is one of Audio's keys, and bars now arbitrate too (issues.md: "A device's own level arriving late brings the OSD's bars out beside its card") |
| (new) a Bluetooth headset's card takes in Audio's switch to it | Bluetooth's `absorbs(own, other)`: Audio's change to its address |
| a card replaces any ring (`showStatus`' card branch never asks the ring) | a host asks a card only against a card out |

### Routing (`OSDEngine.opensCard` / `cardRoute` / `shownAs`)
Over the new OSD entry shape `{ enabled, cardsEnabled, systems: [{ type, tile, card, quiet, … }] }` (`OSDEngine.itemOf(osd, type)` finds an item):
- `opensCard(osd, type, key)`: an enabled OSD with its cards on, listing the system with its `card` not false and not `quiet`; with `key` (the event's), an item whose `tiles` setting picks the keys it shows (Audio's, Battery's) must pick it (a low battery's card only where Battery shows `battery`). The card-only types of old are systems with only a card part.
- `cardRoute(osds, type, notify, key)`: `"osd"` when one opens it, else `"notification"` with `notify`, else `""`.
- `shownAs(osd, change, hasTile)`: what a change shows on that OSD.
  - A card stays a card while the OSD's and the item's cards are on.
  - Else it shows as its tile, when the key has one and the item's `tile` isn't false; else nothing.
  - A tile shows only under the same tile condition.
  - A level shows as a level.

### The parts (`OSDParts`)
`parts`, `rowTypes(keys, tiles, mode, kept)`, `partOrder`, `sharedDeadlines`, `partsDue`: moved from `OSDItems` unchanged (What shows above), tested in `tst_OSDParts`.

### Timelines (`tests/tst_OSDSystems.qml`, `tests/osd/`)
The spec of every system's behaviour.
- **Files:** `tests/osd/index.js` lists the row files by name (`files: { "<System>": <its rows> }`, each `.import`ed), one `.pragma library` file per system (`tests/osd/<System>.js`, `var rows = [...]`) and `Cross.js` for rows across systems.
- **What it runs:** the pure definition (loaded from its path by `Qt.createComponent`) and `OSDEngine`, with no watcher and no settle window; each step judged against the state the watcher would keep (`OSDEngine.remember`). A row of a system with no folder yet, or a stub (`stub: true`), is skipped, as `SKIP` (that allowance goes once every system is ported).
- **A row:**
  - `name`;
  - `systems` (default: the file's name);
  - `options` (the item's settings, by system or for the only one);
  - `host` (what's out at the start: `{ card: { system, key, at }, ring: { system, key, at } }`; once a change comes out the simulated host keeps it whole, and arbitrates with it);
  - `onScreenChanges` (`OSD.onScreenChanges` for `opens`; default false);
  - `steps`.
- **A step:**
  - `system` (default: the row's first);
  - `at` (ms; default 3000 after the last, past the quiet window);
  - `state`: by key, laid over that system's state (a key given replaces it; `null` deletes it; one not given keeps the very same object, so an event isn't seen anew);
  - `byUser` (default false);
  - `settled` (default true; or by key);
  - `tiles`: by key, a subset of each one's tile after the step, changed or not (`hidden` too; the first reading's included);
  - `expect`.
- **The first step** of a system is its first reading: nothing shows.
- **`expect`:**
  - Omitted or `"none"`: nothing shows.
  - An object: exactly one change. An array: those, in `exposes` order.
  - Each may hold:
    - `key`, `show` (both checked first, as a list);
    - any field of the change (`kind`, `still`, `unexpected`, `alert`, `added`, `removed`, `left`, `byUser`);
    - `opens`: whether the change opens a shut OSD (`OSDEngine.opens` with the row's item `options`, its `quiet`, the key's `opens`, `byUser`, `alert` and the row's `onScreenChanges`);
    - `action`: a subset of the definition's `actionOf(key, state)` (`null`: none);
    - `tile` (a subset of `OSDEngine.tileOf` for the key after the step) and `card` (a subset of `OSDEngine.cardOf`; `null`: none);
    - `host`: the simulated host's decision. For a card it's `"open"`, `"replace"` or `"keep"`. For a tile it's `"ring"`, `"keep"`, `"beside"`, `"suppress"` or `"retract"`. For a bar it's `"open"`, `"beside"` or `"suppress"`.
- A subset compares objects field by field, anything else exactly.
- **Example:**
  ```js
  { "name": "turned on: its icon, lit and unusual",
    "steps": [
      { "at": 0, "state": { "caffeine": { "value": false } } },
      { "at": 3000, "state": { "caffeine": { "value": true } },
        "expect": { "key": "caffeine", "show": "tile", "kind": "add", "tile": { "on": true, "notable": true }, "host": "ring" } } ] }
  ```
