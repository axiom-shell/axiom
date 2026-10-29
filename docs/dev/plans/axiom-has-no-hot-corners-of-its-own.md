# axiom has no hot corners of its own

> **Issue:** [axiom has no hot corners of its own](../issues.md#axiom-has-no-hot-corners-of-its-own)
> **Status:** proposed

### Problem
The only hot corner is niri's: `Compositor.niri.hotCorner` (`config/schema/sections/Compositor.yaml`, default off) is written in managed mode as `gestures { hot-corners { off } }` (`x-compositor` `offFlag`; `manager/testdata/golden/niri/managed.kdl`), so it can only open niri's overview from the top-left, and only on niri. Hyprland 0.55 and sway 1.12 have no hot corner at all (Hyprland only through plugins). The maintainer (2026-10-29): "hot corners should be implemented (which would cause niris to work the same way (i.e. only exits if axiom sets it in managed mode (which also wouldn't even use niris corner)". Their rule for managed binds applies here as well: "Binds are exactly representative of what there is" (Phase 13 step 4). Detached and included leave niri's own corner alone, as they leave its binds alone (steps 1 and 4).

Settled already, so it's not an option here: in managed mode on niri, axiom always writes niri's corner off and never uses it, and any corner the user gets is axiom's. A user's own `user/*.kdl` turning it back on is their own config, and stays.

### Options
#### A. A trigger window per corner (recommended)
One small transparent layer-shell window per configured corner, on each screen the corner targets (`General.screensFor`), `ExclusionMode.Ignore`, anchored to two edges. It's `EdgeTrigger` (`components/hosts/popout/EdgeTrigger.qml`) shaped to a corner: hover, a dwell delay, `triggered` fired once, and armed again only after the pointer leaves. It runs a shell action. A new `HotCorners` section holds `items[]` (`corner`, `action` and its argument, `screen`, `delay`). None are set by default, so a user without corners maps no windows.
- Cost: a window and its render thread per corner per screen. That's at most 4 per monitor, against [Nineteen windows stay mapped](../issues.md#nineteen-windows-stay-mapped-on-one-monitor), and nothing until a corner is set.
- Risk: a Wayland input region can't take hover and still let clicks through, so the corner pixel or pixels stop reaching what's under them. That might be a bar widget sitting in the very corner, or a fullscreen app's corner. Kept to 1–2 px it costs little, since a corner click usually lands a few px in, but a launcher button at the top-left pixel would be pushed off it by the corner.
- The layer decides fullscreen: on `Top`, under fullscreen windows on all three compositors, a corner goes quiet in games and videos, as the bars do. On `Overlay` it works over them.
- Leaves out pressure or "push" detection (Wayland gives a client no pointer motion past the screen edge) and corners shared between two monitors, which the pointer can slide past as it does in niri.

#### B. Corners inside the windows already at the edge
Where a bar, the screen border's strip or corner, or an integrated edge menu's window already covers a corner (`BarEnds` says which bar owns it), that window watches the corner region itself. A dedicated window (A) is made only where nothing covers the corner.
- Cost: no extra window in the common case, and no stolen click: the bar gets both the hover and the click and can tell them apart.
- Risk: every edge host needs corner logic, plus a fallback for floating bars (their margin leaves the corner pixel uncovered) and for bars hidden or remade. The rule "a decision is read from the helper's output" means a new methods helper (which window owns which corner) with a test matrix. It also ties the corners to the bar and border code, which the memory phase may reshape.

#### C. The compositor's own corners where they exist
Keep niri's corner and map an axiom corner onto it in managed mode (newer niri can pick the corners and outputs, but a corner only toggles its overview). Nothing on Hyprland or sway.
- Cheapest, but it's what the maintainer ruled out ("wouldn't even use niris corner"), it isn't parity, and it offers one action.

### Recommendation
A. It works the same on every compositor, costs nothing until a corner is set, and is mostly existing pieces: `EdgeTrigger`, the bar Button's actions, the screen targeting. B's saving matters only if the stolen corner click turns out to bite. In that case it can come later as a refinement that hands a covered corner to its bar, without changing the config. On niri in managed mode the corner is always off, and `Compositor.niri.hotCorner` goes: a migration turns `true` into an axiom top-left corner running `workspaceOverlay`, which with `WorkspaceOverlay.compositorOverview` opens niri's overview as before.

Questions for the maintainer:
1. **Actions**: the bar Button's set (power menu, launcher, overlay, an overlay page, workspace overview, an edge menu, lock, a command), or every keybind action (`BindActions`, compositor-dependent, many need a focused window)? Recommended: the Button's set, lifted into one shared helper.
2. **Per-monitor**: each corner has a `screen` target (default every screen), or one set of corners for all screens? Recommended: per item, as other surfaces do.
3. **Delay**: one section-wide delay or a delay per corner, and the default? Recommended: per corner, default 0 ms (niri's corner fires at once), since a dwell mostly guards against accidental triggers.
4. **Fullscreen**: quiet over fullscreen windows (`Top`) or active over them (`Overlay`)? Recommended: quiet, as the bars are.

### Items
1. **Shell actions in one place**: the bar Button's `runAction` (`components/bar/widgets/Button/Button.qml`) moves into a shared service function (e.g. ShellManager.runAction(action, args), new) taking the action and its page, menu or command, and Button calls it. No behaviour change. *small*
2. **The `HotCorners` section and its windows**: schema section (`items[]`: `corner`, `action` with its `x-showIf` arguments, `screen`, `delay`; `x-scope` personal, `screen` machine), reader `HotCornersConfig`, shell/HotCorners.qml, new (a `Variants` over screens × items keyed by item id) with a corner trigger generalized from `EdgeTrigger`, its namespace in `LayerStack.layers`, a feature doc (features/hot-corners.md), and the settings page from the schema. *small*
3. **niri's corner off in managed mode**: the niri writer always writes `gestures.hot-corners.off` in the managed file, `Compositor.niri.hotCorner` is removed by a format-2 migration step (`true` becomes a top-left `workspaceOverlay` corner on every screen), goldens updated, and `niri-backend.md` and `schema-annotations.md` (its `offFlag` example) follow. *small*
