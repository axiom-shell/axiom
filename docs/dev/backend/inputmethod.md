# Input methods (daemon)

> **Files:** `backend/internal/inputmethod/inputmethod.go`, `backend/internal/inputmethod/fcitx5.go`, `backend/internal/inputmethod/ibus.go`, `backend/internal/daemon/inputmethod.go`, `backend/internal/daemon/wayland.go`
> **Related:** [D-Bus](dbus.md), [Wayland](wayland.md), [Protocol](protocol.md)

The daemon's side of input sources: it finds the input method framework (fcitx5 or ibus), follows its current input method, its list and the engines installed, switches input methods, pushes the list axiom owns (`Input.keyboard.sources`) to the framework, and sets fcitx5's few options axiom has settings for. The shell's side (`InputSourceManager`) reads it through the `inputMethod` topic.

### Finding the framework
`inputmethod.Service.Run` looks for one, follows it while it runs, and looks again when it stops, when it appears, or when `inputMethod.framework` changes the choice. It never starts or stops a framework.
- **The choice** (`inputMethod.framework {name}`, shell only): `none` (nothing followed, nothing connected), `auto` (the default until the shell says: fcitx5 when it runs, else ibus), `fcitx5`, `ibus`.
- **fcitx5:** `org.fcitx.Fcitx5` owned on the session bus. Heard starting and stopping at once (`NameOwnerChanged`). A running fcitx5 wins in `auto`, also over an ibus followed already.
- **ibus:** never the session bus, where fcitx5 owns `org.freedesktop.IBus` too. The real ibus-daemon runs its own bus, found as libibus finds it: `$IBUS_ADDRESS`, else the address file (`$IBUS_ADDRESS_FILE`, else `~/.config/ibus/bus/<machine-id>-<host>-<display>`: the Wayland display's name whole, else X's `host:number`, host `unix` when empty). Its `IBUS_DAEMON_PID` must be a running `ibus-daemon` (`/proc/<pid>/comm`), not just any process: fcitx5's ibus frontend writes the same file, naming the session bus and itself. ibus appearing is noticed on the next look at its address (every 10 s while nothing runs, unless the choice is `fcitx5`); the session bus connection that hears fcitx5 stays open meanwhile.

### fcitx5
`org.fcitx.Fcitx.Controller1` at `/controller` (fcitx5's dbus module).
- **Read:** `CurrentInputMethod`, `CurrentInputMethodGroup`, `FullInputMethodGroupInfo(group)` (the default layout and the items' unique names and layouts) and `AvailableInputMethods` (unique name, name, native name, icon, label, language, configurable).
- **When it changes:** Controller1 has no signal for the input method changing; its only signal is `InputMethodGroupsChanged`. fcitx5's StatusNotifierItem (`/StatusNotifierItem`, on a connection of its own with no well-known name) sends `NewIcon` / `NewToolTip` on every switch, so the service subscribes to every item's and keeps those whose connection's process (`GetConnectionUnixProcessID`) is the `org.fcitx.Fcitx5` owner's, then reads `CurrentInputMethod` again. fcitx5 registers that item only while a StatusNotifierWatcher runs (axiom's is Quickshell's, there only while a bar has a SystemTray): the service knows it's registered while the watcher's `RegisteredStatusNotifierItems` lists a connection of fcitx5's process (asked of the watcher's owner by its unique name, so the check never starts an activatable watcher; asked again when a watcher comes or goes and on its `StatusNotifierItemRegistered` / `Unregistered`; an item's `NewIcon` says so too). Without it, the **`inputMethodPoll` topic** stands in: while the shell holds it (`InputSourceManager.acquire`: the KeyboardLayout widget, its popout, the module and the OSD's KeyboardLayout system; only while a managed framework runs), each fetch (about once a second, `Service.Poll`) has the follow loop read the whole state again (a switch or a group edit; an unchanged state publishes nothing). With the item registered, with ibus, or with no subscriber, nothing is read; its state is `{polling}`. A **group edit** (`SetInputMethodGroupInfo`, fcitx5-configtool) sends nothing on Controller1 and no `NewIcon`: on a real fcitx5 5.1 the only signal is its tray menu's `com.canonical.dbusmenu` `LayoutUpdated` (`/MenuBar`, on the item's connection), so the service subscribes to it (kept by the same process check) and reads the state again; with no item there's no menu either, and the poll above sees the edit. `InputMethodGroupsChanged` (a group added or removed) reads everything again, the installed list too.
- **`current` is `""`** while no text field had focus yet: fcitx5's current input method is the most recent input context's. The shell takes the list's first then.
- **Switch:** `SetCurrentIM`.
- **Push:** `SetInputMethodGroupInfo(<current group>, defaultLayout, items)`, then `Save`.
- **Options:** `SetConfig`, which loads a partial config over the rest: `fcitx://config/global` `Behavior/ShareInputState` (`No` / `All` / `Program`), `Behavior/ShowInputMethodInformation` and `Hotkey/TriggerKeys` (a list: its items keyed `0`, `1`, …, so an empty map empties it); `fcitx://config/addon/classicui` `Vertical Candidate List` and `Font`. fcitx5 writes booleans as `True` / `False`.

