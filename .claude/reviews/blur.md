# blur
reviewed: b85084b 2026-10-30  (full)

Sound at its core. One rule table feeds all three backends, and pausing and translucency off stop blur everywhere. Open problems are in the fills (a backed toast's double alpha, the keepFill row, SwayFX's popups), plus about 95 lines of deletions.

## Open findings
- Major: [A backed toast's blur fill is at the surface opacity twice](../../docs/dev/issues.md#a-backed-toasts-blur-fill-is-at-the-surface-opacity-twice)
- Major: [A keepFill opening leaves an unfilled row in an unbacked translucent pill](../../docs/dev/issues.md#a-keepfill-opening-leaves-an-unfilled-row-in-an-unbacked-translucent-pill)
- Major: [SwayFX leaves tooltips and the dock's menu translucent and unblurred](../../docs/dev/issues.md#swayfx-leaves-tooltips-and-the-docks-menu-translucent-and-unblurred)
- Cleanup: [SlideAnimation's fade, easing and container aliases are dead](../../docs/dev/issues.md#slideanimations-fade-easing-and-container-aliases-are-dead)
- Cleanup: [The blur window builds stand-ins and copies it never uses](../../docs/dev/issues.md#the-blur-window-builds-stand-ins-and-copies-it-never-uses)
- Cleanup: [BlurBacking spells out four near-identical blur windows](../../docs/dev/issues.md#blurbacking-spells-out-four-near-identical-blur-windows)
- Cleanup: [The border frame's path is built three times](../../docs/dev/issues.md#the-border-frames-path-is-built-three-times)
- Cleanup: [Small shrinks in the blur system](../../docs/dev/issues.md#small-shrinks-in-the-blur-system)

### Minor (report only, not recorded)
- `OutsideShadow.reach` and `AttachedSurface.shadowReach` duplicate `Math.ceil(size * 1.25)`.
- `shadows.md:64` says unbacked surfaces are opaque; only screens with a fullscreen window are.
- `translucency-blur.md`: flat `surfaceBlur*` key names; all four marked `x-scope: machine` (only `pauseFullscreen` is); `_surfacesBlur(true)` doesn't exist.
- `ScreenLayoutView.qml:132`: a stale comment about the greeter's `hyprBlur`.
- `tst_SurfaceContext`: no `layout` row checks `.shadow`.
- `systems.md` › blur: Extra lacks `render/layer.go`, `render/hyprlua.go`, `render/sway.go` and `methods/LayerStack.qml`.

## Contract
Holds:
- One `render.SurfaceBlur` table, rendered by `BlurLua`, `SwaySurfaceBlurLines` and `NiriSurfaceBlurNodes`, with namespaces from `LayerStack`.
- Every `blurSurfaces` namespace, backdrop and chrome popup sends its region on niri.
- `BackgroundEffect` is attached only where `supports.blurRegion`, from `onCompleted`, at eleven sites.
- Pause: compositor-wide on Hyprland and SwayFX (`BlurFacts.Now`), per screen on niri. Translucency 100, no `supports.blur` and the greeter turn everything off.
- `backsOn`, `overFullscreen`, `aboveOverlay` and `opaqueOn` work as documented; the over-overlay window is cut by the window below it.
- The keyed copies and `FrameNudge`; the `LayerOrigin`, `BorderOpening` and `StrokeOpening` guards.
- `AttachedSurface._fill` equals `fillOn`; `shadowReach` doesn't depend on `backed`.
- The Go blur cases and `tst_SurfaceContext` pass.

## Coverage
Read deeply: all 25 scoped files' blur parts, plus `render/layer.go`, `hyprlua.go`, `sway.go`, `manager/inputs.go` and every `BackgroundEffect` site. Outlined: the non-blur parts of `AttachedSurface`, `BarContainer`, `SurfaceContext` and `CompositorConfigManager`. Unsettled: the keepFill row (needs a nested screenshot), and whether niri animates layer surfaces.

## History
- 2026-10-30 full: 14 findings (3 Major, 5 Cleanups, 6 Minor); recorded
