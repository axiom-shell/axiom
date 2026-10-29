# Surfaces touch a dead screen after the outputs go away

> **Issue:** [Surfaces touch a dead screen after the outputs go away](../issues.md#surfaces-touch-a-dead-screen-after-the-outputs-go-away)
> **Status:** proposed

### Problem
Reproduced in nested sway (`scripts/dev/nested.sh sway`, default config, one output `WL-1`) by `swaymsg output WL-1 disable` / `enable`. Each disable logs `qt.qpa.wayland` `There are no outputs - creating placeholder screen`, then 5 to 38 `attempted to use dangling screen object` in one burst (same millisecond), then `@shell/WindowSwitcher.qml[38:-1]: TypeError: Cannot read property 'name' of null`. Enabling the output again logs nothing.

**How it happens** (Quickshell 0.3.2, `src/core/qmlscreen.cpp`, `qmlglobal.cpp`, `variants.cpp`):
1. Qt emits `screenRemoved`; Quickshell's `updateScreens` drops the `ShellScreen` from `Quickshell.screens` and `deleteLater()`s it. `General.outputs` and every `Variants` over it update at once, and Variants `deleteLater()`s the delegates for that screen.
2. Qt then deletes the `QScreen` in the same call. The `ShellScreen` turns dangling: every getter (`name`, `width`, …) warns and returns a fallback (`"{ NULL SCREEN }"`, 0).
3. Until the event loop reaches those deferred deletes, the dying delegates' bindings are live. Any binding that mixes a screen read with something else that changes then (the compositor reports its output gone: `CompositorManager.outputs`, windows, fullscreen; `BrightnessManager` rescans) re-evaluates and reads the dead screen: one warning per read. Whether the compositor's event lands before the deletes is a race, so the count varies.
4. When the `ShellScreen` is finally deleted, properties typed `ShellScreen` turn null; a binding that reads `.name` without `?.` throws (the WindowSwitcher line).

No getter returns wrong data that matters (the delegate is about to go), so this is log noise plus one thrown binding, on a path every user with DPMS or a monitor switched off takes.

**Which surfaces.** With `shell.qml` cut down to one surface at a time (a scratch copy of the tree, two disable/enable cycles each): `OSD` 11 warnings; `WorkspaceOverlay` 31 in one run, 0 in the next (the race); every other surface 0, though the nested default config has no dock, edge menus or second bar, so those weren't tried with content. No surfaces at all: 0. The reads on those paths:
- `shell/OSD.qml`: `claimKey` (`modelData?.name`), `OSDContent.screenName` (`edgeHost.screen?.name`); through `components/hosts/popout/EdgePopout.qml` (kept loaded for the OSD): `fullscreen` (`CompositorManager.hasFullscreen(root.screen?.name …)`), `attachBase`, `overlayOpen`, and the services handed `root.screen` that read `.name` themselves (`ScreenEdgeManager.reservedWithMenusOn`, `SurfaceManager.surfaceOpenOn`, `BlurManager.backingOn`).
- `shell/WorkspaceOverlay.qml`: `shown` (`modelData.name === root.openScreen`), `BackdropRequest._request` (`root.screen.name`), and `components/surfaces/workspaces/OverviewGrid.qml`: `monitor` (`CompositorManager.outputFor(root.screen)`, re-run on every `outputs` change), `monitorW`/`monitorH`, the wallpaper and strip direction.
- `shell/WindowSwitcher.qml`: `claimKey: "switcher:" + host.modelData.name` (the TypeError).

The live session's 68 lines come from more of the same: more monitors, bars and popouts. Across `shell/`, `components/` and `services/` there are about 190 `screen.name` / `modelData.width`-style reads; the ones that warn are those whose binding also depends on something that changes as the output goes.

`ShellScreen.name` is `CONSTANT`: a binding reading only `screen.name` never re-runs on its own. That is what the options build on.

### Options
#### A. Leave it logged, ask upstream
No change here. Quickshell could delete Variants delegates synchronously, or delete the `ShellScreen` before its `QScreen` goes, and every surface would be quiet at once. Costs nothing in axiom; the log stays noisy (Phase 8's "Done means" isn't met) and the WindowSwitcher TypeError stays until upstream moves, which we don't control. The maintainer would raise it upstream; agents don't.

#### B. Read the name once in the surfaces that warn
Each host reads its screen's name in one property that depends on nothing else (`readonly property string screenName: root.screen?.name ?? ""`: re-runs only if `screen` itself changes, and gives `""` once it's null), and every other binding uses that string: `CompositorManager.hasFullscreen(root.screenName)`, `output(screenName)`, `claimKey`, `BackdropRequest`'s request. Services taking a screen take its name where they only need the name. Size from the window (`width`/`height` of the PanelWindow) or `CompositorManager.output(name)` instead of `screen.width`. `PanelWindow.screen` keeps the `ShellScreen` (setting it to null would move the window onto Qt's placeholder, which `General.outputs` exists to avoid). About 60–100 lines over `EdgePopout`, `OSD`, `WorkspaceOverlay`, `OverviewGrid`, `BackdropRequest`, `WindowSwitcher`; EdgePopout is shared, so the dock and edge menus get it too. Leaves whatever warns on a setup the nested default didn't exercise until someone sees it.

#### C. Sweep every screen read, with a check
Option B everywhere: every service function that takes a `ShellScreen` takes a name, every host reads the name once, and `check_structure` refuses `screen.<prop>` / `modelData.<prop>` in a binding other than the one `screenName` line. Clean by construction, but it touches about 190 reads in dozens of files (well past the rare-path cap of about 150 lines, so several PRs), mostly bindings that can never warn, and the check can't see reads made inside a service from an object passed in.

### Recommendation
B. It fixes everything the repro showed, the WindowSwitcher error included, in well under 150 lines, adds no mechanism (one string property per host, and fewer reads overall), and the pattern is one line in `qml-pitfalls.md` for the next case. C's sweep is mostly churn on reads that can't warn; A leaves the row's goal to someone else. B is untested against a fixed tree: the repro (nested sway, `swaymsg output WL-1 disable`) is how each item checks itself, and item 4 re-reads the live log after a real monitor-off.

### Items
1. **WindowSwitcher's null screen:** `shell/WindowSwitcher.qml`'s delegate reads its name once (`screenName`) for `wanted` and `claimKey`, and the strip's width from the window. Trivial.
2. **EdgePopout and the OSD read the screen's name once:** `EdgePopout.screenName` used for `fullscreen`, the claim, the backing region and `OSDContent.screenName`; `ScreenEdgeManager.reservedWithMenusOn`, `SurfaceManager.surfaceOpenOn`, `BlurManager.backingOn` called with names where they only use the name (their callers updated); `shell/OSD.qml`'s `claimKey` from it. Small.
3. **The workspace overview reads the screen's name once:** `WorkspaceOverlay`'s `shown`, `BackdropRequest` (takes a `screenName`), `OverviewGrid` (`monitor` from `CompositorManager.output(name)`, its size from the output or the window). Small.
4. **Re-measure and document:** after 1–3, disable/enable the nested output with a second bar, a dock and an edge menu configured, and read the live log after a real monitor-off; any surface still warning gets the same one-line change or an issues.md entry. Add the rule to `docs/dev/core/qml-pitfalls.md` (a binding never reads a `ShellScreen`'s properties next to a changing dependency; read `name` once). Trivial.
