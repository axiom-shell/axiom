# Input methods (daemon)

> **Files:** `backend/internal/inputmethod/inputmethod.go`, `backend/internal/inputmethod/fcitx5.go`, `backend/internal/inputmethod/ibus.go`, `backend/internal/daemon/inputmethod.go`, `backend/internal/daemon/wayland.go`
> **Related:** [D-Bus](dbus.md), [Wayland](wayland.md), [Protocol](protocol.md)

The daemon's side of input sources: it finds the input method framework (fcitx5 or ibus), follows its current input method, its list and the engines installed, switches input methods, pushes the list axiom owns (`Input.sources`) to the framework, and sets fcitx5's few options axiom has settings for. The shell's side (`InputSourceManager`) reads it through the `inputMethod` topic.

### Finding the framework
`inputmethod.Service.Run` looks for one, follows it while it runs, and looks again when it stops, when it appears, or when `inputMethod.framework` changes the choice. It never starts or stops a framework.
- **The choice** (`inputMethod.framework {name}`, shell only): `none` (nothing followed, nothing connected), `auto` (the default until the shell says: fcitx5 when it runs, else ibus), `fcitx5`, `ibus`.
- **fcitx5:** `org.fcitx.Fcitx5` owned on the session bus. Heard starting and stopping at once (`NameOwnerChanged`). A running fcitx5 wins in `auto`, also over an ibus followed already.
- **ibus:** never the session bus, where fcitx5 owns `org.freedesktop.IBus` too. The real ibus-daemon runs its own bus, found as libibus finds it: `$IBUS_ADDRESS`, else the address file (`$IBUS_ADDRESS_FILE`, else `~/.config/ibus/bus/<machine-id>-<host>-<display>`: the Wayland display's name whole, else X's `host:number`, host `unix` when empty). Its `IBUS_DAEMON_PID` must be a running `ibus-daemon` (`/proc/<pid>/comm`), not just any process: fcitx5's ibus frontend writes the same file, naming the session bus and itself. ibus appearing is noticed on the next look at its address (every 10 s while nothing runs, unless the choice is `fcitx5`); the session bus connection that hears fcitx5 stays open meanwhile.

### fcitx5
`org.fcitx.Fcitx.Controller1` at `/controller` (fcitx5's dbus module).
- **Read:** `CurrentInputMethod`, `CurrentInputMethodGroup`, `FullInputMethodGroupInfo(group)` (the default layout and the items' unique names and layouts) and `AvailableInputMethods` (unique name, name, native name, icon, label, language, configurable).
- **When it changes:** Controller1 has no signal for the input method changing; its only signal is `InputMethodGroupsChanged`. fcitx5's StatusNotifierItem (`/StatusNotifierItem`, on a connection of its own with no well-known name) sends `NewIcon` / `NewToolTip` on every switch, so the service subscribes to every item's and keeps those whose connection's process (`GetConnectionUnixProcessID`) is the `org.fcitx.Fcitx5` owner's, then reads `CurrentInputMethod` again. `InputMethodGroupsChanged` reads everything again, the installed list too.
- **`current` is `""`** while no text field had focus yet: fcitx5's current input method is the most recent input context's. The shell takes the list's first then.
- **Switch:** `SetCurrentIM`.
- **Push:** `SetInputMethodGroupInfo(<current group>, defaultLayout, items)`, then `Save`.
- **Options:** `SetConfig`, which loads a partial config over the rest: `fcitx://config/global` `Behavior/ShareInputState` (`No` / `All` / `Program`) and `Behavior/ShowInputMethodInformation`; `fcitx://config/addon/classicui` `Vertical Candidate List` and `Font`. fcitx5 writes booleans as `True` / `False`.

### ibus
`org.freedesktop.IBus` at `/org/freedesktop/IBus` on its own bus.
- **Read:** the `Engines` property (installed), `ActiveEngines` (the list) and `GlobalEngine` (current; an error, read as `""`, when there is none). Each is a serialized `IBusEngineDesc`: its type name and attachments, then name, long name, description, language, license, author, icon, layout, rank, hotkeys, symbol, … (an order ibus keeps). The label is the symbol, else the language; a layout of `default` reads `""`.
- **When it changes:** every signal of its (`GlobalEngineChanged`, `RegistryChanged`, `PropertiesChanged`) reads it again.
- **Switch:** `SetGlobalEngine`.
- **Push:** the `PreloadEngines` property (applied at once; ibus refuses an engine it doesn't know), then `gsettings set org.freedesktop.ibus.general preload-engines`, which its panel and its next start read. ibus engines carry their own layouts, so `defaultLayout` and the items' layouts aren't used.
- **Options:** only the font (`org.freedesktop.ibus.panel` `custom-font`, and `use-custom-font`; an empty font turns it off). ibus has no equivalent of the others.
- gsettings runs as a process with its arguments, no shell, the value in GVariant's text form (`['xkb:us::eng', 'mozc-jp']`).

### Outside edits
The service remembers the list it pushed last (in memory, for the daemon's life). Whenever the list read differs from it (fcitx5: the default layout, names and layouts; ibus: the names), `outsideEdit` is true: fcitx5-configtool or ibus-setup changed it. Before any push it stays false. Pushing again, or pushing the list read, clears it.

### Protocol
- **Topic `inputMethod`:** `inputMethod.state` (latest-wins), also `inputMethod.get`: `{framework, running, current, defaultLayout, group: [{name, layout}], available: [{name, label, displayName, icon, lang}], outsideEdit}`. `framework` is the one followed (`fcitx5`, `ibus`), or the one asked for while it isn't running, `""` for none.
- **`inputMethod.set {name}`:** switch (any client: switching is what a keybind does).
- **`inputMethod.push {defaultLayout, items: [{name, layout}]}`** (shell only): an empty list, an item without a name or one twice is `bad_request`.
- **`inputMethod.options {shareState?, verticalCandidates?, candidateFont?, showSwitchPopup?}`** (shell only): a key left out is left as it is.
- **`inputMethod.framework {name}`** (shell only).
- With no framework running, the writes answer `unavailable`.

### The capability
`supports.inputMethod` is whether the compositor offers `zwp_input_method_manager_v2`, the protocol fcitx5 and ibus type through on Wayland: `wayland.state`'s `inputMethod` flag. The daemon's Wayland connection only watches the global (`waylandSession`, which binds nothing), so a compositor adding or removing it later is told.

### Testing
- `inputmethod_test.go` runs a fake fcitx5 (Controller1 and its item on a second connection) and a fake ibus-daemon (on a second `dbustest` bus) through the service.
- Never push a list or `SetConfig` to the live fcitx5 or ibus: it rewrites the user's profile. Reading is safe (`busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 FullInputMethodGroupInfo s Default`).
