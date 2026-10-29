# Translucency and blur

> **Files:** `config/Appearance.qml`, `services/ui/BlurManager.qml`, `components/reusable/BlurRegion.qml`, `components/reusable/BoxBlurRegion.qml`, `backend/internal/compositor/render/niri.go`, `services/compositor/CompositorConfigManager.qml`, `backend/internal/compositor/manager/hypr.go`, `components/views/Settings/TranslucencyStatus.qml`, `components/surfaces/screenlayout/ScreenLayoutView.qml`
> **Config:** `Appearance.surface.opacity`, `WindowLook.surfaceBlur*` (`surfaceBlur`, `surfaceBlurThroughWindows`, `surfaceBlurBackdrops`, `surfaceBlurPauseFullscreen`)
> **Related:** [Blur window and openings](blur-window-openings.md), [Window look](../compositor/window-look.md), [Popout registry](../popouts/registry.md)

The translucency setting, how fills apply it, the Hyprland layer rules axiom writes for blur, and per-screen and fullscreen behaviour. How chrome surfaces share one blurred backing window is in [Blur window and openings](blur-window-openings.md).

### The setting
- Look & Feel → Translucency, `Appearance.surface.opacity`: 60–100%. 100 is solid and blurs nothing.
- Compositor → Window look → Blur (`WindowLook`, since config version 63): `surfaceBlur`, `surfaceBlurThroughWindows`, `surfaceBlurBackdrops`, `surfaceBlurPauseFullscreen` (`x-scope: machine`), above the compositor's own blur. Shown while the opacity isn't 100.
- **Without `supports.blur`** (plain sway) the surfaces are solid: `Appearance.surfaceAlpha` is 1 whatever the opacity says, which stays set but greyed out, as are the blur settings (`x-enabledIf`, "SwayFX can."). A translucent surface over another would show it through unblurred. `Appearance.compositorBlurs` is handed over by `CompositorManager` (a `Binding`): a reader reads no service, and building `CompositorManager` reads `Appearance` (reading it directly aborted the shell's start in a creation loop).
- The strength isn't axiom's. Hyprland has one blur, for windows and layers alike, set by the window look's blur part (Compositor → Window look, see [Window look](../compositor/window-look.md)) or the user's own config.
- The card's intro (`TranslucencyStatus`):
  - warns that transparency and blur are experimental;
  - while blurring, shows the blur in effect;
  - with the compositor's blur off (nothing blurs then), offers to set it.
- Reader properties: `Appearance.surfaceAlpha`, `compositorBlurs`, `translucent`, `blur`, `blurThroughWindows`, `blurBackdrops`, `blurThreshold` (0.5), `shadowAlphaMax`.

### Fills
- Every surface fill goes through `Appearance.fill(color)` at the shared pieces' draw sites:
  - `AttachedSurface`, `FloatingPopout`, `CornerPiece`, `BorderPanel`;
  - the bar's background and islands, the overlay's box and navigator;
  - edge menus, docks, power menu, overview, polkit and monitor prompts;
  - `StyledContainer`, `Card`/`Panel`, buttons, inputs, `ActionTile`, `DropdownSurface`.
- Outer and nested fills alike, so nested fills stack: a card on a 60% panel reads about 84%.
- Accent colors and hover tints are left alone.

### Hyprland layer rules
Written by `render.BlurLua` from `render.SurfaceBlur`'s rule groups (the ones SwayFX's `layer_effects` and niri's xray rules are written from too), handed `spec.surfaces` (`M.blur()` in the module). The named layer rules are always written, `enabled` or not, since a rule is taken back by redefining it (no reload).
- `axiom-blur`, on the namespaces that blur themselves (`LayerStack.blurSurfaces`: the blur window, the overlay, the floating launcher and switcher, …):
  - `blur_popups`, and `ignore_alpha` at the threshold. The big transparent windows need it; shadows are capped under the threshold while blurring (`BarsConfig.shadowColor`).
  - `xray` is always written, off with `surfaceBlurThroughWindows`. Left out, a layer takes `decoration.blur.xray`, which the window look turns on.
- `axiom-blur-popups`, on the chrome's own namespaces (`LayerStack.blurChrome`), for their popups alone (tooltips, the dock's menu):
  - Hyprland blurs a layer's popups whether or not the layer blurs, never with xray, and with its `ignore_alpha`. The group says `xray = false` anyway, for niri's rule (below).
  - So a bar popout, a popup drawn transparent over the blur window, blurs only under its content.
- `axiom-blur-over-overlay`, on the blur window over the overlay (`LayerStack.blurOverOverlay`): `blur`, `ignore_alpha` at the threshold, and always `xray = false`, since it blurs the overlay under it.
- `axiom-blur-backdrops`, on `axiom-backdrop` and polkit (whose window holds its dim), at any alpha.
- `axiom-blur-no-anim`: `no_anim` on `LayerStack.blurBacked`, the windows the blur window draws for, while it does.
  - They slide themselves. Hyprland fading or popping one in (its `layers`/`fade` animations, read as it maps) would leave its stroke and content behind the fill, blur and shadow drawn for it, which it doesn't animate.
- That's all it writes: the strength is Hyprland's own blur.
- The module file holds the setting as saved (`_surfacesBlur(true)`). At runtime it's `BlurManager.active`, evaluated over the file after every reload.

