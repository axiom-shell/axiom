# Translucency and blur

> **Files:** `qml/config/Appearance.qml`, `qml/services/ui/WallpaperToneManager.qml`, `qml/services/ui/BlurManager.qml`, `qml/components/reusable/BlurRegion.qml`, `qml/components/reusable/BoxBlurRegion.qml`, `backend/internal/compositor/render/niri.go`, `qml/services/compositor/CompositorConfigManager.qml`, `backend/internal/compositor/manager/hypr.go`, `qml/components/views/Settings/TranslucencyStatus.qml`, `qml/components/surfaces/screenlayout/ScreenLayoutView.qml`
> **Config:** `Appearance.surface.opacity`, `Appearance.surface.blur` (`enabled`, `throughWindows`, `backdrops`, `pauseFullscreen`)
> **Related:** [Blur window and openings](blur-window-openings.md), [Window look](../compositor/window-look.md), [Popout registry](../popouts/registry.md)

The translucency setting, how fills apply it, the Hyprland layer rules axiom writes for blur, and per-screen and fullscreen behaviour. How chrome surfaces share one blurred backing window is in [Blur window and openings](blur-window-openings.md).

### The setting
- Look & Feel → Translucency, `Appearance.surface.opacity`: 60–100%. 100 is solid and blurs nothing.
- Appearance → Translucency → Blur (`Appearance.surface.blur`, from `WindowLook.surfaceBlur` before config version 105): `enabled`, `throughWindows`, `backdrops`, `pauseFullscreen` (`x-scope: machine`). Shown while the opacity isn't 100.
- **Without `supports.blur`** (plain sway) the surfaces are solid: `Appearance.surfaceAlpha` is 1 whatever the opacity says, which stays set but greyed out, as are the blur settings (`x-hintedIf`, "SwayFX can."). A translucent surface over another would show it through unblurred. `Appearance.compositorBlurs` is handed over by `CompositorManager` (a `Binding`): a reader reads no service, and building `CompositorManager` reads `Appearance` (reading it directly aborted the shell's start in a creation loop).
- The strength isn't axiom's. Hyprland has one blur, for windows and layers alike, set by the window look's blur part (Compositor → Window look, see [Window look](../compositor/window-look.md)) or the user's own config.
- The card's intro (`TranslucencyStatus`):
  - warns that transparency and blur are experimental;
  - while blurring, shows the blur in effect;
  - with the compositor's blur off (nothing blurs then), offers to set it.
- Reader properties: `Appearance.surfaceAlpha`, `compositorBlurs`, `translucent`, `blur`, `blurThroughWindows`, `blurBackdrops`, `blurThreshold` (0.5), `shadowAlphaMax`.

### Fills
- The edge family (`AttachedSurface`, `CornerPiece`, `BorderPanel`, the bar, edge menus, docks, toasts) draws at `Style._edgeAlpha` (the user's opacity, raised to the wallpaper's edge floor, below) through `Style.edgeFill(color, opaque)`; every other surface (`Surface`: the overlay's box and navigator, cards, prompts, pickers, power menu, overview, lock and greeter cards) at `Style.surfaceAlpha` (floored, D-50 as narrowed by Q-8b).
- Outer and nested fills alike, so nested fills stack: a card on a 60% panel reads about 84%.
- Accent colors and hover tints are left alone.

### The edge floor from the wallpaper
Below 100 % `Style._edgeAlpha` is `max(Appearance.surfaceAlpha, Appearance.wallpaperEdgeFloor)`: the least alpha at which the bars' text colour reads (4.5 plus the readability margin) over the wallpapers under every non-transparent bar, taken once for every screen and the whole edge family, so surfaces that join never differ. `WallpaperToneManager` computes it from config geometry (`BarsConfig.expandBars`, the band each bar covers: `Backdrop.band`), never from the drawn bars, which read it back (a binding loop), and hands it to `Appearance` through a `Binding`. It is 0 until the daemon's grid arrives (`theme.backdrop`, [Themes](themes.md)), and it glides (`Appearance.animSlow`) when it changes, so a new wallpaper never steps every edge surface at once (bars compute their content colours for the settled floor, so the glide re-enriches no bar). A bar with no surface gets a shade or an adapting ink instead (`BarEnrich.backdropOf`, [Bar widget style](../bar/widget-style.md)). The floor applies to bars over a compositor that blurs, as the opacity setting does. `Appearance.wallpaperEdgeTarget` is the same floor unglided (`Style.edgeAlphaSettled`): what the bars judge their content colours against, so the glide never re-enriches a bar each frame.

### Style's floor
`Style.surfaceAlpha` is `Appearance.surfaceAlpha` raised to the theme's readability floor (the least alpha at which `text` on the page and on a card, over the opposite pole of the wallpaper, reaches 3.0; none at 100 %), and `Style.fill*` are the roles at it ([Style](../core/style.md) › Translucency). The edge family has its own floor from the wallpaper (above).

### Hyprland layer rules
Written by `render.BlurLua` from `render.SurfaceBlur`'s rule groups (the ones SwayFX's `layer_effects` and niri's xray rules are written from too), handed `spec.surfaces` (`M.blur()` in the module). The named layer rules are always written, `enabled` or not, since a rule is taken back by redefining it (no reload).
- `axiom-blur`, on the namespaces that blur themselves (`LayerStack.blurSurfaces`: the blur window, the floating launcher and switcher, …):
  - `blur_popups`, and `ignore_alpha` at the threshold. The big transparent windows need it; shadows are capped under the threshold while blurring (`Style.shadowColor`).
  - `xray` is always written, off with `blur.throughWindows`. Left out, a layer takes `decoration.blur.xray`, which the window look turns on.
- `axiom-blur-reduced`, on `LayerStack.blurReduced` (the overlay): `axiom-blur`'s fields, `on` false while `spec.surfaces.reduced` (`BlurManager.reduced`: `Overlay.reduceFullscreen` over a fullscreen window, below). Its own row, so SwayFX has a `blur disable` line to take the blur back.
- `axiom-blur-popups`, on the chrome's own namespaces (`LayerStack.blurChrome`), for their popups alone (tooltips, the dock's menu):
  - Hyprland blurs a layer's popups whether or not the layer blurs, never with xray, and with its `ignore_alpha`. The group says `xray = false` anyway, for niri's rule (below).
  - So a bar popout, a popup drawn transparent over the blur window, blurs only under its content.
- `axiom-blur-backdrops`, on `axiom-backdrop` and polkit (whose window holds its dim), at any alpha.
- Not a blur rule: `LayerStack.layers`' `noAnim` (`no_anim`, one layer rule per namespace, `render.LayerRules`, with the rule's `order`) is on every chrome namespace in every mode: the chrome slides itself.
- That's all it writes: the strength is Hyprland's own blur.
- The module file holds the setting as saved (`_surfacesBlur(true)`). At runtime it's `BlurManager.active`, evaluated over the file after every reload.

