# Overlay pages and the module grid

> **Files:** `qml/shell/Overlay.qml`, `qml/components/hosts/overlay/OverlayPanel.qml`, `qml/components/hosts/overlay/OverlayPages.qml`, `qml/components/hosts/overlay/OverlayGrid.qml`, `qml/components/hosts/overlay/PageBox.qml`, `qml/components/hosts/overlay/OverlayPage.qml`, `qml/components/hosts/overlay/ModuleGrid.qml`, `qml/components/hosts/overlay/OverlaySlot.qml`, `qml/components/hosts/overlay/OverlayPageNavigator.qml`, `qml/components/views/base/BaseView.qml`, `qml/components/views/Custom/Custom.qml`, `qml/components/methods/GridPlacement.qml`, `qml/components/methods/Sizing.qml`, `qml/config/OverlayConfig.qml`
> **Config:** `Overlay.items`, `Widget.cardSize`, `Widget.contentSize`, `Overlay.navigator`, `Overlay.navigatorLabels`, `Overlay.animation`, `Overlay.showBackdrop`, `Overlay.backdrop`
> **Related:** [Streamed building](../core/streamed-building.md), [Content roots](content-roots.md), [Writing modules](writing-modules.md), [Layouts editor](layouts-editor.md), [Menus](../menus/overview.md)

How the overlay turns `Overlay.items` into pages, and a page's modules into a grid of slots: views, the pure grid maths in `GridPlacement`, per-screen card sizing and what is loaded when. Read this before touching a view, the grid or overlay loading.

### Views, modules and places
- `Overlay.items` in the schema drives the overlay's pages, just as `Bars` drives the bar.
- A Custom view is a grid of modules, each with a `place` `{ x, y, w, h }` in **grid units, four to a card** (a quarter card each).
- With `grid.fine` ("Double grid") there are eight units to a card:
  - `Custom.qml` lays the page out at `OverlayConfig.pageUnit`, `GridPlacement.fineUnit`: two of its units and their gap span one card unit (rounded down, never over).
  - `OverlayManager.fitOf` and the onboarding fit use it too.
