# Bar composition

> **Files:** `qml/shell/Bar.qml`, `qml/components/bar/BarPanel.qml`, `qml/components/bar/BarContainer.qml`, `qml/components/bar/WidgetGroup.qml`, `qml/components/bar/WidgetDecorations.qml`, `qml/components/bar/AccentLines.qml`, `qml/components/bar/BarWidgetHost.qml`, `qml/components/methods/BarLayout.qml`, `qml/components/hosts/popout/BarPopouts.qml`, `qml/components/hosts/popout/PopoutAnchor.qml`, `qml/config/BarsConfig.qml`, `qml/services/ui/BarManager.qml`, `qml/services/ui/BarRevealManager.qml`, `qml/services/ui/ScreenEdgeManager.qml`
> **Config:** `Bars` (`Bar`, `BarWidget` definitions)
> **Related:** [Widget style](widget-style.md), [Widget shapes and runs](widget-shapes-runs.md), [Layering and corners](layering-and-corners.md), [Bar editor](bar-editor.md), [Menus](../menus/overview.md), [Popout hosts](../popouts/hosts-and-switching.md)

How a bar is built from config: the panel per bar, the widget hosts, the layout math, how widgets open popouts and menus, the icon rules, auto-hide, and why bar motion animates what is drawn rather than what is measured.

### Bars from config
- `qml/shell/Bar.qml` renders one `BarPanel` per entry in `ScreenEdgeManager.bars` (a `Variants`/model). Multi-monitor and multi-panel bars therefore come from config data, not from hardcoded code.
- `ScreenEdgeManager.bars` holds the running bars after `BarsConfig.enrichBarConfig` (the bar editor, `BarManager`, only previews its draft into them). Enrichment adds:
  - The compositor's `gapsOut` and `floatGaps` (what an Automatic float gap keeps: `gapsOut`, or the screen margin with no backend), which a reader can't read.
  - Each bar's place among the bars stacked on its edge (`BarEnds.withEnds`: its exclusive `zone`, `layerRank`, `ends`; [Layering and corners](layering-and-corners.md#bars-stacked-on-one-edge-barendsstackson-placestack-edgeof)).
  - What the bars leave on each screen edge: `edgesFor` (the innermost), `stackOn`, `edgeOn`, `screenEdgeOpen`, `barReservedOn`, `frameLine`, `detachedGaps`.
