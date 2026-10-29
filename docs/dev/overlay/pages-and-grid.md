# Overlay pages and the module grid

> **Files:** `shell/Overlay.qml`, `components/hosts/overlay/OverlayPanel.qml`, `components/hosts/overlay/OverlayPages.qml`, `components/hosts/overlay/OverlayGrid.qml`, `components/hosts/overlay/ModuleGrid.qml`, `components/hosts/overlay/OverlaySlot.qml`, `components/hosts/overlay/OverlayPageNavigator.qml`, `components/views/base/BaseView.qml`, `components/views/Custom/Custom.qml`, `components/methods/GridPlacement.qml`, `config/OverlayConfig.qml`
> **Config:** `Overlay.items`, `Overlay.moduleScale`, `Widget.cardSize`, `Widget.scale`, `Overlay.navigator`, `Overlay.navigatorLabels`, `Overlay.animation`, `Overlay.showBackdrop`, `Overlay.backdrop`
> **Related:** [Streamed building](../core/streamed-building.md), [Content roots](content-roots.md), [Writing modules](writing-modules.md), [Layouts editor](layouts-editor.md), [Edge menus](../edge-menus/overview.md)

How the overlay turns `Overlay.items` into pages, and a page's modules into a grid of slots: views, the pure grid maths in `GridPlacement`, per-screen card sizing and what is loaded when. Read this before touching a view, the grid or overlay loading.

### Views, modules and places
- `Overlay.items` in the schema drives the overlay's pages, just as `Bars` drives the bar.
- A Custom view is a grid of modules, each with a `place` `{ x, y, w, h }` in **grid units, four to a card** (a quarter card each).
- With `grid.fine` ("Double grid") there are eight units to a card:
  - `Custom.qml` lays the page out at `OverlayConfig.pageUnit`, `GridPlacement.fineUnit`: two of its units and their gap span one card unit exactly.
  - `OverlayManager.fitOf` and the onboarding fit use it too.
  - Toggling it rescales the places (`GridPlacement.scalePlace`), as for edge menus and screen layouts.
- Everything loads by naming convention, so there are no lookup tables.
- Views and modules are `oneOf`s discriminated by `type`, like `BarWidget`.