### ibus
`org.freedesktop.IBus` at `/org/freedesktop/IBus` on its own bus.
- **Read:** the `Engines` property (installed) and `GlobalEngine` (current; an error, read as `""`, when there is none). The list is the `org.freedesktop.ibus.general preload-engines` setting (`gsettings get`; each item's layout its engine's), which a push and ibus-setup write and ibus's panel preloads: the daemon has no readable list (`PreloadEngines` is write-only, `ActiveEngines` only the engines of components registered while it runs). Without gsettings, or when it fails, the list reads empty. An engine read is a serialized `IBusEngineDesc`: its type name and attachments, then name, long name, description, language, license, author, icon, layout, rank, hotkeys, symbol, … (an order ibus keeps). The label is the symbol, else the language; a layout of `default` reads `""`.
- **When it changes:** every signal of its (`GlobalEngineChanged`, `RegistryChanged`, `PropertiesChanged`) reads it again, the list too except on a switch (`GlobalEngineChanged`).
- **Switch:** `SetGlobalEngine`.
- **Push:** an engine ibus doesn't have (`Engines`) is refused (`failed`) before anything is written; then the `preload-engines` setting (`gsettings set`), which its panel and its next start read, then the `PreloadEngines` property (applied at once). The setting goes first: the property's `PropertiesChanged` rereads the list from it, which would otherwise still hold the old list and show the push as an outside edit for a moment. ibus engines carry their own layouts, so `defaultLayout` and the items' layouts aren't used.
- **Options:** only the font (`org.freedesktop.ibus.panel` `custom-font`, and `use-custom-font`; an empty font turns it off). ibus has no equivalent of the others.
- gsettings runs as a process with its arguments, no shell, the value in GVariant's text form (`['xkb:us::eng', 'mozc-jp']`); a failed one's error carries what it printed on stderr.

### Outside edits
The service remembers the list it pushed last and the framework it went to (in memory, for the daemon's life). Whenever the same framework's list read differs from it (fcitx5: the default layout, names and layouts; ibus: the names), `outsideEdit` is true: fcitx5-configtool or ibus-setup changed it. Before any push, and for another framework than the one pushed to (fcitx5 taking over from ibus, or the choice changed), it stays false. Pushing again, or pushing the list read, clears it. While a push is in flight (the list is remembered before the framework has it) a read keeps the flag as it was: the read after the push decides it, so a switch's refresh, a poll or a tray signal landing in between never shows the push as an outside edit.

### Protocol
- **Topic `inputMethod`:** `inputMethod.state` (latest-wins), also `inputMethod.get`: `{framework, running, current, defaultLayout, group: [{name, layout}], available: [{name, label, displayName, icon, lang}], outsideEdit}`. `framework` is the one followed (`fcitx5`, `ibus`), or the one asked for while it isn't running, `""` for none.
- **`inputMethod.set {name}`:** switch (any client: switching is what a keybind does).
- **`inputMethod.push {defaultLayout, items: [{name, layout}]}`** (shell only): an empty list, an item without a name or one twice is `bad_request`.
- **`inputMethod.options {shareState?, verticalCandidates?, candidateFont?, showSwitchPopup?, triggerKeys?}`** (shell only; `triggerKeys` fcitx5's switch hotkeys, `[]` for none): a key left out is left as it is.
- **`inputMethod.framework {name}`** (shell only).
- With no framework running, the writes answer `unavailable`.

### The capability
`supports.inputMethod` is whether the compositor offers `zwp_input_method_manager_v2`, the protocol fcitx5 and ibus type through on Wayland: `wayland.state`'s `inputMethod` flag. The daemon's Wayland connection only watches the global (`waylandSession`, which binds nothing), so a compositor adding or removing it later is told.

### Testing
- `inputmethod_test.go` runs a fake fcitx5 (Controller1 and its item on a second connection, which, like a real 5.1, tells of a group edit only through its menu's `LayoutUpdated`; a tray watcher listing it, for the poll's fallback) and a fake ibus-daemon (on a second `dbustest` bus) through the service.
- Pushing a list or `SetConfig` to your live fcitx5 or ibus rewrites your profile, so try it on a scratch D-Bus session. Reading is safe (`busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 FullInputMethodGroupInfo s Default`).