- A bar whose screen mode isn't `primary` (every monitor, named ones, or General's, the default) is expanded by `BarsConfig.expandBars` into one entry per screen (id `<id>@<screen>` even on one screen, so a hotplug leaves the other bars' windows, plus `sourceId`), the primary monitor's first. A bar in `primary` mode keeps its plain id.
- Any other bar's monitor is resolved to a connected screen there.

### Widgets and their options
- Bar contents are built from `qml/components/bar/{BarContainer,BarWidgetHost,WidgetGroup,WidgetDecorations,BarPanel}.qml` (a section's `WidgetGroup` measures, allocates and places its hosts; its `WidgetDecorations` draws the run backgrounds, separator marks and widget backgrounds under them, from `methods/BarRuns`; `AccentLines` draws the accent line along the bar or its pills). How widgets are styled, the bar's look and its layers: [Widget style](widget-style.md#the-style-system-in-five-layers). These compose widgets from `qml/components/bar/widgets/<type>/<type>.qml` (Time, Battery, Network, Workspaces, Media, SystemTray, Notifications, etc.).
- Each widget's options live under its `<Type>Widget.properties.properties` definition in the schema.
- `SchemaValidation` picks the `BarWidget` oneOf option by `type`. Widget properties therefore get their defaults filled like the rest of the config, and widgets read `properties.<key>` directly.
- Widget types come from `BarsConfig.availableWidgetTypes`, the `BarWidget` oneOf. Each type's label comes from its description and its icon from its `x-icon`.
- `WidgetGroup` models its widgets by count, so live option edits reach a widget in place instead of rebuilding the section. `BarWidgetHost` takes the widget's whole config (`widget`): a changed `type` reloads the module with that type's own properties, any other change hands it the new `properties` (and `box`, the one item of a widget drawn one box per item: [widget style](widget-style.md#boxes-one-per-item)).

### Layout math
- The main-axis layout math is pure and lives in `methods/BarLayout` (tested in `tst_BarLayout`). It covers:
  - the three sections (left, center, right) placed along the bar (`layoutSections`): the ends hug the ends, the center stays centered (with `lockCenter` dead center, each side fitting its own half)
  - the widgets hidden when the bar overflows (`overflowHidden`): lowest priority first, ties right, then left, the center last
  - elastic widgets squeezed within a section (`allocate`)
  - With `lockCenter`, `layoutSections`, `overflowHidden` and the bar editor's `sectionRooms` read what's centered and the room on each half from one place (`_lockedFrame`), so what's hidden and what the editor shows always match the layout.
- **Spacers** (the Spacer widget, `fill` in its measure) take the free room:
  - **With `lockCenter` off** and a spacer anywhere on the bar, nothing is centered: every spacer takes an equal share of the bar's free room and the sections pack end to end, so every boundary between two widgets joins. Crowded (the preferred sizes don't fit), the spacers keep their `minGap` and the sections are laid out as below. With no spacers the center is centered as ever, sliding towards the roomier side when crowded.
  - **With `lockCenter` on**, the sections are laid out with every spacer at its `minGap` first, so a spacer never moves the center.
  - Then a side with spacers stretches to the center's edge; with no center, the room between the sides is shared by their spacer counts.
  - **Spacers in a locked center** push its outer groups out to the sides (`BarLayout.centerSplit`): with two or more, what lies between the first and the last stays centered (inner spacers keep their `minGap`) and the groups outside them go to the sides; with one, the group with more widgets stays centered (the first on a tie: from the config, so it never flips as widgets change width) and the other goes to its side.
    - The centered group is what `lockCenter` keeps dead center. Each half of the bar, from its end to that group, is shared equally between all the spacers in it, the side's and the center's (`layoutSections` with `centerParts`): a side spacer and a center spacer bordering the same room meet in the middle of it.
    - The center's spacers get their shares as weights (`leadShare`/`tailShare` → `BarLayout.centerFillWeights` → `allocate`); its inner spacers take none.
  - `allocate` hands a section's room past its widgets to its spacers, equally (the remainder to the last).
  - A spacer lies in the gap between the widgets beside it, so a collapsed one (crowded, `minGap` 0) leaves one gap. It's never hidden for want of room.
  - A widget a spacer pushes against the next section joins it: merged backgrounds, powerline chains and separator marks carry on across, and that gap is the one between widgets ([Joined sections](widget-shapes-runs.md#joined-sections)). The center never moves for it.
- `BarContainer` and `WidgetGroup` only feed it measurements.

### Popouts
- A widget opens a popout by dropping in a `PopoutAnchor` with a `popoutName`.
- The per-bar `BarPopouts` (in `hosts/popout/`) loads `content/<popoutName>/<popoutName>.qml` by URL. A new popout is therefore a content file plus an anchor.
- See [Popout hosts](../popouts/hosts-and-switching.md).

### Menu popouts
- Every widget except Separator has a `popout`: `enabled` and `menu`, a menu id (`x-options: menus`) shown under the switch. Button's is a menu only (its click action is separate).
  - A widget with a popout of its own opens that menu in its place. A widget without one gets an "Open on hover" switch.
- `BarWidgetHost` holds the one anchor for the menu:
  - It is a `PopoutAnchor` with `menu`, hovered through the host's `hitArea` but sized to the module (not the hit area's powerline reach back), so a menu opened at its widget (`popoutAtWidget`) centres on it.
  - It calls `MenuManager.open(id, anchor)` on hover.
  - The anchor keeps a floating menu open while it is hovered.
- Meanwhile the widgets' own anchors stand down (`active: MenusConfig.opensOwnPopout(properties) && …`).
- A menu that is gone or disabled leaves the widget its own popout (`MenusConfig.popoutMenuOf`).

### Icons
- Icons are Material Symbols names drawn by `reusable/StyledIcon` in `Appearance.iconFamily`, the font axiom bundles ([icons.md](../core/icons.md)).
- `StyledIcon` draws anything that isn't a name (a glyph, or text typed into an icon field) in the text font.
- Services, schema defaults (`x-icon`, icon fields) and launcher `glyph`s hold names.
- `DependencyManager` warns once when the font is missing.

### Auto-hide (`autoHide`, `BarRevealManager`)
- `autoHide`: `never` (default), `always`, or `whenCovered` (hidden only while a window covers its slot, or a fullscreen window is on its screen: `CompositorManager.windowsCover` over its whole edge, `hasFullscreen`).
- **Shown** (`BarRevealManager.shownOf(bar)`, per running bar id): `never`, or pinned, or hovered, or held, or revealed for a moment, or (`whenCovered`) not covered. One one-shot Timer runs to the earliest deadline (a moment's end, a hover waiting on its delay).
  - **Hover:** the bar's `HoverHandler`; hidden, its window's mask is only a `ScreenEdge.triggerSize` strip at its outer edge (`edgeStrip`). Entering a hidden bar shows it after `timing.openDelay`; leaving hides it after `timing.closeDelay`. Revealed, the mask is the bar where it rests (`barSlot`), so the pointer holds it while it slides in.
  - **Holds** (`hold(id, key, on)`, reported by `BarPanel`): its popouts open (`BarPopouts.occupied`), a menu opened from a widget on it (`MenuManager.anchors`), the bar editor open with it selected. Let go, it stays one close delay longer.
  - **Moments** (`reveal(id, ms)`): a workspace change on its monitor (`revealOnWorkspace`, from `CompositorManager.outputs`' active and special workspace; the first look only records them), a widget's news (`attention(id)`, with `revealOnActivity`; ignored in the bar's first 2 s, its widgets' startup; below) and the IPC `reveal`, each for `revealFor`.
  - **Pinned** (`setPinned`; the IPC `toggle`): shown until unpinned, and reserving its space (below). `hideNow` unpins and drops hover and moments.
  - **IPC** (`IpcTarget` `bar`, [usage](../../usage.md)): `reveal <id>` (a moment), `toggle <id>` (pin or unpin; all pinned when any isn't), `hide <id>` (`hideNow`), where `<id>` is a bar's config id (its instance on every monitor) or `focused` / `""` (the auto-hiding bars on the focused monitor); an unknown id is `not_found`. The keybind action `bar` calls them (toggle, open → `reveal`, close → `hide`; its argument defaults to `focused`, `KeybindManager.argumentOptions` lists the auto-hiding bars).
- **Reserving:** an auto-hiding bar's enriched `reserveSpace` is false (`BarsConfig.enrichBarConfig`; the `reserveSpace` setting shows only for `never`), so a revealed bar lies over the windows. Pinned, `ScreenEdgeManager.bars` sets its `pinned`, and `BarEnds` zones it by `reserves(bar)` (`reserveSpace || pinned`) while stack order, corners, frames and the connected run go by `reserveSpace` alone: pinning changes only its exclusive zone and where windows start, never where any bar lies ([layering](layering-and-corners.md#bars-stacked-on-one-edge-barendsstackson-placestack-edgeof)).
- **A widget's news** (`BarWidget.attention()`, which `BarWidgetHost` hands to `BarRevealManager.attention`, never from a preview) fires on a change, never at startup. Most set `attentionLevel` (-1 while unknown) and the base fires when it rises past the last known one (`attentionMuted` records a rise without firing): Notifications (the unread count, muted by do-not-disturb), Battery (0, or 1 below the low threshold while discharging), Updates (the count, known once a check has ended here) and CustomWidget (its state's colour: 1 warning, 2 error). Media fires itself when the track changes while playing (not on a player's first track).
- **Hiding** (`BarPanel`): it keeps its window and its slot; the `BarContainer` slides out toward its edge by geometry (`slide`, gliding over `animNormal`), not a Translate, so its blur shapes and shadow follow it, cut to its window (`BarContainer.blurClip`). Nothing maps, unmaps or changes layer, fullscreen included: the bar stays on Top under a fullscreen window.
  - **What sits on it follows its reveal** (`BarPanel.present`: mapped and revealed; `onScreen`: any of it still in view). Once it has slid out of view its border openings (`borderOpening`, `joinOpening`, a solid bar's join) close, the stroke whole again. While it isn't revealed, surfaces on its edge take it as absent (`EdgePlacement.barPanel`, `ScreenEdgeManager.surfaceEnd`'s `barShowing`) and a bar beside it doesn't merge into it (`BarContainer.barAt`): a dock there stands on the frame, and moves out onto the bar when it reveals.

### Bar motion: drawn, not measured
- **Measured, never animated:** the layout is measured from the modules' implicit sizes. That covers `naturalSize`/`preferredSize`, `WidgetGroup.allocation`, `BarContainer.slots`, and a section's `mainPos`/`usedLength`.
- **Drawn, glides to the layout:**
  - Each `BarWidgetHost`'s `x`/`y`/`width`/`height` glide with animFast. This is off until `_settled`.
    - The module is laid out at its target `mainSize` and centred in the drawn box.
    - It is clipped while the two sizes differ, so labels never re-elide mid-animation.
  - Each `Section`'s `drawnPos`/`drawnLength` glide too. `groupSpans` (each section's groups of widgets as drawn, `WidgetGroup.drawnGroups`), and through it the pills, read these.
- Backgrounds and separator marks follow the hosts as drawn.
- A widget that is going keeps its last place and colors while its host still fades or shrinks out, going with it. A host that stays drawn (a delegate reused for another widget, a widget dropping its background) lets go once its size settles.
- Colors (`WidgetBackground`, `IconTextRow`) fade with ColorAnimations. The tray's icons grow in (Grid `add`/`move`).
