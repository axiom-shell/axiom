# Bar composition

> **Files:** `shell/Bar.qml`, `components/bar/BarPanel.qml`, `components/bar/BarContainer.qml`, `components/bar/WidgetGroup.qml`, `components/bar/BarWidgetHost.qml`, `components/methods/BarLayout.qml`, `components/hosts/popout/BarPopouts.qml`, `components/hosts/popout/PopoutAnchor.qml`, `config/Bar.qml`, `services/ui/BarManager.qml`, `services/ui/ScreenEdgeManager.qml`
> **Config:** `Bars` (`Bar`, `BarWidget` definitions)
> **Related:** [Widget style](widget-style.md), [Widget shapes and runs](widget-shapes-runs.md), [Layering and corners](layering-and-corners.md), [Bar editor](bar-editor.md), [Edge menus](../edge-menus/overview.md), [Popout hosts](../popouts/hosts-and-switching.md)

How a bar is built from config: the panel per bar, the widget hosts, the layout math, how widgets open popouts and edge menus, the icon rules, and why bar motion animates what is drawn rather than what is measured.

### Bars from config
- `shell/Bar.qml` renders one `BarPanel` per entry in `ScreenEdgeManager.bars` (a `Variants`/model). Multi-monitor and multi-panel bars therefore come from config data, not from hardcoded code.
- `ScreenEdgeManager.bars` holds the running bars after `Bar.enrichBarConfig` (the bar editor, `BarManager`, only previews its draft into them). Enrichment adds:
  - Hyprland's `gapsOut`, which a reader can't read.
  - What the bar leaves on each screen edge: `edgesFor`, `screenEdgeOpen`, `barReservedOn`, `frameLine`, `detachedGaps`.
- A bar whose `monitor` is `"*"` is expanded by `Bar.expandBars` into one entry per screen (id `<id>@<screen>`, plus `sourceId`), the primary monitor's first.
- Any other bar's monitor is resolved to a connected screen there.

### Widgets and their options
- Bar contents are built from `components/bar/{BarContainer,BarWidgetHost,WidgetGroup,BarPanel}.qml`. These compose widgets from `components/bar/widgets/<type>/<type>.qml` (Time, Battery, Network, Workspaces, Media, SystemTray, Notifications, etc.).
- Each widget's options live under its `<Type>Widget.properties.properties` definition in the schema.
- `SchemaValidation` picks the `BarWidget` oneOf option by `type`. Widget properties therefore get their defaults filled like the rest of the config, and widgets read `properties.<key>` directly.
- Widget types come from `Bar.availableWidgetTypes`, the `BarWidget` oneOf. Each type's label comes from its description and its icon from its `x-icon`.
- `WidgetGroup` models its widgets by count, so live option edits reach a widget in place instead of rebuilding the section.

### Layout math
- The main-axis layout math is pure and lives in `methods/BarLayout` (tested in `tst_BarLayout`). It covers:
  - sections placed along the bar
  - the widgets hidden when the bar overflows
  - elastic widgets squeezed within a section
- `BarContainer` and `WidgetGroup` only feed it measurements.

### Popouts
- A widget opens a popout by dropping in a `PopoutAnchor` with a `popoutName`.
- The per-bar `BarPopouts` (in `hosts/popout/`) loads `content/<popoutName>/<popoutName>.qml` by URL. A new popout is therefore a content file plus an anchor.
- See [Popout hosts](../popouts/hosts-and-switching.md).

### Menu popouts
- Every widget except Separator has a `popout`: `enabled` and `menu`, an edge menu id (`x-options: edgeMenus`) shown under the switch. Button's is a menu only (its click action is separate).
  - A widget with a popout of its own opens that menu in its place. A widget without one gets a "Menu popout" switch.
- `BarWidgetHost` holds the one anchor for the menu:
  - It is a `PopoutAnchor` with `menu`, hovered through the host's `hitArea` but sized to the module (not the hit area's powerline reach back), so a menu opened at its widget (`popoutAtWidget`) centres on it.
  - It calls `EdgeMenuManager.open(id, anchor)` on hover.
  - The anchor keeps a floating menu open while it is hovered.
- Meanwhile the widgets' own anchors stand down (`active: EdgeMenusConfig.opensOwnPopout(properties) && …`).
- A menu that is gone or disabled leaves the widget its own popout (`EdgeMenusConfig.popoutMenuOf`).

### Icons
- Icons are Material Symbols names (`ttf-material-symbols-variable`, fonts.google.com/icons) drawn by `reusable/StyledIcon` in `Appearance.iconFamily`.
- `StyledIcon` draws anything that isn't a name (a glyph, or text typed into an icon field) in the text font.
- Services, schema defaults (`x-icon`, icon fields) and launcher `glyph`s hold names.
- `DependencyManager` warns once when the font is missing.
- (Rule: AGENTS.md › UI conventions, Icons.)

### Bar motion: drawn, not measured
- **Measured, never animated:** the layout is measured from the modules' implicit sizes. That covers `naturalSize`/`preferredSize`, `WidgetGroup.allocation`, `BarContainer.slots`, and a section's `mainPos`/`usedLength`.
- **Drawn, glides to the layout:**
  - Each `BarWidgetHost`'s `x`/`y`/`width`/`height` glide with animFast. This is off until `_settled`.
    - The module is laid out at its target `mainSize` and centred in the drawn box.
    - It is clipped while the two sizes differ, so labels never re-elide mid-animation.
  - Each `Section`'s `drawnPos`/`drawnLength` glide too. `_spans`, and through it the pills, read these.
- Backgrounds and separator marks follow the hosts as drawn.
- A widget that is going keeps its last place and colors while its host still draws, fading with its opacity.
- `BarContainer.layoutMoved()` emits `layoutUpdated` at once and again after `animNormal`, so an open popout re-anchors on the settled widget.
- Colors (`WidgetBackground`, `IconTextWidget`) fade with ColorAnimations. The tray's icons grow in (Grid `add`/`move`).
- (Rule: AGENTS.md › Config, Animation.)