- Each page has its own `sizing` (`Overlay.items[].sizing`, picked by its view type's schema: a Custom page's `PageSizing`, a tool page's `ToolSizing`): see [Sizing](#sizing).
  - Toggling it rescales the places (`GridPlacement.scalePlace`), as for menus and screen layouts.
- Everything loads by naming convention, so there are no lookup tables.
- Views and modules are `oneOf`s discriminated by `type`, like `BarWidget`.

### View (`OverlayPages` → `OverlayView`)
- `qml/components/views/<type>/<type>.qml`, a `BaseView` that receives the screen's `grid` and its `viewConfig`.
- `BaseView` gives hand-built pages their sizes, in whole pixels: `pageHeight` (two cards; a page window's height in a window, `windowed`), `cardPageWidth`, `sideWidth`, and for tool pages `pageWidth` (side + editor + gap: every tool page is this wide, so switching pages never changes the overlay box), `inspectorWidth` and `listWidth` (the page less the inspector). Tool pages are built on `ToolPane`/`WorkArea` ([editors pattern](../core/editors-pattern.md)).
- `Custom` (`views/Custom/Custom.qml`) is one `ModuleGrid` of its `modules`, with its own `icon` in the navigator (`OverlayConfig.pageIcon`; empty is the type's).
- Tool pages (`x-tool`), hand-built with their pieces in `views/<page>/`: `Settings`, `BarEditor`, `Themes`, `Keybinds`, `Monitors`, `CalendarPage`, `CustomWidgets`, `WindowRules`.
  - `CalendarPage`: the month with its events, the selected day's `DayPane`, and the calendars to switch on and off. It is not named `Calendar`, which `views/Themes`' import of `content/` would see twice.
  - The Themes page is described in [Themes](../theming/themes.md).
- `Layouts` (the layouts editor, `views/Layouts/`) is pinned, not in config: see [Layouts editor](layouts-editor.md).
- `ShellManager.showOverlayPage(type)` switches the overlay to a page. `axiom ipc overlay page <type or name>` opens it on one.
- Tool pages with `x-window` can open in a window of their own instead, with a box in their place here meanwhile: [page windows](page-windows.md).

### Grid maths (`methods/GridPlacement`)
Pure, tested by `tst_GridPlacement`.
- `unitOf(card)`: a unit's size, `(card - 3 × spacing) / 4` (110 px at the reference 500).
- `span(n)`: n units plus the gaps between, so `span(4)` is a card and `span(2)` half of one.
- `bounds(modules)`: how far they reach.
- `canPlace` / `overlaps`: keep modules apart (holes are fine).
- `firstFree(modules, w, h)`: finds a spot in reading order, else beside (or below a wide grid).
- `revealOrder(modules)`: each module's rank when a page streams them in, by diagonal (`x + y`), then the higher.
- `normalize`: shifts a grid so its top left module sits at 0, 0.
- `trackSizes(bounds, unit, stretch)`: one unit's width and height and the grid's size, growing either axis evenly into `stretch` room (never shrinking). Units may be fractional; the grid's size is rounded to whole px.
- `rectPx(place, sizes)`: places a module, each edge rounded to a whole px (not its size, so neighbours keep their gap). Each slot clips its module, and a clip on a fractional edge shaves the pixel a module draws its stroke in (a borderless Chat's composer in an edge menu).
- `fitScale`: how much an area's room shrinks modules reaching some bounds.
- `overlayLayout(height, card, zoom)`: a page's drawn card, unit and zoom, and whether the height capped the cards (see [Sizing](#sizing)).
- Edge menu geometry (see [Menu hosts](../menus/hosts.md)):
  - `menuLattice` / `latticeOf`: the cells a menu sits on along its edge. As many as fit between the frame's pads, centred there, moved `gridOffset` px.
  - `menuCell` / `alongStart` / `menuAlong`: where its modules start (centred on the lattice, `offset` cells on, kept on it).
  - `offsetFor` / `offsetRange`: the offset for a cell, and those that keep it on the lattice.
  - `unitsAlong`, `menuPlacement` (where they sit on the screen, in px), `menuOnScreen` (its box and modules' rects there), `menuReservedDepth`, `screenBox`.
- The layouts canvas (see [Grid canvas](grid-canvas.md)):
  - `canvasExtent`: the units drawn around the grid, and the `view` fitted (a menu's screen and a unit round it, in fractions, so the screen stays put while modules move on it).
  - `canvasFit`: the view's scale and origin in the area.
  - `canvasRect` / `canvasScreenRect`.
  - `canvasDropPlace`: where a carried module lands, held by the unit it was grabbed by.
  - `edgeBand` / `edgeBar`.

### Host (`hosts/overlay/ModuleGrid`)
- Sizes itself from `grid.sizes(bounds, stretch)`.
- Places one clipped `OverlaySlot` per module (keyed by count), passing `GridPlacement.rectOf(place)` as the module's `slotRect`.
- Warns once for a module that overlaps another.
- Its `host` (handed to each module) is `{ kind: "overlay" }`; a Custom page adds its name as `page`, `bare: !OverlayConfig.moduleBorders` (`Overlay.moduleBorders`, one setting for every page) and `padded: true`, so with module borders off its modules drop their card box but keep their padding.
- Growing modules are laid out here too: see [Growing and expanding](grow-expand.md).

### Module (`OverlaySlot`)
- Loads `content/<type>/<type>.qml`, filling its place. Its root is `Card` or `Panel`: see [Content roots](content-roots.md).
- `OverlaySlot` imports `qs.components.content` so that `qs` scans the URL-loaded content; without it, their own `qs.*` imports fail with "not installed".
- Adding a module type: see [Writing modules](writing-modules.md).

### Sizing
Two sizes everywhere: **Card size** (how big module cards are) and **Content size** (text and controls inside them). Look & Feel holds the global pair (`Interface.cardSize`, `Interface.contentSize`, read as `Widget.cardSize` and `Widget.contentSize`); a surface may scale them with its own `sizing`, each level a multiplier on the one above (a level left alone counts as 100%).

| Level | Card size | Content size | Linked | Definition |
|---|---|---|---|---|
| Global (`Interface`) | `cardSize` % | `contentSize` % | no link | personal |
| Custom page | factor 50-100 | factor 50-100 | yes | `PageSizing` |
| Tool page | follows Content | factor 50-100, zooms the whole page | none | `ToolSizing` |
| Edge menu, desktop item, lock screen, login screen | factor 50-200 | factor 50-200 | yes | `Sizing` ([menus](../menus/hosts.md)) |
| Built-in bar popout (popout on, no menu) | follows Content | factor 50-200, zooms the whole popout | none | `ContentSizing` (`PopoutSizing`) ([popouts](../popouts/hosts-and-switching.md#sizing)) |
| Custom widget popout | factor 50-200 | factor 50-200 | yes | `Sizing`, personal like the widget ([popouts](../popouts/hosts-and-switching.md#sizing)) |
| Module (on any surface) | its grid's w × h | factor 50-200 | none | ModuleBase `contentSize` |

- The Layouts page isn't in config: it follows the global sizes alone.
- **Applied, not shown.** The global percentages are already inside `OverlayConfig.cardUnitOn` (the card) and `Widget` / `Appearance` / `Style` (the content). A host applies only its surface's factors, `Sizing.factors(sizing)` → `{ card, content }`, never multiplies by hand:
  - with a `linked` (a Custom page, a menu): the card is `cardSize`'s factor, the content follows it while `linked`, else is `contentSize`'s;
  - without one (a tool page): the whole page zooms, card and content the one `contentSize` factor, which keeps a tool page's drawn cards at the card size times its zoom and its `unit` the card size itself.
- A `null` size follows the level above. Turning "Set by hand" on stores 100, so nothing moves. Unlinking writes `contentSize` the cards' size in the same edit and linking again drops it (`Sizing.edited` / `editedIn`, called at each edit point: `OverlayManager.updateViewField` for a page, `BarManager.updateWidgetProperty` for a widget's popout).
- A module's own `contentSize` (`modules[].contentSize`, beside `place`; a % or null) multiplies onto its surface's zoom for that slot alone: `ModuleGrid` hands `OverlaySlot` `Sizing.moduleZoom(grid zoom, contentSize)`, the one place the factors meet. On an overlay page (the page zooms as a whole, the grid's zoom is 1) it is the factor alone. An expanded module keeps the surface's zoom, not the module's. It is edited in the Layouts inspector's Content size row, a `SchemaPropertiesForm` on `OverlayConfig.moduleInfo(type).contentSize` (the schema comes from the expanded type, as the kind base is gone then), through `GridEditor.updateModuleField` (undo key `index:@contentSize`).
- Ranges: pages 50-100 (the two-cards-high cap below shrinks cards, not the zoom); menus, screen layouts, popouts and modules 50-200.

Cards follow the screen; text and controls don't. A monitor's cards are its card size (`OverlayConfig.cardUnitOn`: two cards fill its short side less `GridPlacement.screenMargin` each side, `GridPlacement.baseCard`, times `Widget.cardSize`%), the same turned either way and on every surface. Content lays out at the card's real size, so text is the Content size's (`Widget.contentSize`) on every monitor; only a surface's Content size factor zooms it.
- Every overlay page, page window and the onboarder has an `OverlayGrid` (`hosts/overlay/`) of its own `sizing`. In the overlay it is the page area beside the navigator (`OverlayConfig.navigatorRoom`), less a `cardSpacing` margin and the box's padding (`OverlayConfig.boxPadding`, at the Content size, not zoomed) on each side, that gives its room (`OverlayConfig.layoutFor(screen, width, height, sizing)`, `GridPlacement.overlayLayout`, tested in `tst_GridPlacement`; one object, so a page's card, zoom and cap never come from two bindings):
  - `drawnUnit`: the card size on its screen times the page's Card size factor, at most what lets a page two cards high (two cards and a gap) fill the height, rounded down so such a page fits exactly instead of being shrunk by a hair. `layoutFor` also says whether the height `capped` it.
  - `zoom`: the Content size factor (`GridPlacement.zoomOf`: 1 within 2 %, so content isn't resampled for nothing). The cap doesn't reduce it.
  - `unit`: the card size content lays out at, `drawnUnit / zoom` (rounded down). Bigger text (the Content size) fits less in each card.
  - `roomWidth` / `roomHeight`: the room in layout px, what views size against (`BaseView.editorWidth`).
- Views receive it as `grid` (`BaseView`) and size everything from `grid.unit` / `grid.span(n)` / `grid.sizes(bounds, stretch)`, passing plain numbers down to content. Text and widget sizes stay the shell's px tokens; the zoom scales them with the cards.
- Each `OverlayPage` draws its page in a `PageBox` at `contentZoom` (`zoom × fitScale`, Item.scale on the box); the overlay's box (a `page` Surface with the `borderSubtle` hairline) is sized in drawn px to the current page's (`OverlayPage.drawnWidth` / `drawnHeight`), so its border and radius stay crisp. It casts a soft shadow (`Style.shadowSoft`, an `OutsideShadow` of a plain copy of the box's shape) while the shell's shadow switch is on, except where the compositor's blur would frost it (`Appearance.blur && BlurManager.shadowsApart`). `PageBox` is the one piece that scales a page: the overlay's pages, `PageWindow` and the onboarder all use it, with the room (`roomWidth` / `roomHeight`), `fitHeight` (off for a window, which fills its height) and `fitCap` (the onboarder's) they differ in.
  - The box scales from its top left, placed on a whole px, and the grid knows what it's drawn at (`OverlayGrid.drawnZoom`, which each host binds to its `PageBox.contentZoom`), so `GridPlacement.rectPx` puts every slot's edges on whole drawn px: each card's border falls on the screen's pixels alike, never smeared over two at some zooms.
  - Menus, the desktop, the lock screen and the greeter zoom each module's content instead (`ModuleGrid.zoom`), keeping their grid in drawn px with its gaps scaled to its cards (`OverlayGrid.gap`, `GridPlacement.gapOf`), so the grid is the overlay's scaled: see [Menu hosts](../menus/hosts.md).
  - `StyledIcon` finds the `contentZoom`s up its parents (multiplied) and, scaled, draws unfilled symbols with the distance-field renderer (a native glyph blurs when scaled; a filled one stays native, as distance fields blot its contours).
- A page that still doesn't fit (wider than the screen, higher than two cards) is shrunk as a whole by its `PageBox.fitScale` (the room over what the page draws, width and height; at most 1, or `fitCap`).
- A page slides in `OverlayPage`, which moves its own `PageBox`: during a slide between pages of different sizes the box resizes, as it does for pages of different widths. Tool pages (`BaseView.pageWidth`) are the same width at the same Content size, so switching between them never resizes the box; two tool pages at different Content sizes differ in width.
- Each `OverlayPanel` reports its room before shrinking, in drawn px, with its screen's size to `OverlayManager.reportArea`, and `OverlayManager.fitOf(view)` works a Custom page's own layout and fit on each screen from them (`layoutFor` with the page's `sizing`, then `GridPlacement.fitScale`): the layouts editor's "fits" line. Menus, the desktop, the lock screen and the greeter don't use it: they start from `OverlayConfig.cardUnitOn` (the card size without a page's own sizing, and without bars), so they look the same whether an overlay is open or not, and their cards match a page's at the same sizing wherever the overlay isn't capped by its height.
- `cardSpacing` and the card padding (`OverlayConfig.cardPad`, from `Widget.cardPadding`: the density's, at the Content size) are layout px: they scale with the zoom. A grid drawn in drawn px (`OverlayGrid.fixedUnit`) takes `gapOf` its zoom as its `gap`; every `GridPlacement` size helper takes that gap (`unitOf`, `span`, `stepOf`, `fineUnit`, `trackSizes`, whose `sizes.gap` `rectPx` reads, and the menu and screen lattices).
- The onboarder (`OnboardingWindow`) works out a grid of the overlay's first Custom page's sizing and draws its pages at the same zoom, so its Welcome page previews `Widget.cardSize` and `Widget.contentSize`.

### Loading
- One overlay per screen in `General.screens` (`qml/shell/Overlay.qml`): a transparent `OverlayPanel` inside the reserved area, placed by its base `ReservedAreaWindow` (shared with the onboarder).
- Under it, its `reusable/BackdropRequest` dims the whole monitor under the bars and border (the screen's `ScreenBackdrop` window), as dark as `Overlay.backdrop` while `Overlay.showBackdrop`.
  - It comes in as the overlay does (`Overlay.animation`): sliding from the top or bottom edge (the request's `slide`), or fading.
  - A Top-layer surface kept under them by a Hyprland `order` layer rule that `HyprlandManager` adds at startup and on config reload.
  - The workspace overview and launcher use it too.
- Its focus grab (`HyprlandGrab`) also whitelists `SurfaceManager.grabPartnersFor(screen)`. The bars, bar popouts and submenus register themselves there (`registerGrabPartner(window, screenName)`), so they keep working while it's open.
- Opening it closes the bar popouts and floating edge menus on its screen (`PopoutManager.closeOn`), which keep their layer while open and would end up under it; integrated menus, docks, OSDs and the launcher stay.
- Close on outside click (`Overlay.closeOnOutsideClick`) is a real click on its own empty background only, outside the page and the navigator (`backgroundClicks`), on every compositor: a click on another monitor, the screen border or a floating bar's gap leaves it open. Its grab ending never closes it: that's also keyboard focus leaving (a polkit prompt closing gives it back to the last app) or, on Hyprland, another surface's grab starting over it (one native grab at a time).
- Only the current page and its neighbours (navigation wraps) are instantiated, and only while the overlay is open (`OverlayPages.isLoaded` → `OverlayPage.loaded`).
  - Opening or switching builds only the page shown. Its neighbours follow the page the user settled on (`OverlayPages._settled`, set `Appearance.animSlow` after the open or the switch), so they're built once it has slid in, not in the same frame.
  - A Custom page's modules stream in (`ModuleGrid.stream`): the grid and its box are built at once, sized from the places, and each module is a job in `BuildQueueManager`'s queue, top left to bottom right (`GridPlacement.revealOrder`), fading in (`OverlaySlot.active` / `ready`). Tool pages stream their panels the same way (`StreamedLoader`). Edge menus, the lock screen, the greeter, the desktop and screen layouts build all of their modules with the grid. The mechanics, and what each tool page streams: [streamed-building](../core/streamed-building.md).
  - The panel keeps the page area's last mapped size (`pageArea.roomWidth` / `roomHeight` in `OverlayPanel`): the window has no size while unmapped, and building at an estimate laid every page out twice per open. Before the first map it estimates from the screen less the window's margins.
  - Timing: each page logs `Overlay page N built in X ms` and a streamed grid `Overlay modules streamed in X ms` (`--debug`); `scripts/dev/bench_overlay.sh` prints them per step ([streamed-building › Measuring](../core/streamed-building.md)).
- Page order (`OverlayPages.buildViewsModel`; `viewsModel[i].index` is the view's place in config):
  1. the user's own (Custom) pages, in config order;
  2. the tool pages (view types with `x-tool`: Settings, BarEditor, Themes, Keybinds, Monitors, CalendarPage, CustomWidgets, WindowRules), in config order;
  3. the pinned Layouts page.
- A view with `visible: false` stays in config but isn't shown.

### Navigator
- `OverlayPageNavigator`, pinned to the screen's bottom or top edge (`Overlay.navigator`), shows a tab per page with a sliding accent pill. It's pinned to the edge, not the box, since the box changes height with each page.
- Tabs come from `OverlayPages.pages`: icon, name and `tool` from `OverlayConfig.viewIcon` / `viewLabel` / `isTool`, shared with the layouts editor.
- Tool tabs follow a divider as icons only (named in a tooltip), even when current.
- `Overlay.navigatorLabels`: `auto` drops the other tabs to icons when all names don't fit; `current` names only the current tab; `icons` names none.
- While any page can open as a window (`x-window`), a pop-out button sits between dividers before the right arrow, enabled only while such a page is current and not already out (dimmed otherwise, so stepping between pages never resizes the navigator). A page that's out gets an `open_in_new` badge on its tab ([page windows](page-windows.md)).
- **Links and the way back.** A link to another page (`SettingsLink`, a settings header link, the layouts editor's "Also opened by" rows, Edit in Layouts) goes through `ShellManager.followLink(type)`. `OverlayPages` keeps the page it left as `ShellManager.linkOrigin`, and the navigator shows a back chip (back arrow and that page's icon) before its arrows until the user navigates themselves (`step`, a tab), another switch comes from outside, or the overlay closes. The chip calls `ShellManager.followLinkBack()`. A link within the same page keeps the way back it already has. A link followed from a page window sets `window:<type>`, and its chip goes back to that window.
- **Scroll memory.** Pages are unloaded while the overlay is closed, so their panels keep where they were scrolled to in `EditsManager` (`TitledCard.scrollKey`, `reusable/ScrollMemory`): the settings categories and sidebar, Themes, Keybinds' list and key map, the bar editor and its widget inspector (per widget), Layouts and its module inspector (per module), Monitors and its inspector. A Notes module keeps each note's place the same way (by its path, [notes](../features/notes.md) › Scrolling).