### niri: blur regions
niri (26.04) blurs a layer rule's whole rectangle, with no alpha threshold, so a rule would frost axiom's full-screen windows edge to edge. Instead each window sends what blurs through ext-background-effect (`supports.blurRegion`, Quickshell's `BackgroundEffect.blurRegion`):
- The backing window sends its shapes as drawn (`BlurBackingWindow.regionPieces`): an `AttachedSurface`'s fill (`blurPieces()`, from `SurfaceOutline.blurRegion`: the box out to the stroke's outer edge, its far corners rounded, each fillet's square less its circle), a rect with its radii, and the border's frame (`blurPieces(w, h)`, from `FrameOutline.blurRegion`: the screen less its inner rounded rect), each placed and cut to its `clipRect` (`SurfaceOutline.placeRegion`), through `reusable/BlurRegion`; a shape fading (an `AttachedSurface`'s `shownOpacity`, `hostOpacity`: a detached box's Fade, a fading dock hidden; a `BlurShape`'s `color` alpha: a toast fading; an attached shape's is its surface's `fillColor`) sends none while its fill is under `Appearance.blurThreshold`, as `BoxBlurRegion` does.
  - Its shadows lie outside every region, so they stay in it unblurred: no `axiom-shadows` windows (`BlurManager.shadowsApart`).
- Each surface that blurs itself (`LayerStack.blurSurfaces` and `blurReduced`: the overlay's box and navigator, the power menu, the workspace overview, the monitor prompt, the dock's preview) and the chrome's popups (tooltips, the dock's menu) sends its box (`reusable/BoxBlurRegion`), mapped as it slides, scales and fades: nothing while its fill's alpha (`Appearance.surfaceAlpha`, or a dim's color, × its opacity) is under `Appearance.blurThreshold`, as Hyprland's `ignore_alpha` compares each pixel's, so a fade starts and stops blurring at the same point on both.
- Backdrops and polkit's dim send their whole rect while `blurBackdrops` (at any alpha, `threshold` 0.01).
- They do while `BlurManager.regionsOn(screen)` (`backdropRegionsOn`): the pause, per screen there, never touches niri's config.
- `BackgroundEffect` is attached only where `supports.blurRegion`, from `Component.onCompleted` (`BackgroundEffect.blurRegion = Qt.binding(…)`), never as a binding: attached at all, even with a null region, Quickshell creates the window's ext-background-effect object, and Hyprland (which speaks the protocol too) then blurs only what it asks, ignoring the layer rules.
- The module holds only xray: a `layer-rule` per `render.SurfaceBlur` group that blurs or whose popups do (`render.NiriSurfaceBlurNodes`), xray off with `blur.throughWindows`, and always off for the chrome's popups (as Hyprland, which never blurs a popup with xray). niri marks non-xray blur experimental: it can vanish during open and close animations.
- The strength is niri's `blur {}` (the window look's blur part writes it); `NiriManager.blur` reads it back from `axiom compositor niri info` (its offset as the size) for the Translucency card and the lock screen's frost.

