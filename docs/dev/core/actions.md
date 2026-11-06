# Actions (one catalogue)

> **Files:** `backend/internal/compositor/actions/table.json` (what each action is: its IPC call, label, section, icon, calls, argument), `qml/services/ui/ActionsManager.qml` (each action's state and the one way to run it), `qml/components/methods/BindActions.qml` (the table's functions), `qml/services/ui/ShellManager.qml` (`runAction`), `qml/services/core/BackendManager.qml` (`callLocal`), `backend/internal/schema/yamlsrc/actions.go` (`x-axiomActions`)
> **Config:** `Keybinds.binds[].action`, `HotCorners.items[].action`, a QuickActions module's `actions`, a Button widget's `action`
> **Related:** [Keybinds](../hyprland/keybinds.md), [Hot corners](../features/hot-corners.md), [OSD](../features/osd.md), [Launcher](../features/launcher.md), [Schema annotations](schema-annotations.md)

Every one-tap thing the shell does (Wi-Fi, Bluetooth, airplane mode, the VPN, do not disturb, caffeine, night light, dark mode, the power saver, the mutes, a recording, the session actions, opening a surface, …) is one action of one catalogue, offered in many places and run the same way from each. (Rule: AGENTS.md › Services.)

### What an action is
- **Its definition** is a row of the keybind table, `table.json`'s `ipcActions`: `[IPC call, label, section]`, with its icon in `icons`, its open/close functions in `calls`, its argument kind in `argumentKinds`. The daemon sends the table to the shell (`compositor.bindActions`, `KeybindManager.actionTable`), so the Go writers, the Keybinds page and every UI read one list.
- **Its state** is `ActionsManager`'s:
  - `available(id)`: whatever it needs is here (a device, a tool, a compositor capability; hibernate, logind's `CanHibernate`: `SessionManager.canHibernate`, asked once at start). It reads no on/off state, so a list of the actions shown can be a Repeater's model.
  - `info(id)`: `{ active, status, icon }`, from its service.
  - `label(id)`: the table's (as the Keybinds page shows it), or a tile's shorter one (Mute, Mute mic, VPN, Record).
  - `destructive(id)`: log out, restart and shut down (SessionManager's list).
- **Its run** is `ActionsManager.run(id, { call, argument, fromScreen })`. `fromScreen` marks the change as the pointer's first (`ShellManager.onScreen`, by `osdKind(id)`), so an OSD stays shut for it unless `OSD.onScreenChanges`. Then `ShellManager.runAction` makes the IPC call its keybind would (`BindActions.ipcCall`) and runs it in place (`BackendManager.callLocal`: the same checks as `axiom ipc`, with no round trip). A tile, the OSD, a command, a key and a hot corner therefore run the same IPC function. The session actions go to `SessionManager.sessionAction` instead, as the power menu always ran them: lock then works with a locker of the user's own (`Lockscreen.mode` "none", whose `lockscreen` target is off), and log out isn't a table action (the compositor's `exitSession` is its bind).
- Until the daemon's hello the table is null: icons are `keyboard`, and run() logs that it can't run the action.

### Where actions are offered
- **Keybinds** (all of the table's, run by the compositor through `axiom ipc`) and **hot corners** (the table's less what a stray pointer mustn't fire: losing state, moving a window, restart and shut down; `ActionsManager.run` with the corner's call and argument, not marked as the pointer's, so lock works with a locker of the user's own).
- **QuickActions tiles**: every action that takes no argument but clipboard, emoji and calculator (they only open the launcher with a prefix typed), in the order the user drags them into (`x-ordered`), plus tiles of the module's own: Brightness, Volume, Theme and Wallpaper open their module (nothing to switch), Pin open pins its edge menu, Log out is SessionManager's. A tile's detail (Wi-Fi's networks, the mixer for the mutes, the VPNs, the recorder) is the module's `details` map.
- **The Button bar widget**: any action that takes no argument (but clipboard, emoji and calculator, as for tiles), or its own (an overlay page, an edge menu at the button, a command, nothing). Destructive ones ask for a second click there too, and only the actions that open something run on hover (as the schema shows `hoverActivate`).
- **OSD status icons**: `ActionsManager.osdStatusAction(type)` names the action a click runs (the layout to the next, the profile between power saver and balanced, …); a status nothing switches has none. Not marked as the pointer's: that OSD is showing.
- **Launcher commands**: `LauncherCommands._action` / `_switch` (`[on | off]` maps to the open / close call). Not marked (typed, and the launcher closes).
- **Bar widgets' clicks** (Bluetooth, IdleInhibitor, Notifications, Vpn, KeyboardLayout, ScreenRecord) and the modules' own controls (WifiNetworks, BluetoothDevices, NightLightControls, Caffeine, ThemePicker's dark and light, WallpaperPicker's next, ScreenRecord's stop, NotificationHeader, Screenshot's tiles, the Notifications module's Clear all (after its cards leave), the Notifications widget's middle click, the night light settings card, the OSD bars' mute icons, the Pomodoro and Stopwatch widgets and modules, the Monitors page's Identify).
- `check_structure` fails a UI file calling one of these actions' service toggles or setters, or `ShellManager.runAction`, directly. A call that must stay marks its line `// allowed: <reason>`: VolumeDials, Power, NowPlaying and KeyboardLayout, which also run on the lock screen, where `x-lockActions` cover their service calls and not `ActionsManager`.

### The enums
`x-axiomActions` fills an action enum from the table at schema build time ([schema annotations](schema-annotations.md)): `except` leaves actions out (hot corners; QuickActions and Button the launcher prefixes), `noArgument: true` keeps only those with no `{0}` (QuickActions, Button), `extra` adds the field's own values after the table's, labelled by its own `x-enumLabels`. It also fills `x-enumIcons` and `x-enumGroups` (the table's icons and sections), which the ordered chips of a QuickActions module show. The Keybind definition's own enum stays hand-kept (it also lists the compositor actions); `tst_BindActions` checks it against the table, and every action has an icon.

### Adding an action
1. A row in `table.json`'s `ipcActions` (with `calls` if it opens and closes, `argumentKinds` if it takes one) and its icon in `icons`.
2. The IPC target and function in its service (`IpcTarget`), and its row in `docs/usage.md`'s IPC table.
3. Its label in `Keybind.yaml`'s `action` enum and `x-enumLabels`.
4. Its state in `ActionsManager.available` / `info` if it has any, and its `osdKind` if an OSD shows its change.
5. Optionally a detail in QuickActions' `details`, a launcher command (`_action` / `_switch`), and an OSD status (`_statusActions`).

