# Hyprland config writer

> **Files:** `backend/internal/compositor/manager/hypr.go`, `config/HyprlandConfig.qml`, `backend/internal/compositor/render/hyprconfig.go`, `backend/internal/compositor/render/hyprlua.go`, `components/methods/BindKeys.qml`, `config/InputConfig.qml`
> **Config:** `Compositor.mode`, `Compositor.requiredSettings`, `Input.*`, `Session.*`, `Keybinds.binds`, `Compositor.hyprland`, `WindowLook`, `Monitors.items`, `Workspaces.strips`
> **Related:** [Config modes](../compositor/config-modes.md), [Managed takeover](managed-takeover.md), [Window look](../compositor/window-look.md), [Bind merge](bind-merge.md), [Keybinds](keybinds.md), [Monitors](monitors.md), [Workspace strips](workspace-strips.md)

Hyprland's config writer (the daemon's `manager/hypr.go`, with its [runtime layer](../compositor/config-modes.md#the-runtime-layer), the takeover and the bind merge; its Lua from `render`'s `ModuleLua`, `ManagedLua`, `LookLua`, …): what axiom's layer is in Hyprland's Lua, for each mode. The modes themselves, leaving one and the live parts are neutral: [Config modes](../compositor/config-modes.md). Read both before touching anything axiom writes into Hyprland.

### One Lua layer
- It needs Hyprland's Lua config (0.55+). Axiom's own evals and dispatches are all Lua (`hl.*`), sent as [IPC](ipc.md) describes. The stubs are in `/usr/share/hypr/stubs/hl.meta.lua`.
- One Lua layer covers:
  - binds (`binds[]`: an IPC `action` or `exec`, `description` "Axiom: …"; see [Keybinds](keybinds.md))
  - required settings: `allow_session_lock_restore`, a named rule suppressing `maximize` requests, and a `workspaces` animation
  - the [window look](../compositor/window-look.md) and blur
  - monitor profiles ([Monitors](monitors.md))
  - strips ([Workspace strips](workspace-strips.md))
- The layer rules stacking axiom's surfaces (`render.LayerRulesLua`, from `LayerStack.layers`) are in the module's files, and in every mode the daemon also adds them at runtime: when the shell asks at its start (`compositor.layerRules`, `HyprlandManager.surfacesReady`) and on every `configreloaded` (`Manager.configReloaded`), each in its own `pcall`.

### `detached`
- It is evaluated at startup and on every `configreloaded` (the writer's runtime layer).
- It skips keys Hyprland's binds show taken (`HyprlandManager.withBinds`, read after unbinding its own). `components/methods/BindKeys` provides `keyId`, `runtimeBinds`, and `userKeyCounts` for KeybindManager.
- The keys it bound live in Hyprland's Lua state (`AXIOM_RUNTIME_KEYS`):
  - a Hyprland reload resets them, along with the binds
  - they survive a qs reload
  - they are unbound before the binds are read.
- The runtime layer starts over when Hyprland reloads while it reads the binds (`noteReload()` counts them). A plan from another config would record that config's keys in `AXIOM_RUNTIME_KEYS`, and `clear()` would then unbind them.

### `included`
- `moduleText(spec)` (`render.moduleLua`) goes to `$XDG_STATE_HOME/axiom/hyprland.lua`.
- The user loads that module with `includeLines`.

### `managed`
- `managedText(spec)` (`render.managedLua`) becomes `~/.config/hypr/hyprland.lua` itself, plus the `managed` options.
- Taking the user's existing config over (the binary's `compositor/takeover`) is described in [Managed takeover](managed-takeover.md).

### Include and autostart lines
- `includeLines` (included) and `autostartLines` (included and detached) are hookup targets:
  - `autostartLines` is one line marked `-- axiom`, like install.sh's.
  - Managed mode starts axiom itself.
  - Both start it with `startCommand`, `'<AXIOM_BIN>' run`. A second `axiom run` on the display exits at once (the instance lock), as install.sh's line does.
- The targets are `includeTarget` (at the top of hyprland.lua) and `autostartTarget` (at the end). An `axiom run` line (`Paths.startPattern`) counts as done.
- `IntegrationHookupManager` runs them under the keys `compositorInclude` (both lines) and `compositorAutostart` ([Config modes](../compositor/config-modes.md)).

### Is the file loaded?
- An `AXIOM_INCLUDED` global tells axiom the file is loaded.
- `checkLoaded` evals a check of it; when it isn't set, the runtime layer stands in and `problem` says why.

### Managed options (`render.ConfigTable`)
- The managed options (`Compositor.hyprland`) become one `hl.config({...})` through `render.ConfigTable` (pure), driven by each field's `x-compositor.hyprland` spec (`key`, `scale`, `value`, `if`, `skip`, `always`: [Schema annotations](../core/schema-annotations.md) › Compositor config).
- A field is written only when it differs from its default (Hyprland's own), so a new option is just a schema entry.
- Its cards come from `x-group`/`x-order`, and it shows only while Hyprland is the compositor and the mode is managed (`x-showIf`).
- Not mapped through annotations:
  - `animationPreset`, written after `axiom.setup()`:
    - `hyprland` writes nothing
    - `axiom` follows `Appearance.animFast/Normal/Slow` and turns animations off with motion
    - `instant` turns them off (`animations:enabled`, as `axiom` does with motion off), as on sway
    - `snappy` / `bouncy` / `lightning`
    - `custom` comes from `curves`/`customAnimations`
    - a set giving `global` but not `workspaces` gets a `workspaces` leaf like it (`animationSet`): `M.required()`'s explicit one, set before, would otherwise keep sliding, as an explicit leaf ignores its parent
  - `Session.env`: `render.SessionEnv` (as on sway): the recommended variables while `Session.recommendedEnv` is on, then the theme integrations' (`render.SessionEnv`: `QT_QPA_PLATFORMTHEME=qt5ct` while `ThemeIntegrations.qt` is on), then the cursor's `XCURSOR_*`, then the user's, which win over all of them
  - `Session.autostart`: written after axiom's in the start hook
  - the cursor (`Input.cursor`): `hyprctl setcursor` at start (its `XCURSOR_*` are in the environment above).

### Input
- `Input` (reader `InputConfig`) is in the layer in every mode, as `M.input()` after `M.look()`: one `hl.config` of the parts that are on (`render.Input`, `render.InputLua`). Its fields' `x-compositor.hyprland` specs are gated by `if` on their part's `enabled`, so a part on writes all its fields, defaults too, except a `skip` value (acceleration at `default` leaves `input.accel_profile` out).
- Like the look, it is evaluated at runtime as it changes and after every reload, and a part turned off reloads Hyprland's config ([Config modes](../compositor/config-modes.md) › Live parts).
- The cursor theme is set with `setcursor` (the daemon's config layer; the greeter's through `greeter.compositor`).
- Before config version 59 these were `managed` options (the part switches were turned on there).

### Service creation
- The daemon makes Hyprland's writer when it runs under Hyprland (`HYPRLAND_INSTANCE_SIGNATURE`).

### Testing
- Never switch the user's real config to `managed` to test it. (Rule: AGENTS.md › Never, while testing.)
- Test the takeover on scratch dirs, as `backend/internal/compositor/takeover/takeover_test.go` does.
- The Lua comes from `render` (pure): its frozen cases replay every text the JS made, and `TestCompositorsReadTheFiles` has `luac -p` read the included, managed and given-back files, and Hyprland itself (`Hyprland --verify-config`, where it's installed: not in CI) the managed file with every look and input part on, every default bind and a monitor profile, which catches an option Hyprland refuses.