### View (`OverlayPages` → `OverlayView`)
- `components/views/<type>/<type>.qml`, a `BaseView` that receives the screen's `grid` and its `viewConfig`.
- `BaseView` gives hand-built pages their sizes: `pageHeight` (two cards), `cardPageWidth`, `sideWidth`.
- `Custom` (`views/Custom/Custom.qml`) is one `ModuleGrid` of its `modules`, with its own `icon` in the navigator (`OverlayConfig.pageIcon`; empty is the type's).
- Tool pages (`x-tool`), hand-built with their pieces in `views/<page>/`: `Settings`, `BarEditor`, `Themes`, `Keybinds`, `Monitors`, `CalendarPage`.
  - `CalendarPage`: the month with its events, the selected day's `DayPane`, and the calendars to switch on and off. It is not named `Calendar`, which `views/Themes`' import of `content/` would see twice.
  - The Themes page is described in [Themes](../theming/themes.md).
- `Layouts` (the layouts editor, `views/Layouts/`) is pinned, not in config: see [Layouts editor](layouts-editor.md).
- `ShellManager.showOverlayPage(type)` switches the overlay to a page. `axiom ipc overlay page <type or name>` opens it on one.

### Grid maths (`methods/GridPlacement`)
Pure, tested by `tst_GridPlacement`.
- `unitOf(card)`: a unit's size, `(card - 3 × spacing) / 4` (110 px at the reference 500).
- `span(n)`: n units plus the gaps between, so `span(4)` is a card and `span(2)` half of one.
- `bounds(modules)`: how far they reach.
- `canPlace` / `overlaps`: keep modules apart (holes are fine).
- `firstFree(modules, w, h)`: finds a spot in reading order, else beside (or below a wide grid).
- `revealOrder(modules)`: each module's rank when a page streams them in, by diagonal (`x + y`), then the higher.
- `normalize`: shifts a grid so its top left module sits at 0, 0.
- `trackSizes(bounds, unit, stretch)`: one unit's width and height and the grid's size, growing either axis evenly into `stretch` room (never shrinking).
- `rectPx(place, sizes)`: places a module.
- `fitScale`: how much an overlay's room shrinks a page.
- Edge menu geometry (see [Edge menu hosts](../edge-menus/hosts.md)):
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
- Its `host` (handed to each module) is `{ kind: "overlay" }`; a Custom page adds `bare: !OverlayConfig.moduleBorders` (`Overlay.moduleBorders`, one setting for every page, like `Overlay.moduleScale`) and `padded: true`, so with module borders off its modules drop their card box but keep their padding.
- Growing modules are laid out here too: see [Growing and expanding](grow-expand.md).

### Module (`OverlaySlot`)
- Loads `content/<type>/<type>.qml`, filling its place. Its root is `Card` or `Panel`: see [Content roots](content-roots.md).
- `OverlaySlot` imports `qs.components.content` so that `qs` scans the URL-loaded content; without it, their own `qs.*` imports fail with "not installed".
- Adding a module type: see [Writing modules](writing-modules.md).

### Sizing (per screen)
Cards follow the screen; text and controls don't. A monitor's cards are its card size (`OverlayConfig.cardUnitOn`: two cards fill its short side less `GridPlacement.screenMargin` each side, `GridPlacement.baseCard`, times `Widget.cardSize`%), the same turned either way and on every surface. Content lays out at the card's real size, so text is the Interface scale's (`Widget.scale`) on every monitor; only a Module size zooms it.
- Each `OverlayPanel` has an `OverlayGrid` (`hosts/overlay/`) on the page area beside the navigator (`OverlayConfig.navigatorRoom`), less a `cardSpacing` margin and the box's padding (`OverlayConfig.boxPadding`, at the Interface scale, not zoomed) on each side (`OverlayConfig.layoutFor`, `GridPlacement.overlayLayout`, tested in `tst_GridPlacement`):
  - `drawnUnit`: the card size on its screen times `Overlay.moduleScale`%, at most what lets a page two cards high (two cards and a gap) fill the height.
  - `zoom`: `Overlay.moduleScale` as a factor (`GridPlacement.zoomOf`: 1 within 2 %, so content isn't resampled for nothing).
  - `unit`: the card size content lays out at, `drawnUnit / zoom`. Bigger text (the Interface scale) fits less in each card.
  - `roomWidth` / `roomHeight`: the room in layout px, what views size against (`BaseView.editorWidth`).
- Views receive it as `grid` (`BaseView`) and size everything from `grid.unit` / `grid.span(n)` / `grid.sizes(bounds, stretch)`, passing plain numbers down to content. Text and widget sizes stay the shell's px tokens; the zoom scales them with the cards.
- `OverlayPages` draws the current page at `contentZoom` (`zoom × fitScale`, Item.scale on the views' container); its box is sized in drawn px, so its border and radius stay crisp.
  - Edge menus, the desktop, the lock screen and the greeter zoom each module's content instead (`ModuleGrid.zoom`), keeping their grid in drawn px with its gaps scaled to its cards (`OverlayGrid.gap`, `GridPlacement.gapOf`), so the grid is the overlay's scaled: see [Edge menu hosts](../edge-menus/hosts.md).
  - `StyledIcon` finds the `contentZoom`s up its parents (multiplied) and, scaled, draws unfilled symbols with the distance-field renderer (a native glyph blurs when scaled; a filled one stays native, as distance fields blot its contours).
- A page that still doesn't fit (wider than the screen, higher than two cards) is shrunk as a whole by `OverlayPages.fitScale`.
- The panel reports its room before shrinking, in layout px, and its `unit` to `OverlayManager.reportArea`: the layouts editor's "fits" line (`fitOf`), which the layouts editor's page fits read. Edge menus, the desktop, the lock screen and the greeter don't use it: they start from `OverlayConfig.cardUnitOn` (the card size without the overlay's own Module size, and without bars), so they look the same whether an overlay is open or not, and their cards match the overlay's at the same Module size wherever the overlay isn't capped by its height.
- `cardSpacing` and the card padding (`OverlayConfig.cardPad`, from `Widget.cardPadding`: the density's, at the Interface scale) are layout px: they scale with the zoom. A grid drawn in drawn px (`OverlayGrid.fixedUnit`) takes `gapOf` its zoom as its `gap`; every `GridPlacement` size helper takes that gap (`unitOf`, `span`, `stepOf`, `fineUnit`, `trackSizes`, whose `sizes.gap` `rectPx` reads, and the menu and screen lattices).
- The onboarder (`OnboardingWindow`) works out the same grid and draws its pages at the same zoom, so its Welcome page previews `Widget.cardSize` and `Widget.scale`.

### Loading
- One overlay per screen in `General.screens` (`shell/Overlay.qml`): a transparent `OverlayPanel` inside the reserved area, placed by its base `ReservedAreaWindow` (shared with the onboarder).
- Under it, its `reusable/BackdropRequest` dims the whole monitor under the bars and border (the screen's `ScreenBackdrop` window), as dark as `Overlay.backdrop` while `Overlay.showBackdrop`.
  - It comes in as the overlay does (`Overlay.animation`): sliding from the top or bottom edge (the request's `slide`), or fading.
  - A Top-layer surface kept under them by a Hyprland `order` layer rule that `HyprlandManager` adds at startup and on config reload.
  - The workspace overview and launcher use it too.
- Its focus grab (`HyprlandGrab`) also whitelists `SurfaceManager.grabPartnersFor(screen)`. The bars, bar popouts and submenus register themselves there (`registerGrabPartner(window, screenName)`), so they keep working while it's open.
- Only the current page and its neighbours (navigation wraps) are instantiated, and only while the overlay is open (`OverlayPages.isLoaded` → `OverlayPage.loaded`). (Rule: AGENTS.md › UI conventions, Overlay lifetime.)
  - Opening or switching builds only the page shown. Its neighbours follow the page the user settled on (`OverlayPages._settled`, set `Appearance.animSlow` after the open or the switch), so they're built once it has slid in, not in the same frame.
  - A Custom page's modules stream in (`ModuleGrid.stream`): the grid and its box are built at once, sized from the places, and each module is a job in `BuildQueueManager`'s queue, top left to bottom right (`GridPlacement.revealOrder`), fading in (`OverlaySlot.active` / `ready`). Tool pages stream their panels the same way (`StreamedLoader`). Edge menus, the lock screen, the greeter, the desktop and screen layouts build all of their modules with the grid. The mechanics, and what each tool page streams: [streamed-building](../core/streamed-building.md).
  - The panel keeps the page area's last mapped size (`pageArea.roomWidth` / `roomHeight` in `OverlayPanel`): the window has no size while unmapped, and building at an estimate laid every page out twice per open. Before the first map it estimates from the screen less the window's margins.
  - Timing: each page logs `Overlay page N built in X ms` and a streamed grid `Overlay modules streamed in X ms` (`--debug`); `scripts/dev/bench_overlay.sh` prints them per step ([streamed-building › Measuring](../core/streamed-building.md)).
- Page order (`OverlayPages.buildViewsModel`; `viewsModel[i].index` is the view's place in config):
  1. the user's own (Custom) pages, in config order;
  2. the tool pages (view types with `x-tool`: Settings, BarEditor, Themes, Keybinds, Monitors, CalendarPage), in config order;
  3. the pinned Layouts page.
- A view with `visible: false` stays in config but isn't shown.

### Navigator
- `OverlayPageNavigator`, pinned to the screen's bottom or top edge (`Overlay.navigator`), shows a tab per page with a sliding accent pill. It's pinned to the edge, not the box, since the box changes height with each page.
- Tabs come from `OverlayPages.pages`: icon, name and `tool` from `OverlayConfig.viewIcon` / `viewLabel` / `isTool`, shared with the layouts editor.
- Tool tabs follow a divider as icons only (named in a tooltip), even when current.
- `Overlay.navigatorLabels`: `auto` drops the other tabs to icons when all names don't fit; `current` names only the current tab; `icons` names none.
- **Links and the way back.** A link to another page (`SettingsLink`, a settings header link, the layouts editor's "Also opened by" rows, Edit in Layouts) goes through `ShellManager.followLink(type)`. `OverlayPages` keeps the page it left as `ShellManager.linkOrigin`, and the navigator shows a back chip (back arrow and that page's icon) before its arrows until the user navigates themselves (`step`, a tab), another switch comes from outside, or the overlay closes. The chip calls `ShellManager.followLinkBack()`. A link within the same page keeps the way back it already has.
- **Scroll memory.** Pages are unloaded while the overlay is closed, so their panels keep where they were scrolled to in `EditsManager` (`TitledCard.scrollKey`, `reusable/ScrollMemory`): the settings categories and sidebar, Themes, Keybinds' list and key map, the bar editor and its widget inspector (per widget), Layouts and its module inspector (per module), Monitors and its inspector.