### No reload per step
- The window look and the blur are the layer's live part (`liveKey`, [config modes](../compositor/config-modes.md)): the daemon builds them from `WindowLook` and the facts `CompositorConfigManager` sends (`look`, `blur`).
- In every mode a change is only evaluated at runtime (`manager.applyLive`, which also runs after every reload); the file catches up on its next write. A pause or resume of the blur alone sends only the blur's lines.
- Turning a look part off rewrites the file (an eval can't take a setting back).

### Per screen
Every mode is backed: `BlurManager.backingOn(screen)` follows the backing window's slot (`LayerManager.slotOn`: true while the layer service shows it), so chrome draws its own fill whenever that window isn't shown (e.g. while it maps again on sway), and the backing window draws the chrome opaque, translucent with the blur off, and blurred, on every compositor (plain sway too, where it only holds its place under the bars), and the compositor blurs it only where `active`/`regionsOn`. `shadowsApart` stays capability-only: on SwayFX the shadow windows exist with the blur off too.

`BlurManager.backsOn(screen, onOverlay)`:
- A surface on the Overlay layer (bar popouts and submenus, edge popouts, OSDs) stays backed while the overlay is open on its screen: the one backing window draws it, over the overlay's page (which is under the backing window, LayerStack).
  - It reads its host's `onOverlayLayer`, which its submenu follows (true for bar and edge popouts; false for a free menu, whose window is on Top).
- BlurManager's fullscreen reads (backing, pause, reduce, opaque) are the layer pass's (`LayerManager.hasFullscreen`), so a surface's handover to the backing window and that window's move to Overlay happen in one turn and the move rides its first frame (a frame drawn on Top in between would never be followed by another: no frame callback under a fullscreen window).
- A surface on Top (bars, the border, docks, integrated menus) leaves the backing window while a fullscreen window shows there, since that fades the Top layer out.
  - The backing window itself then rises to the Overlay layer on that screen (its row's `overFullscreen: "always"`, order 9 keeping it under the surfaces there, after the overlay's page), so what shows over a fullscreen window still blurs. Where layers stack by map order, each move lands it on top of its new layer, so the windows ordered over it there map again (`LayerManager`'s sequence pass; [layer arrangement](../compositor/layer-arrangement.md)).

### Paused over fullscreen
- `blur.pauseFullscreen` (on by default): while a screen shows a fullscreen window, the blur pauses (`BlurManager.pausedOn(screen)`):
  - where the compositor's rules are compositor-wide (Hyprland's layer rules, SwayFX's `layer_effects`), on every screen: `BlurManager.paused`, and `active` is false;
    - the rules are taken back at runtime, as is Hyprland's blur where the window look kept it on for the surfaces alone (the module file keeps the saved setting);
  - where each window asks for its own blur (niri, `supports.blurRegion`), only on that screen: its windows send no region (`regionsOn`), and `active` stays on;
  - the backing window keeps drawing the chrome (`backingOn`), and the compositor blurs nothing there.
- On the screens showing one, surfaces fill solid (`opaqueOn`): the backing window draws them with the solid fill (`BlurManager.fillOn`, `Style.edgeFill`); `AttachedSurface.opaque` is the unbacked fallback's.
- Elsewhere they stay translucent.
- `Overlay.reduceFullscreen` leaves the overlay unblurred over a fullscreen window the way the pause does, as a second subject of it: `BlurManager.reduced` (compositor-wide where the rules are: the `axiom-blur-reduced` rule's `on`, via the `blur` fact's `reduced`, live only: the file keeps the setting as saved) and `reducedOn(screen)` (per screen where each window asks: the overlay's niri region), live with the fullscreen window, no namespace change. Its look (motion, shadow) stays the overlay's own ([pages and grid](../overlay/pages-and-grid.md)); the blur windows, toasts and OSD keep their blur.

### Stacking
- The chrome's fills all live in the one backing window (Top, order 9), under every chrome window.
- A chrome surface that stood over another one in a higher layer (the attached launcher, an Overlay-layer edge popout, over a dock) no longer hides it with its fill: what's in between shows through.
- So popouts never overlap: what one covers gives way (see [Popout registry](../popouts/registry.md)).
- While the backing window backs surfaces, an edge popout or a free menu slides out only once its window's origin is known (`LayerOrigin.settled`), so its first frames never fill and shadow themselves beside backed ones. The integrated edge menu takes no such wait: its window is placed before its first frame is drawn (`origin !== null` in its `backed`).

### Lock screen and greeter
- The greeter is never translucent: in greeter mode `Appearance.compositorBlurs` is false, so its surfaces are solid and nothing frosts ([greeter runtime](../features/greeter-runtime.md)).
- No compositor blur reaches a session-lock surface, so `ScreenLayoutView` frosts its own background under the modules while the shell blurs (`frosted`):
  - the backdrop is blurred at about Hyprland's strength (`hyprBlur`);
  - the lock surface reads it from `CompositorManager.blur`;
  - masked by the modules at the blur threshold.
- Not when the wallpaper is blurred already: over a blurred wallpaper lock cards don't frost, whatever its strength, and show it at the Blur strength set.
