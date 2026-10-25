# Onboarding

> **Files:** `services/session/OnboardingManager.qml`, `shell/Onboarding.qml`, `components/surfaces/onboarding/OnboardingWindow.qml`, `components/surfaces/onboarding/pages/CompositorPage.qml`, `components/surfaces/onboarding/pages/IntegrationsPage.qml`, `components/surfaces/onboarding/pages/ChecksPage.qml`, `services/core/DependencyManager.qml`, `components/methods/Packages.qml`, `components/views/Settings/OnboardingCard.qml`
> **Config:** none of its own (pages write other sections); state in `~/.local/state/axiom/ui/onboarding.json`
> **Related:** [Config modes](../compositor/config-modes.md), [Hyprland's writer](../hyprland/config-modes.md), [Monitors](../hyprland/monitors.md), [Greeter install](greeter-install.md), [Pages and grid](../overlay/pages-and-grid.md)

The first-run onboarder: a paged window that sets up the look, the compositor's config mode, monitors, apps and integrations.

### When it opens
- When there was no config.json (`ConfigManager.firstRun`, set by `_existsCheck`).
- After a restart, until the user finishes or skips it.
- State lives in `~/.local/state/axiom/ui/onboarding.json`: `{ completedVersion, step }`.
  - A config with no state file is never prompted.
  - Bump `version` when a page is worth showing to existing users.
- The step and the chosen compositor mode live in a `PersistentProperties`.

### Window
- `shell/Onboarding` → `surfaces/onboarding/OnboardingWindow`, with pages in `onboarding/pages/`.
- The window is a `hosts/overlay/ReservedAreaWindow`, like the overlay's.
- It uses the same `OverlayGrid` and draws its pages at its `zoom`, so the Welcome page's `Widget.cardSize` and `Widget.scale` settings show on it.
- Its pages shrink as much as the overlay's first page does there (`GridPlacement.fitScale`). Cards therefore show at the overlay's real size, even on a screen too small for it.
- The step bar is the overlay's `OverlayPageNavigator`.

### Applying
- Pages apply as the user goes:
  - `SettingsManager.commitValues({ dottedPath: value })`; or
  - `forms/SettingRows`, which shows config paths as `SchemaField` rows and saves them debounced.
- Only the compositor mode waits for Finish.

### Compositor page
- Shown wherever axiom can set the compositor up (`supports.configModes`: Hyprland, sway). Its paths and names are the config writer's (`CompositorConfigManager.managedPath`, `userDir`) and `CompositorManager.displayName`, so nothing on it is one compositor's; `detectCompositor()` reads it all.
- **`configState`:** `none` | `stock` | `custom` | `ours` | `blocked` | `legacy`. It comes from `checkManaged()`, plus on Hyprland a `hyprland.conf` check (`legacy`) and its version (`hyprlandSupported`: 0.55+; `compositorSupported` is false only for an older Hyprland, and Finish then leaves the mode).
- Where another build of the compositor can do more (plain sway: SwayFX), a notice says so (the backend's `unsupportedHint`).
- **The three modes** are always shown, with `OptionCard.tag`:
  - `managed`: Recommended
  - `included`: For complex setups
  - `detached`: For testing
- **Starting mode:** the page starts on `recommendedMode` (`chosenMode` falls back to it): the current `Compositor.mode` when it isn't `detached` (run again, Finish keeps it; FinishPage warns when a pick changes it), else
  - `managed` for the compositor's example config (`stock`), for no config (`none`), or for axiom's own (`ours`);
  - `detached` for any config of the user's (`custom`, `legacy`, `blocked`), which it then leaves alone.
- A blocked managed card says why (`blockedReason`).
- **Hookups:** for included and detached it shows `forms/IntegrationHookup` for `compositorInclude` / `compositorAutostart` (copy, or Apply after a backup).
  - `includeDone` / `autostartDone` drop the "won't start axiom" warnings, both there and on Finish.
- See [Config modes](../compositor/config-modes.md).

### Monitors
- On a first run with a stock or missing config, `MonitorManager.useWholeScale()` saves a layout with every fractional scale rounded down to a whole one (`MonitorLayout.wholeScaleRules`).
  - The example config's `scale = "auto"` is often 1.25 or 1.5.
  - A scale of 2 stays, so a HiDPI panel stays readable.
- It doesn't do this if a layout is already saved, or if no scale is fractional.
- See [Monitors](../hyprland/monitors.md).

### Other pages
- It reuses the Monitors view, `WallpaperPicker` and `ThemePicker` as they are.
- The Look page's folder check, create and open are `WallpaperManager.checkFolder()` / `folderImages` / `createFolder()` / `openFolder()`.
- `DependencyManager.check(commands)` / `found` / `tools` say what's installed. Calls made together are batched into one `deps.check` to axiom (`backend/internal/deps`: `$PATH` through `exec.LookPath`), and without axiom the commands stay unknown. A `py:<module>` key (`py:numpy`, `py:icalendar`) is a Python module, looked up with python3's `importlib` (one python3 run for all of them); `DependencyManager.label` shows it as `python: <module>`. Python modules come from the distribution's own packages (no venv, no pip).
- The Apps page shows the main modifier and the keys to know only where axiom binds keys (`CompositorManager.supports.keybinds`); elsewhere it's just the apps.
- The Integrations page, top to bottom: updates, clipboard history, [Idle](idle.md), the lock screen, [Polkit](polkit.md), the login screen, then theme integrations.
  - Idle, the lock screen, polkit and the login screen are `OptionCard` choices. The lock screen has two (`Lockscreen.mode`): axiom's, or your own.
  - The login screen (`forms/GreeterSetup`, see [Greeter install](greeter-install.md)) is set up only from its Install button.
  - Theme integrations come last: they're optional and need no decision.

### Package hints
- `DependencyManager.distro` is `Packages.distroFamily` of `/etc/os-release`: `arch`, `fedora`, or `""` (unknown).
- `Packages.packages` names each command's package per distribution: a name, `{ name, repo }` (Fedora's Hyprland tools come from the `nett00n/hyprland` COPR), `{ file, to }` (the icon font on Fedora, downloaded), or `null` (nothing to install there; that `DependencyManager.tools` row is hidden, e.g. `checkupdates` off Arch). A row with `compositors` shows only under those (`CompositorManager.kind`): night light's tool, and the X11 helper niri and sway need (`xwayland-satellite`, `Xwayland`). A row with `alternatives` counts as installed when any of them is (`DependencyManager.toolFound`, `toolCommand` names the one found): the login screen's compositor, `sway` or Hyprland's `start-hyprland`; missing, it offers its own command (sway).
- `DependencyManager.installLines(keys)` / `installCommand(key)` give the shell lines: COPRs to enable, one install, then downloads. On an unknown distribution they're empty and the Checks page lists names only.
- The same commands serve Settings' hints (Idle, Night light, Login screen) and the missing icon font notification. A distribution without names gets the text only, no command.
- `Packages.distros.<family>.updates` is how the Updates widget checks and upgrades there (`UpdatesManager.backend`); `"/$distro": "arch"` in an `x-showIf` hides the AUR options elsewhere.
- **Adding a distribution:** one column in every `Packages.packages` entry (`tst_Packages` fails on a missing one), one `Packages.distros` entry (with `updates`, and a format in `backend/internal/updates` if its output is new), and test rows; then install.sh's column for it ([packaging.md](../packaging.md): `check_packages.py` compares the two).

### Entry points
- IPC `onboarding`:
  - `open`, `close`;
  - `reset`, which opens it at the next start;
  - `goTo <step>`.
- Launcher `/welcome`.
- Settings → General's `OnboardingCard`.

### Testing
- Use `ipc call onboarding goTo <n>` plus grim screenshots.
- Never delete the real config.json to test it. (Rule: AGENTS.md › Never, while testing.)
