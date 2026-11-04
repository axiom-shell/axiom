# Bars and the screen border: layering and corners

> **Files:** `qml/shell/Bar.qml`, `qml/shell/ScreenBorder.qml`, `qml/components/surfaces/border/RoundedBorders.qml`, `qml/components/surfaces/border/BorderPanel.qml`, `qml/components/reusable/CornerPiece.qml`, `qml/components/methods/BarEnds.qml`, `tests/tst_BarEnds.qml`, `qml/components/bar/BarContainer.qml`, `qml/components/bar/CornerMerge.qml`, `qml/components/hosts/popout/AttachedSurface.qml`, `qml/services/ui/ScreenEdgeManager.qml`, `qml/services/compositor/HyprlandManager.qml`
> **Config:** `Appearance.shape.screenBorder`, `Bars[].background`, `BarStyle` shadow group. (`insideBorder`, `innerStroke` are derived `barConfig` values from `BarsConfig.enrichBarConfig`, not config keys.)
> **Related:** [Pill and floating bars](../popouts/pill-and-floating-bars.md), [Held off an edge](../popouts/held-off-edge.md), [Edge attach](../popouts/edge-attach.md), [Surface context](../popouts/surface-context.md), [Widget shapes](widget-shapes-runs.md)

How bars and the screen border share an edge through layer-shell ordering. Covers solid bars, bars inside the border, bars stacked on one edge, which bar gets a shared corner, transparent bars, the border being off, and the border's inward shadow window. Bar ends and pills are in [Bar ends and pills](bar-ends-pills.md).

(Rule: `qml/components/bar/AGENTS.md`, Layer ordering. The order lives in `LayerStack.layers`, listed in [layer stacking](../generated/layers.md).)

### The border
- `Appearance.screenBorder` turns the border off.
- The border is `qml/shell/ScreenBorder`, which is `surfaces/border/RoundedBorders`: four `BorderPanel` strips and four `CornerPiece` corners, in the layer namespace `axiom-border`.

### Solid bar (`Bars.items[].surface: "bar"`)
- It is on the Top layer, at the screen edge.
- The border's strip on that edge is arranged after the bar and overlaps its inner part, so the strip's stroke is the bar's inner edge.
- **Build order.** Hyprland reads a layer rule's `order` only as a surface maps.
  - So the bars, border, docks and edge menus are built only once `CompositorManager.surfacesReady` is true. The daemon adds the rules when the shell starts (`compositor.layerRules`, which `HyprlandManager` waits for, at most 2 s) and again on every `configreloaded` (a reload drops rules added at runtime); they're kept across QML reloads. On sway it waits for the `get_version` reply instead (whether it's SwayFX, so the blur and shadow windows map with the rest); niri's is true at once.
  - Why: in detached mode, hyprland.lua doesn't hold the rules. A border mapped first would land outside the bar, with its corners on the bar's outer side.
  - Each of these windows also maps in `LayerStack.layers` order, a stage at a time, through its `hosts/popout/LayerSlot`. Where the compositor has no layer rules (sway, niri: no `supports.layerOrder`), map order is all that decides, so a window landing out of place (a bar remade after the border) makes the ones it should have come before map again ([layer arrangement](../compositor/layer-arrangement.md)).
- **Window keying.** For the same reason, `qml/shell/Bar` keys each bar's window on whether it sits inside the border, as well as on its id.
  - Switching to or from solid changes the bar's namespace, so the window is remade and maps under the new rule.

