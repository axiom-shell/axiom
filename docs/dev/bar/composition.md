# Bar composition

> **Files:** `qml/shell/Bar.qml`, `qml/components/bar/BarPanel.qml`, `qml/components/bar/BarContainer.qml`, `qml/components/bar/WidgetGroup.qml`, `qml/components/bar/BarWidgetHost.qml`, `qml/components/methods/BarLayout.qml`, `qml/components/hosts/popout/BarPopouts.qml`, `qml/components/hosts/popout/PopoutAnchor.qml`, `qml/config/BarsConfig.qml`, `qml/services/ui/BarManager.qml`, `qml/services/ui/ScreenEdgeManager.qml`
> **Config:** `Bars` (`Bar`, `BarWidget` definitions)
> **Related:** [Widget style](widget-style.md), [Widget shapes and runs](widget-shapes-runs.md), [Layering and corners](layering-and-corners.md), [Bar editor](bar-editor.md), [Edge menus](../edge-menus/overview.md), [Popout hosts](../popouts/hosts-and-switching.md)

How a bar is built from config: the panel per bar, the widget hosts, the layout math, how widgets open popouts and edge menus, the icon rules, and why bar motion animates what is drawn rather than what is measured.

### Bars from config
- `qml/shell/Bar.qml` renders one `BarPanel` per entry in `ScreenEdgeManager.bars` (a `Variants`/model). Multi-monitor and multi-panel bars therefore come from config data, not from hardcoded code.
- `ScreenEdgeManager.bars` holds the running bars after `BarsConfig.enrichBarConfig` (the bar editor, `BarManager`, only previews its draft into them). Enrichment adds:
  - The compositor's `gapsOut` and `floatGaps` (what an Automatic float gap keeps: `gapsOut`, or the screen margin with no backend), which a reader can't read.
  - Each bar's place among the bars stacked on its edge (`BarEnds.withEnds`: its exclusive `zone`, `layerRank`, `ends`; [Layering and corners](layering-and-corners.md#bars-stacked-on-one-edge-barendsstackson-placestack-edgeof)).
  - What the bars leave on each screen edge: `edgesFor` (the innermost), `stackOn`, `edgeOn`, `screenEdgeOpen`, `barReservedOn`, `frameLine`, `detachedGaps`.
- A bar whose `monitor` is `"*"` is expanded by `BarsConfig.expandBars` into one entry per screen (id `<id>@<screen>`, plus `sourceId`), the primary monitor's first.
- Any other bar's monitor is resolved to a connected screen there.

### Widgets and their options
- Bar contents are built from `qml/components/bar/{BarContainer,BarWidgetHost,WidgetGroup,BarPanel}.qml`. These compose widgets from `qml/components/bar/widgets/<type>/<type>.qml` (Time, Battery, Network, Workspaces, Media, SystemTray, Notifications, etc.).
- Each widget's options live under its `<Type>Widget.properties.properties` definition in the schema.
- `SchemaValidation` picks the `BarWidget` oneOf option by `type`. Widget properties therefore get their defaults filled like the rest of the config, and widgets read `properties.<key>` directly.
- Widget types come from `BarsConfig.availableWidgetTypes`, the `BarWidget` oneOf. Each type's label comes from its description and its icon from its `x-icon`.
- `WidgetGroup` models its widgets by count, so live option edits reach a widget in place instead of rebuilding the section.

### Layout math
- The main-axis layout math is pure and lives in `methods/BarLayout` (tested in `tst_BarLayout`). It covers:
  - the three sections (left, center, right) placed along the bar (`layoutSections`): the ends hug the ends, the center stays centered (with `lockCenter` dead center, each side fitting its own half)
  - the widgets hidden when the bar overflows (`overflowHidden`): lowest priority first, ties right, then left, the center last
  - elastic widgets squeezed within a section (`allocate`)
- **Spacers** (the Spacer widget, `fill` in its measure) take the free room:
  - The sections are laid out with every spacer at its `minGap` first, so a spacer never moves the center.
  - Then a side with spacers stretches to the center's edge; with no center, the room between the sides is shared by their spacer counts. A spacer in the center keeps its `minGap`.
  - `allocate` hands a section's room past its widgets to its spacers, equally (the remainder to the last).
  - A spacer lies in the gap between the widgets beside it, so a collapsed one (crowded, `minGap` 0) leaves one gap. It's never hidden for want of room.
- **`length: fit`** (`barConfig.fit`, with `align`): the sections lie end to end at the bar's `align` (start, center, end) in what its end margins leave (`BarLayout.fitSections`), spacers at their `minGap`, and `lockCenter` doesn't apply. The window still spans its edge and reserves as ever; what's drawn spans the content: a floating bar's one island (`BarContainer._contentSpan`), pills per group as always. A solid bar keeps its fill along the whole edge (the border's strip there is transparent, relying on the bar's fill), so only its widgets move.
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
- Icons are Material Symbols names drawn by `reusable/StyledIcon` in `Appearance.iconFamily`, the font axiom bundles ([icons.md](../core/icons.md)).
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
  - Each `Section`'s `drawnPos`/`drawnLength` glide too. `groupSpans` (each section's groups of widgets as drawn, `WidgetGroup.drawnGroups`), and through it the pills, read these.
- Backgrounds and separator marks follow the hosts as drawn.
- A widget that is going keeps its last place and colors while its host still draws, fading with its opacity.
- Colors (`WidgetBackground`, `IconTextWidget`) fade with ColorAnimations. The tray's icons grow in (Grid `add`/`move`).
- (Rule: AGENTS.md › Config, Animation.)
