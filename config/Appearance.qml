pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Appearance section. Values are always present: schema
// defaults are filled in by ConfigManager at load time.
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Appearance

  // --- Theme (UI-owned, set on the overlay's Themes page) ---
  readonly property string theme: _c.theme.name
  // From the active theme, not config: a theme is dark or light
  readonly property bool darkMode: ThemeManager.currentTheme.variant !== "light"
  // The wallpapers picked by hand (fixed mode): the primary monitor's, the
  // fallback for monitors without their own, and monitor name -> URL, set
  // per monitor on the Themes page. What's showing (rotated, light/dark)
  // is ThemeManager.wallpaperFor(monitor).
  readonly property string fixedWallpaper: _c.wallpaper.file
  readonly property var fixedWallpapers: _c.wallpaper.perScreen
  // As configured (for display), and with ~ expanded, no trailing slash
  // "quickshell" (shell/Wallpaper draws it) | "awww" (setWallpaper.sh)
  readonly property string wallpaperBackend: _c.wallpaper.backend
  // Start awww's daemon for the awww backend (WallpaperManager)
  readonly property bool wallpaperDaemon: _c.wallpaper.daemon
  readonly property string wallpaperFolder: _c.wallpaper.folder
  readonly property string wallpaperPath: Paths.expandHome(_c.wallpaper.folder)
  // "fixed" | "rotate" (wallpaperRotation) | "variant" (variantWallpapers),
  // driven by WallpaperManager
  readonly property string wallpaperMode: _c.wallpaper.mode
  // How often it rotates (ms)
  readonly property int rotationInterval: _c.wallpaper.rotation.interval
  // "random" | "sequential"
  readonly property string rotationOrder: _c.wallpaper.rotation.order
  readonly property bool rotationSameOnAll: _c.wallpaper.rotation.sameOnAll
  // { dark, light }: file URLs, "" for none
  readonly property string darkWallpaper: _c.wallpaper.variants.dark
  readonly property string lightWallpaper: _c.wallpaper.variants.light

  // --- Light/dark by time of day (WallpaperManager) ---
  readonly property bool themeScheduled: _c.theme.schedule.enabled
  readonly property string lightAt: _c.theme.schedule.lightAt
  readonly property string darkAt: _c.theme.schedule.darkAt

  // --- Font ---
  readonly property string fontFamily: _c.font.family
  // At the Interface scale (Widget.scale); bars size their text from
  // baseFontSize, the setting itself
  readonly property int baseFontSize: _c.font.size
  readonly property int fontSize: Math.round(baseFontSize * Widget.scale)
  readonly property int fontSizeLarge: fontSizeBy(4)
  // The font size `n` px bigger (smaller when negative) than the setting,
  // at the Interface scale: the offset grows with the text, where
  // `fontSize + n` would leave it the same at every scale
  function fontSizeBy(n: real): int {
    return Math.round((baseFontSize + n) * Widget.scale);
  }
  // Icons are Material Symbols names drawn in this font (StyledIcon), so
  // they don't depend on the text font
  readonly property string iconFamily: "Material Symbols Rounded"

  // --- Shape ---
  readonly property int borderRadius: _c.shape.radius
  // The gap a surface growing out of an edge keeps between its box and
  // that edge, which its fillets curve across (AttachedSurface, EdgeAttach)
  readonly property int connectorGap: borderRadius * 2
  readonly property int borderWidth: _c.shape.borderWidth
  readonly property bool screenBorder: _c.shape.screenBorder
  // The frame can't be thinner than its own outline (a narrower one would
  // draw the stroke over the screen edge); without a frame it's just a gap
  readonly property int screenMargin: screenBorder ? Math.max(borderWidth, _c.shape.screenMargin) : _c.shape.screenMargin

  // --- Translucency ---
  // How solid the shell's surfaces are (0.6–1). Every surface fill goes
  // through fill(), outer and nested alike, so nested fills stack: a card
  // on a 60% panel reads about 84%.
  // Solid where the compositor can't blur behind them (plain sway): a
  // translucent surface over another would show it through unblurred. The
  // setting keeps its value (greyed out, x-enabledIf).
  readonly property real surfaceAlpha: compositorBlurs ? _c.surface.opacity / 100 : 1
  // Whether the compositor blurs behind axiom's surfaces
  // (CompositorManager.supports.blur), handed over by CompositorManager: a
  // reader reads no service, and building CompositorManager reads this
  property bool compositorBlurs: false
  readonly property bool translucent: surfaceAlpha < 1
  // The compositor blurs behind them (Hyprland's layer rules, which leave
  // out pixels under blurThreshold: shadows, dims, fades; SwayFX's layer
  // effects), with its own blur (the window look's blur part, or the
  // user's config). The options are the window look's (Compositor ›
  // Window look › Blur)
  readonly property var _look: ConfigManager.live.WindowLook
  readonly property bool blur: translucent && _look.surfaceBlur.enabled
  readonly property bool blurBackdrops: blur && _look.surfaceBlur.backdrops
  // Blurring what's under each surface, windows included, rather than the
  // wallpaper alone (xray), which every surface shares
  readonly property bool blurThroughWindows: _look.surfaceBlur.throughWindows
  // Nothing blurs while a fullscreen window is open (BlurManager.pausedOn)
  readonly property bool blurPauseFullscreen: _look.surfaceBlur.pauseFullscreen
  readonly property real blurThreshold: 0.5
  // A shadow's darkest alpha while blurring: under the threshold, so its
  // halo isn't blurred (the blur window casts the chrome's, and Hyprland
  // blurs the chrome's popups). Where the blur has no threshold (SwayFX),
  // a window it doesn't blur casts them (BlurBacking).
  readonly property real shadowAlphaMax: blur ? 0.45 : 1

  // A surface fill (a theme color, or a name or "#hex" as
  // Theme.resolveColor gives one) at the surface opacity
  function fill(color) {
    if (!translucent)
      return color;
    const c = Qt.color(color);
    return Qt.alpha(c, c.a * surfaceAlpha);
  }

  // --- Motion ---
  // Every animation in the shell uses one of these durations, so the
  // single speed setting (and the on/off switch) applies uniformly.
  // Use `duration: Appearance.animNormal` — never a literal.
  readonly property bool animations: _c.motion.enabled
  readonly property real _motionScale: animations ? 100 / _c.motion.speed : 0
  readonly property int animFast: Math.round(100 * _motionScale)    // hover, colour, small state changes
  readonly property int animNormal: Math.round(150 * _motionScale)  // slides, popouts, expanding sections
  readonly property int animSlow: Math.round(300 * _motionScale)    // large panels, lockscreen, pulses
  readonly property int easing: Easing.OutCubic
}
