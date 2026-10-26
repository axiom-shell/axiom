# Bars and the screen border: layering and corners

> **Files:** `shell/Bar.qml`, `shell/ScreenBorder.qml`, `components/surfaces/border/RoundedBorders.qml`, `components/surfaces/border/BorderPanel.qml`, `components/reusable/CornerPiece.qml`, `components/methods/BarEnds.qml`, `tests/tst_BarEnds.qml`, `components/bar/BarContainer.qml`, `components/bar/CornerMerge.qml`, `components/hosts/popout/AttachedSurface.qml`, `services/ui/BarManager.qml`, `services/compositor/HyprlandManager.qml`
> **Config:** `Appearance.shape.screenBorder`, `Bars[].background`, `BarStyle` shadow group. (`insideBorder`, `innerStroke` are derived `barConfig` values from `Bar.enrichBarConfig`, not config keys.)
> **Related:** [Pill and floating bars](../popouts/pill-and-floating-bars.md), [Held off an edge](../popouts/held-off-edge.md), [Edge attach](../popouts/edge-attach.md), [Surface context](../popouts/surface-context.md), [Widget shapes](widget-shapes-runs.md)

How bars and the screen border share an edge through layer-shell ordering. Covers solid bars, bars inside the border, which bar gets a shared corner, transparent bars, the border being off, and the border's inward shadow window. Bar ends and pills are in [Bar ends and pills](bar-ends-pills.md).

(Rule: AGENTS.md › UI conventions, Layer ordering. The order lives in `LayerStack.layers`, listed in [layer stacking](../generated/layers.md).)

### The border
- `Appearance.screenBorder` turns the border off.
- The border is `shell/ScreenBorder`, which is `surfaces/border/RoundedBorders`: four `BorderPanel` strips and four `CornerPiece` corners, in the layer namespace `axiom-border`.

### Solid bar (`Bar.background: "solid"`)
- It is on the Top layer, at the screen edge.
- The border's strip on that edge is arranged after the bar and overlaps its inner part, so the strip's stroke is the bar's inner edge.
- **Build order.** Hyprland reads a layer rule's `order` only as a surface maps.
  - So the bars, border, docks and edge menus are built only once `CompositorManager.surfacesReady` is true. The rules are evaluated at startup and kept across QML reloads.
  - Why: in detached mode, hyprland.lua doesn't hold the rules. A border mapped first would land outside the bar, with its corners on the bar's outer side.
  - Each of these windows also maps in `LayerStack.layers` order, a stage at a time, through its `hosts/popout/LayerSlot`. Where the compositor has no layer rules (sway, niri: no `supports.layerOrder`), map order is all that decides, so a window landing out of place (a bar remade after the border) makes the ones it should have come before map again ([layer arrangement](../compositor/layer-arrangement.md)).
- **Window keying.** For the same reason, `shell/Bar` keys each bar's window on whether it sits inside the border, as well as on its id.
  - Switching to or from solid changes the bar's namespace, so the window is remade and maps under the new rule.

### Bar inside the border (`barConfig.insideBorder`)
- This applies to any background except solid, with the border on.
- The bar is on the Top layer like the border, in the `axiom-bar-pill`, `axiom-bar-transparent` or `axiom-bar-floating` (floating bars and floating pills) namespace.
  - Their layer rules (below the border's) make Hyprland arrange the bar after the border and draw it over the border.
- It sits just inside the border with a `-borderWidth` margin, so its outer edge lies on the border's stroke.
- A fullscreen window covers it, as it does everything on the Top layer, so it never hides.
- Hyprland counts that margin into the reserved space, so the bar reserves `extent`.
- `RoundedBorders.cornerMargin` pulls the corner pieces back out to the border's corners on such a bar's edge.

### Bars sharing a corner (`methods/BarEnds`, `tests/tst_BarEnds.qml`)
- Hyprland gives a corner to the bar it arranges first. The other bar's window ends at its reserved line.
- Which bar that is depends on the layer rule, never on which mapped first. First to last: solid bars, the border, pill bars, transparent bars, floating bars and floating pills (orders: [layer stacking](../generated/layers.md), from `LayerStack.layers`; `tst_LayerStack` holds them to this order).

  - A floating bar always makes way.
  - Between bars of one kind, the bar on the screen's longer edge makes way (the `-long` namespace), so the shorter bar gets the corner: side bars on a landscape monitor, top and bottom ones on a portrait one (`shortEdge`, `BarEnds.onShortEdge`).
  - Solid bars can't tie with pill bars: a solid bar is arranged before the border, a pill bar after it.
  - Docks, the overlay, the OSD and popouts are ordered after every bar.
  - The namespace comes from `Bar.layerNamespace`. `shell/Bar` keys each window on it, since `order` is read only as a surface maps: a bar changing kind, or a monitor rotating, remakes the window.
- A bar reserving nothing takes no corner.

### Ends and pills
Each bar end's `kind`, joining rules, pill bars merging at a corner, and pills themselves: see [Bar ends and pills](bar-ends-pills.md).

### Transparent bars
- They reserve `Hyprland gaps_out` less (`CompositorManager.gapsOut`). Windows therefore start at the bar's invisible inner edge, and the widgets' gap to the windows matches their gap to the screen edge.
- Bar popouts use `adjustment: PopupAdjustment.None`. Their placement is computed, and Hyprland would otherwise nudge one sitting flush on the screen edge a few pixels inwards.

### Border off
- A solid bar draws its own inner stroke (`barConfig.innerStroke`) on its innermost `borderWidth` pixels, where its popouts attach.
- Surfaces on a bare screen edge (`ScreenEdgeManager.screenEdgeOpen(screen, location)`: no border and no bar there) run straight off it, with no fillets and no `-borderWidth` margin.
  - For pills, merged popouts and EdgePopout, that is `AttachedSurface.straight` (attach edge) / `straightJoins` (joined ends).
  - The overlay panel pushes its corners and stroke past the window on those sides.

### Border shadow window
- The screen border casts the `BarStyle` section's shadow inward, all the way round. It does this through `RoundedBorders`' shadow window:
  - one click-through, exclusion-ignoring window over the screen
  - the frame's shape, blurred and masked to its inside
  - `innerInset`: inset past a solid bar reserving its edge
  - in the `axiom-border-shadow` namespace. Its layer rule stacks it under every other axiom surface, the overlay backdrop included.
- A solid bar reserving its edge under the border casts no shadow of its own (`Bar.enrichBarConfig`'s `borderShadowed`).
- `Bar.shadowColor` resolves the color for both the border and the bar shadows (see [Widget shapes](widget-shapes-runs.md#bar-shadow)).