### niri: blur regions
niri (26.04) blurs a layer rule's whole rectangle, with no alpha threshold, so a rule would frost axiom's full-screen windows edge to edge. Instead each window sends what blurs through ext-background-effect (`supports.blurRegion`, Quickshell's `BackgroundEffect.blurRegion`):
- The blur window sends its shapes as drawn (`BlurBackingWindow.regionPieces`): an `AttachedSurface`'s fill (`blurPieces()`, from `SurfaceOutline.blurRegion`: the box out to the stroke's outer edge, its far corners rounded, each fillet's square less its circle), a rect with its radii, and the border's frame (the screen less its inner rounded rect), each placed and cut to its `clipRect` (`SurfaceOutline.placeRegion`), through `reusable/BlurRegion`.
  - Its shadows lie outside every region, so they stay in it unblurred: no `axiom-shadows` windows (`BlurBacking.shadowsApart`).
- Each surface that blurs itself (`LayerStack.blurSurfaces`: the overlay's box and navigator, floating popouts, toasts, the power menu, the workspace overview, the monitor prompt, the dock's preview) and the chrome's popups (tooltips, the dock's menu) sends its box (`reusable/BoxBlurRegion`), mapped as it slides, scales and fades: nothing while its fill's alpha (`Appearance.surfaceAlpha`, or a dim's color, × its opacity) is under `Appearance.blurThreshold`, as Hyprland's `ignore_alpha` compares each pixel's, so a fade starts and stops blurring at the same point on both.
- Backdrops and polkit's dim send their whole rect while `blurBackdrops` (at any alpha, `threshold` 0.01).
- They do while `BlurManager.regionsOn(screen)` (`backdropRegionsOn`): the pause, per screen there, never touches niri's config.
- `BackgroundEffect` is attached only where `supports.blurRegion`, from `Component.onCompleted` (`BackgroundEffect.blurRegion = Qt.binding(…)`), never as a binding: attached at all, even with a null region, Quickshell creates the window's ext-background-effect object, and Hyprland (which speaks the protocol too) then blurs only what it asks, ignoring the layer rules.
- The module holds only xray: a `layer-rule` per `render.SurfaceBlur` group that blurs or whose popups do (`render.NiriSurfaceBlurNodes`), xray off with `surfaceBlurThroughWindows`, always off over the overlay and for the chrome's popups (as Hyprland, which never blurs a popup with xray). niri marks non-xray blur experimental: it can vanish during open and close animations.
- The strength is niri's `blur {}` (the window look's blur part writes it); `NiriManager.blur` reads it back from `axiom compositor niri info` (its offset as the size) for the Translucency card and the lock screen's frost.

### No reload per step
- The window look and the blur are the layer's live part (`liveKey`, [config modes](../compositor/config-modes.md)): the daemon builds them from `WindowLook` and the facts `CompositorConfigManager` sends (`look`, `blur`).
- In every mode a change is only evaluated at runtime (`manager.applyLive`, which also runs after every reload); the file catches up on its next write. A pause or resume of the blur alone sends only the blur's lines.
- Turning a look part off rewrites the file (an eval can't take a setting back).

### Per screen
`BlurManager.backsOn(screen, onOverlay)`:
- A surface on the Overlay layer (bar popouts and submenus, edge popouts, OSDs) stays backed while the overlay is open on its screen: the blur window over the overlay draws it then (see [Blur window and openings › Over the overlay](blur-window-openings.md#over-the-overlay)).
  - It reads its host's `onOverlayLayer`, which its submenu follows (not while it slides under a bar).
- A surface on Top (bars, the border, docks, integrated menus) leaves the blur window while a fullscreen window shows there, since that fades the Top layer out.
  - The blur window itself then rises to the Overlay layer on that screen (`overFullscreen`, order 9 keeping it under the surfaces there), so what shows over a fullscreen window still blurs. Where layers stack by map order, each move lands it on top of its new layer, so the windows ordered over it there map again (`LayerManager.reportSlot`; [layer arrangement](../compositor/layer-arrangement.md)).

### Paused over fullscreen
- `surfaceBlurPauseFullscreen` (on by default): while a screen shows a fullscreen window, the blur pauses (`BlurManager.pausedOn(screen)`):
  - where the compositor's rules are compositor-wide (Hyprland's layer rules, SwayFX's `layer_effects`), on every screen: `BlurManager.paused`, and `active` is false;
    - the rules are taken back at runtime, as is Hyprland's blur where the window look kept it on for the surfaces alone (the module file keeps the saved setting);
  - where each window asks for its own blur (niri, `supports.blurRegion`), only on that screen: its windows send no region (`regionsOn`), and `active` stays on;
  - the blur window goes there (`backingOn`) and the chrome fills itself.
- On the screens showing one, surfaces fill solid (`opaqueOn`): `AttachedSurface.opaque`, `BlurManager.fillOn` for floating popouts, `StyledContainer.solid` for toasts.
- Elsewhere they stay translucent.

### Stacking
- The chrome's fills all live in the one blur window (Top, order 9), under every chrome window.
- A chrome surface that stood over another one in a higher layer (the attached launcher, an Overlay-layer edge popout, over a dock) no longer hides it with its fill: what's in between shows through.
- So popouts never overlap: what one covers gives way (see [Popout registry](../popouts/registry.md)).
- While the blur window backs surfaces, an edge popout slides out only once its window's origin is known (`LayerOrigin.settled`), so its first frames never fill and shadow themselves beside backed ones.

### Lock screen and greeter
- The greeter is never translucent: in greeter mode `Appearance.compositorBlurs` is false, so its surfaces are solid and nothing frosts ([greeter runtime](../features/greeter-runtime.md)).
- No compositor blur reaches a session-lock surface, so `ScreenLayoutView` frosts its own background under the modules while the shell blurs (`frosted`):
  - the backdrop is blurred at about Hyprland's strength (`hyprBlur`);
  - the lock surface reads it from `CompositorManager.blur`;
  - masked by the modules at the blur threshold.
- Not when the wallpaper is blurred already.