### Bar inside the border (`barConfig.insideBorder`)
- This applies to any background except solid, with the border on.
- The bar is on the Top layer like the border, in the `axiom-bar-pill`, `axiom-bar-transparent` or `axiom-bar-floating` (floating bars and floating pills) namespace.
  - Their layer rules (below the border's) make Hyprland arrange the bar after the border and draw it over the border.
- It sits just inside the border with a `-borderWidth` margin, so its outer edge lies on the border's stroke. A pill bar on the border itself reaches back over the whole frame instead (`outerReach`, the screen margin), so it lies as a solid bar does ([Bar ends and pills](bar-ends-pills.md#pills-barcontainerpillrects)).
- A fullscreen window covers it, as it does everything on the Top layer, so it never hides.
- Hyprland counts that margin into the reserved space, so the bar reserves `extent`.
- `RoundedBorders.cornerMargin` pulls the corner pieces back out to the border's corners on such a bar's edge.

### Bars stacked on one edge (`BarEnds.stacksOn`, `placeStack`, `edgeOf`)
- Any number of bars may share an edge on a screen. The compositor lays each out in what the ones arranged before it left, so they lie one inside the other.
- **Order, outer first** (`stacksOn`): the reserving bars by kind (solid, then the border's strip, pills, transparent, floating, floating pills), then the bars reserving nothing, laid over what's left. Bars of one kind keep list order.
  - The kind decides, never the list: a floating bar is always inside a full one on its edge. It keeps its float gap from that bar's inner side (its frame line), as it would from the border's.
  - Floating bars and floating pills share a layer rule, and so do two bars of one kind, so the compositor breaks the tie by map order. Each bar's `LayerSlot` maps it by its `layerRank` (`BarEnds.layerRanks`: floating before floating pills, then list order), and a bar remade later maps again in its place ([layer arrangement](../compositor/layer-arrangement.md#mapping-in-order)).
- **Where each lies** (`placeStack`, added to every `ScreenEdgeManager.bars` entry): `outer` (its window's outer edge from the screen edge), `zone` (the exclusive zone `BarPanel` sets), `taken` (what it reserves, its outer margin counted), `frame` (its inner side), `outerReach` (that margin: `borderWidth` inside the border, the screen margin for a pill bar on the border), `stripCover`, `innermost`, `facesWindows`, `offBorder`.
  - A bar inside the border keeps its `-borderWidth` margin when stacked: its outer edge reaches back onto the far stroke of the bar outside it (a pill's or island's), as onto the border's.
  - **Trim:** only a bar facing the windows (`facesWindows`: none inside it reserves) reserves gaps_out short of a transparent edge. A transparent bar with a floating bar next inside it reserves that bar's float gap short, so the islands sit its padding from its widgets, as the bar outside it does (an inner accent line is an edge to see: no trim). Any other bar with a reserving bar inside it reserves its whole extent, so the next bar never overlaps it.
  - **Solid bars:** the border's strip lies over the innermost reserving solid bar alone, which reserves the strip's overlap less. A solid bar outside it reserves its whole extent and has no stroke at its inner edge with the border on (`offBorder`), so its popouts open no stroke there (`SurfaceContext.layout`).
  - **`offBorder`** is also a bar inside the border with another inside the border outside it: its pills open no border stroke (`BarContainer.borderOpening`), as the border's stroke isn't there.
- **What the edge is left with** (`edgeOf`, read through `ScreenEdgeManager.edgeOn`): `reserved` (the border's margin and every bar's `taken`), `frame` (the innermost bar's), `corner` (past the reserving solid bars and the strip), `strip`, `solidZone`, `insideTaken`, `facing` (the innermost reserving bar, where `reserved` ends: the overlay's margin reads its trim, `ReservedAreaWindow`). `barReservedOn`, `frameLine` and `cornerLine` are these; `RoundedBorders` pulls its corner pieces out past `insideTaken`, insets its shadow by `solidZone`, and leaves its strip clear over a solid bar while `strip`.
- Surfaces arranged after every bar (edge popouts, docks, floating menus, the OSD) meet the innermost bar (`edgesFor`, `barOn`); a bar's own popouts grow out of their bar wherever it lies (`ScreenEdgeManager.barFrameLineOn`, [Surface context](../popouts/surface-context.md)), or past the connected bars inside it.
- **Connected run** (`BarEnds.connectedFrom`, each entry's `attachId`): a solid or pill bar's popouts grow out of the innermost of the reserving solid and pill bars lying inside it, as an edge popout would: out of the pill under them, stretched to carry them, or between pills from the border over the pill bar's empty room. The run stops at a transparent or floating bar (a popout covers those, on the Overlay layer), a bar reserving nothing and a pill bar off the border.
- **Covered bars give way** (`BarEnds.coveredSpans`, `ScreenEdgeManager.coveredOn`, `BarContainer.coveredSpans`): a popout's fill is drawn in the blur window, under every bar, so it can't hide the bars it covers. While a bar outside one has a popout open over it (not one grown out of it or a bar inside it), its islands, sections and accent line under that popout's footprint fade out, an island's fill and shadow leaving the blur window. A pill bar's pills stay: the popout runs past them and merges with them, as an edge popout does. A pill bar inside another pill bar doesn't (its own [issue](../issues.md#a-pill-bar-stacked-inside-another-pill-bar-grows-its-pills-out-of-nothing)).
- A transparent bar's detached popouts clear the whole stack, in line with the windows ([Pill and floating bars](../popouts/pill-and-floating-bars.md#transparent-bars-detached-popouts)).
- **Known limit:** a bar reserving no space is laid over what the reserving bars leave, so it ends the connected run (`connectedFrom`) and an outer bar's popout covers it, pills included: that layout is the user's to avoid (reserve its space).
- **Known limit:** a pill bar inside another pill bar grows its pills out of that bar's inner side, where only the outer bar's pills have a stroke; between them its pills' outer side is open ([issue](../issues.md#a-pill-bar-stacked-inside-another-pill-bar-grows-its-pills-out-of-nothing)). Inside a solid bar it lies on the border's stroke as ever.

### Bars sharing a corner (`methods/BarEnds`, `tests/tst_BarEnds.qml`)
- Hyprland gives a corner to the bar it arranges first. The other bar's window ends at its reserved line.
- Which bar that is depends on the layer rule, never on which mapped first. First to last: solid bars, the border, pill bars, transparent bars, floating bars and floating pills (orders: [layer stacking](../generated/layers.md), from `LayerStack.layers`; `tst_LayerStack` holds them to this order).

  - A floating bar always makes way.
  - Between bars of one kind, the bar on the screen's longer edge makes way (the `-long` namespace), so the shorter bar gets the corner: side bars on a landscape monitor, top and bottom ones on a portrait one (`shortEdge`, `BarEnds.onShortEdge`).
  - Solid bars can't tie with pill bars: a solid bar is arranged before the border, a pill bar after it.
  - Docks, the overlay, the OSD and popouts are ordered after every bar.
  - The namespace comes from `BarsConfig.layerNamespace`. `qml/shell/Bar` keys each window on it, since `order` is read only as a surface maps: a bar changing kind, or a monitor rotating, remakes the window.
- A bar reserving nothing takes no corner.
- **Against a stack:** an end makes way for each bar on the perpendicular edge that Hyprland arranges before it. Layer rules order kinds the same on every edge, so that's the outer part of the stack. The end meets the innermost of them (its `barId`), and its window starts past them all (`from`, `BarEnds.endsOf`). So a top pill bar on a landscape screen merges into a left pill bar's end, while the transparent bar inside that left bar makes way for the top bar.

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
- A solid bar reserving its edge under the border casts no shadow of its own (`BarsConfig.enrichBarConfig`'s `borderShadowed`).
- `BarsConfig.shadowColor` resolves the color for both the border and the bar shadows (see [Widget shapes](widget-shapes-runs.md#bar-shadow)).
