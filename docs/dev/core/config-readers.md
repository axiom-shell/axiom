# Config readers

> **Files:** `qml/config/*.qml` (e.g. `qml/config/General.qml`, `qml/config/Appearance.qml`, `qml/config/BarsConfig.qml`, `qml/config/Theme.qml`, `qml/config/Paths.qml`)
> **Config:** one reader per section
> **Related:** [Config manager](config-manager.md), [Schema annotations](schema-annotations.md), [Themes](../theming/themes.md)

Typed, read-only views of config sections. (Rule: AGENTS.md › Config, no `??` fallbacks; › Layering. Reader naming: [README](../README.md) › Layout.)

### What a reader is
- `pragma Singleton`, but a reader, not an owner: one per config section, exposing `readonly property` values from `ConfigManager.live` (the config with editors' unsaved previews over it, [Previews](config-manager.md#previews)).
- No `??` fallbacks: schema defaults are already filled in.
- UI reads colors and settings from readers (`Theme.background`, `Widget.padding`), never `ConfigManager.config` directly.
- Readers whose section name collides with a type get a `Config` suffix (`Popouts`, `Overlay`, `Icons`, `OSD`, `Launcher`, `Notifications`, …).

### Readers
- **`General`**: `displayName`, `primaryMonitor`, `monitors` / `screens`, and:
  - `outputs`: the connected monitors.
    - It is `Quickshell.screens` without Qt's nameless placeholder and Hyprland's headless `FALLBACK`, which stand in while no monitor is connected.
    - A window left on a stand-in when monitors return is moved off a screen Qt then frees, and qs crashed configuring it.
    - `check_structure` refuses `Quickshell.screens` outside `General`; the windows that must exist with no monitor (the lock and greeter previews, the windowed greeter, the no-parent notice) say why on the line: `// allowed: <reason>`.
  - `screensNamed(name)`: that screen, else the primary, else the first.
  - `screensFor(mode, name)`: see [Shell manager and screen targeting](shell-manager-targeting.md).
- **`Idle`**: hypridle ([Idle](../features/idle.md)).
- **`PolkitConfig`**: [Polkit](../features/polkit.md).
- **`GreeterConfig`**: [Greeter install](../features/greeter-install.md).
- **`Appearance`**: theme, font, shape, motion tokens.
- **`Widget`**: sizes for controls and panels outside the bar. `height`, `padding`, `spacing`, `cardPadding`, `iconButton`, `smallHeight` and `smallPadding` are the density preset's (`Widget.density`) times the Interface scale (`Widget.scale`, a factor), which also scales `Appearance.fontSize` / `fontSizeLarge`; `Widget.px(n)` is any other size (a panel's width, an avatar, a dot) at the scale. Which to use where: [Shared UI pieces › Sizes](shared-ui-pieces.md#sizes). Bars read `Appearance.baseFontSize` and their own sizes, so they never follow it. `cardSize` is the card size every module grid starts from (`OverlayConfig.cardUnitOn`).
- **`BarsConfig`**: from `Bars`.
  - The first bar is primary.
  - Edges are numbers from `methods/ScreenEdge` (`ScreenEdge.fromConfig(location)`), not this reader's.
- **`PopoutsConfig`**: open/dismiss delays and edge trigger size, shared by bar and edge popouts.
- **`OSDConfig`**: the OSDs; see [OSD](../features/osd.md).
- **`HotCornersConfig`**: the hot corners; see [Hot corners](../features/hot-corners.md).
- **`LauncherConfig`**: launcher placement, size and providers.
- **`Apps`**: the terminal, file manager and browser that binds and the launcher open, and the network editor (the Wi-Fi menu, the VPN module).
- **`Screenshots`**: the screenshot and recording folders, `~` expanded, empty for `ScreenshotManager`'s defaults ([Screenshots and screen recording](../features/screenshots-recording.md)).
- **`NotificationsConfig`**: the toasts' corner and gaps; see [Notifications](../features/notifications.md).
- **`OverlayConfig`**: views and card-grid constants.
- **`EdgeMenusConfig`**: edge menus.
- **`IconsConfig`**, **`ChatConfig`**, **`ThemeIntegrations`**.
- **`TailscaleConfig`**: what every Tailscale widget and module shares: the poll `interval`, `showOffline` peers, the Connect/Disconnect `actions`.
- **`DrivesConfig`**: whether drive events notify, what plugging in a removable drive does and the drives left alone: `notify`, `onInsert`, `warnUnplugged`, `ignore`.
- **`VpnConfig`**: what every VPN widget and module shares: `notifyOnDrop`, `showTailscale` (Tailscale as a VPN row), `publicIpUrl`.
- **`CustomWidgetsConfig`**: the custom widgets (`items`, `byId`, `definition(id)`), read through a JSON string so an unrelated change doesn't notify ([custom widgets](../features/custom-widgets.md)).
- **`CommunitySetups`**: whether the gallery is on, and its catalog URL ([Community setups](../features/community-setups.md)).
- **`CalendarConfig`**:
  - accounts with their ids filled in
  - `calendars` flattened with resolved colors
  - `shownCalendars` / `writableCalendars`, `newEventCalendar`
  - `colors` by calendar id
  - `timeFormat` from `use24Hour`.
- **`Paths`**: derived filesystem paths, not configurable. Also `packaged` / `packagedVersion`: the marker a distribution package writes at the install tree's root (`installTreePath`, from `$AXIOM_INSTALL_TREE`; [packaging.md](../packaging.md)).
  - What ships in the tree: `axiomPath` (the QML folder, `Quickshell.shellDir`), `resourcePath` and `themePath` under it, and `treePath` (the tree's root, `$AXIOM_TREE`, whose `data/` holds the runtime files that aren't QML). Read-only.
  - What axiom writes, the XDG folders from `ConfigManager.dataDirs`: `userConfigPath`, `statePath`, `userStatePath`, `userDataPath`, `defaultNotesPath`, `generatedThemesPath`, plus `themeFile(name)` for a theme's file by name. See [Where files live](config-manager.md#where-files-live).
  - Also `greeter` and the greeter's folders ([Greeter runtime](../features/greeter-runtime.md)).
- **`Theme`**: below.

### Theme
- `qml/config/Theme.qml` exposes the base16 palette (`base00`–`base0F`).
- Semantic aliases (`background`, `accent`, `error`, …) resolve through `_themeData.semantic`.
- `stringToColorMap` + `resolveColor(name)` give dynamic lookup by string, for a color name that comes from JSON/config rather than a static binding.
