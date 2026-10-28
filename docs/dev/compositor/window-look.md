# Window look

> **Files:** `config/WindowLookConfig.qml`, `config/BarsConfig.qml`, `services/compositor/CompositorConfigManager.qml`, `backend/internal/compositor/manager/hypr.go`, `services/compositor/HyprlandManager.qml`, `components/views/Settings/TranslucencyStatus.qml`
> **Config:** `WindowLook.*` (borders and their colors, `shape`, `matchShell`, `borderSize`, `rounding`, gaps, `blur`, `opacity`, `windowBlur`)
> **Related:** [The compositor](README.md), [Contract](contract.md), [Config modes](config-modes.md), [Translucency and blur](../theming/translucency-blur.md), [Lockscreen](../features/lockscreen.md)

The themed window look axiom gives the compositor: borders, shape, gaps, blur and window opacity. The settings are compositor-neutral (`WindowLook`, Settings › Compositor). The daemon's `render.Look` decides the parts once; each backend's config writer turns it into its own text, in every mode ([config modes](config-modes.md)); on Hyprland that is one `hl.config`.

### What it covers
- The section is `WindowLook` (`WindowLookConfig.look`; `Hyprland.look` before config version 56). It is `x-scope: look`, so exports, examples and imports carry it. It isn't `x-takeover`.
- Each part's fields carry `x-enabledIf: { "/$supports.window<Part>": true }`, so a compositor without that part shows them greyed out with why ([schema annotations](../core/schema-annotations.md)); fields one compositor alone has also need `"/$compositor"`.
- It holds:
  - themed borders: `activeColor`/`inactiveColor` (theme color names; empty follows the theme's `borderFocus`/`border`)
  - the shape: border width and corner rounding, axiom's (`Appearance.borderWidth`/`borderRadius`) while `matchShell`, else `borderSize`/`rounding`. Hyprland's managed options held these before config version 58.
  - `WindowLookConfig` resolves both (`activeBorder`, `inactiveBorder`, `borderWidth`, `radius`), so every backend gets the same values
  - `gaps_in`/`gaps_out`
  - Hyprland's blur (`blur`: `decoration.blur.*`). Its size and passes are the one strength that windows and axiom's surfaces share.
  - the blur behind axiom's surfaces (`surfaceBlur*`, [translucency](../theming/translucency-blur.md))
  - window shadows (`shadow`, `shadowSize`, `shadowPower` on Hyprland, `shadowColor`: empty is the compositor's own) and dimming of unfocused windows (`dim`, `dimStrength`). Hyprland's managed options held these before config version 63; they now apply in every mode.
  - while `shadowMatchShell` (the default), the shadow is axiom's: Bar style's (`BarStyle.shadow`, its color as `BarsConfig.shadowBaseColor` gives it, alpha included, and `shadowSize`), spread evenly (every writer writes the offset 0 itself, which resets a user's own), as `SurfaceShadow` casts it. Bar style's shadow off casts none: the part is then off (`WindowLookConfig.shadowOn`). `WindowLookConfig` resolves it (`shadowOn`, `shadowSize`, `shadowColor`, `shadowAlpha`) and `CompositorConfigManager` sends it (`compositor.inputs`' `look.shadow`) for the daemon's `render.Look` as `opts.shadow`; the spec's color is `rrggbbaa` (and `rgb`/`alpha` apart). Matching axiom's, the spec says `soft`: it's axiom's shadow as drawn where nothing caps it (`Appearance.shadowAlphaMax` keeps the chrome's under the blur threshold; no blur reaches a window's shadow). Hyprland's shadow falls off otherwise and shows a light color over a dark background several times stronger than its alpha, so `render.SoftShadow` gives the range, power and alpha fitted on screen to look like axiom's (1.2 × its size, power 4, its alpha × 0.3 for black down to × 0.018 for a light color, by luminance); `shadowPower` is hidden then. SwayFX's and niri's are gaussians reaching about twice as far as axiom's at the same size, so `render.GaussianShadow` gives the radius and alpha fitted to axiom's glow (0.7 × its size, its alpha × 0.2 ln(size); scenefx's `box_shadow.frag` against MultiEffect, sizes 8–64). `shadowStrength` (%) scales the alpha in every case (`WindowLookConfig.shadowStrength`; the spec's `alpha` is `baseAlpha × strength`, capped at 1, and `softShadow` scales its fitted alpha); the compositor's own color (empty `shadowColor`) isn't written, so it keeps its strength.
  - window opacity (`opacity`).
- `render.Look` decides which parts are on and their values (colors, shape, gaps), the same spec every backend gets ([contract](contract.md)).
- All of it becomes one `hl.config` (`render.LookLua`, from that spec).
  - The blur and opacity fields are `x-hypr` fields, each gated by `x-hyprIf` on its part, so `configTable` writes them. The shadow and dim come from the spec (`decoration.shadow.*`, the offset as the sequence `{ 0, 0 }`: Hyprland refuses `{ x = …, y = … }` for a vec2; `dim_inactive`/`dim_strength`), as the borders do, the color resolved first (`WindowLookConfig.shadowColor`).

### Blur and windows
- With the blur part on, Hyprland's blur stays enabled while axiom's surfaces blur, even if `windowBlur` is off.
- The `axiom-no-window-blur` rule (redefined on or off) then keeps windows and their popups unblurred.
- `CompositorManager.blur` reads the blur in effect (`refreshOptions`). It is used by:
  - the Translucency card's status (`views/Settings/TranslucencyStatus`, that card's `x-intro`)
  - the lock screen's frost.

### Where it's applied
- Every part shows in every mode. A managed config writes them through `M.look()`, like the rest of the layer.
- It is a live part ([config modes](config-modes.md) › Live parts): evaluated at runtime as it changes and after every reload in the file modes, so it wins over the user's own lines while it's on, and a part turned off reloads the compositor's config (`manager.undoLive`).
- `HyprlandManager.refreshOptions()` waits for queued Lua, so `gapsOut` reads what the look set, and Automatic bars follow it.
