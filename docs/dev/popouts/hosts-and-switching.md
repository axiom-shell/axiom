# Popout hosts, window sizing and switching in place

> **Files:** `qml/components/hosts/popout/PopoutWrapperBase.qml`, `qml/components/hosts/popout/BarPopouts.qml`, `qml/components/hosts/popout/EdgePopout.qml`, `qml/components/hosts/popout/AttachedSurface.qml`, `qml/components/hosts/popout/SlideAnimation.qml`, `qml/components/hosts/popout/SwitchStill.qml`, `qml/components/hosts/popout/PopoutAnchor.qml`, `qml/components/hosts/popout/SubmenuHost.qml`, `qml/components/reusable/ZoomLoader.qml`, `qml/config/PopoutsConfig.qml`, `qml/components/methods/Sizing.qml`, `qml/shell/OSD.qml`
> **Config:** `Bars.*.widgets[].properties.popout.sizing`
> **Related:** [Surface context](surface-context.md), [Edge attach](edge-attach.md), [Submenus](submenus.md), [Registry](registry.md), [Content roots](../overlay/content-roots.md), [Pill and floating bars](pill-and-floating-bars.md)

This doc covers the shared host pieces in `qml/components/hosts/popout/`, how a bar popout's window is sized, how it switches to another payload without closing, and how screen-edge popouts sit.

### Shared pieces (`qml/components/hosts/popout/`)
- **`PopoutWrapperBase`:**
  - Open/close/queue state: `isOpen`, `show(data)`, `hide()`, and a timer that dismisses on hover loss, held while an instant action surface is up (`_holdsOpen`, [Modal windows](../core/shell-manager-targeting.md#modal-windows)). A `show()` while it closes queues the open for once it has closed; a `hide()` drops that queued open.
- **`AttachedSurface.hovered`:** the pointer on the whole surface (its `HoverHandler` is reparented to the surface: one declared inside it lands in the content box). `EdgePopout`'s `keepAlive`, `engaged` and `_pointerIn` read it.
  - A wrapper may switch an open popout to another payload in place instead of closing it first, via its `canSwitchTo(anchor, data)` and `prepareSwitch(done)` hooks.
- **Closing on an outside click** (`closeOnClickOutside`: the launcher, a floating edge menu with `close.onOutsideClick`): `EdgePopout` closes on its `FocusGrab`'s `dismissed`, a real click only, never its `cleared`. So a popout opened by hover that takes the keyboard (Todo, Calculator, Stopwatch), another surface's grab starting or a polkit prompt closing leaves it open. A click on a bar closes it too; on sway and niri the bar reports it once released (`BarPanel`), after the click's own action, so the bar's launcher button closes the launcher rather than closing and reopening it.
- **`SlideAnimation`:** slides its content in from its edge, or with `fade` (a detached box whose `animation` is Fade: `EdgePopout.fades`) fades it in and out where it sits; entering its first state as it's made is instant, so a surface made and shown at once slides in; only its states set where it slides, so while hidden it follows its size and its first open slides like every other; its `shownOpacity` is how far it has faded in.
- **Colours (the edge family):** a host's box fills `Style.surfacePage`, outlines `Style.frameStroke` and takes translucency through `Style.edgeFill` at the user's opacity like the bar, so joins and blur copies match; free-standing surfaces use `Surface` (`fillPage`, `borderSubtle`). A fading copy (a toast, a menu tile) fades alone through `BlurShape.fade`.
- **`AttachedSurface`:** the content box, connector and `CornerPiece` fillets that make a popout look like it grows out of a bar or the screen border. `edge` is a `ScreenEdge`.
  - **Attached:**
    - The box starts on the attach edge, with the fillets curving outside its walls (`boxStart`).
    - `boxStart` is pushed back only as far as a box too shallow for its fillet and far corner needs.
  - **Detached:** the box sits half a connector gap past its lead.
    - Past a transparent bar, the lead moves the box in line with the windows (`BarsConfig.detachedPush`), past any bars inside it too. This is negative where the windows start nearer, down to minus half a connector gap.
    - A bar's pills keep that half gap too, since their depth is sized by it.
- **`BarPopouts.qml`:** bar popouts share one wrapper, and one box, per bar. The content's `properties` arrive at `setSource`: a module's filled with its schema defaults (`OverlayConfig.moduleProperties`, over what the payload sends), a schema-less content's as sent (the Workspaces widget's options). The rest of the payload is copied onto the loaded item.

### Bar popout window sizing
- **The window never follows its content.**
  - **Along the bar:** it spans the whole bar (`windowFrom`/`windowTo`).
  - **Across:** it keeps the most room the box has needed since it opened (`BarPopouts.spareAcross`), or the room the content declares up front (`maxImplicitHeight`/`maxImplicitWidth`; the Calendar declares it for its editor).
  - **Surface position:** the surface sits on the bar side, as `EdgePopout.maxContentDepth` does it.
- **Content changing size redraws the scene; it does not resize the Wayland window.** A resize is a compositor round trip, and the outline visibly lagged behind it.
  - **The box animates** to its new size and place (`shownBoxWidth`/`shownBoxHeight`/`shownBoxStart`, `animFast`), starting from the first frame it shows.
  - **The content** sits at its target size, hung from the box's start and bar side, and clipped to the box.
- **Growing while open keeps the controls still** (`BarPopouts.growth`, from `EdgeAttach.growth`). Content sizes to what it shows, from a small minimum, and the box grows away from the side its controls are on.
  - **Which way:** away from a horizontal bar (`up` from a bottom bar). Along a vertical bar the box opens centred on its anchor, then its start stays where it opened and it grows `down`; when the most it can grow to (`maxImplicitHeight`) wouldn't fit below (a widget low on the bar), its end stays and it grows `up`. With room neither way, the way with more. Taken from the box's length once its content is ready (`_openLength`, again after a switch in place).
  - **The content's side:** content reads it as `Panel.growth`. With `Panel.flips` its column shows in reverse order while it grows `up`, so the controls are last, by the bar (`reusable/LayoutOrder`); a panel laid out in a GridLayout swaps its rows with `Layout.row` (AudioMixer instead; Calendar inside its GridLayout, as well as flipping its column).
  - **Which do:** the radio menus (`parts/DeviceList`, 2 rows up to `visibleRows`, 5, Wi-Fi's 6: WifiNetworks, BluetoothDevices, Tailscale), AudioMixer (1 to 4 rows), Notifications (empty, one notification's height, so it only grows), Todo, Stopwatch's laps, Calendar's day.
- **Room to grow:** the window's `popoutRoom` is how much more the box can grow before it meets what's on the screen's far side (along a vertical bar, its ends), from `ScreenEdgeManager.frameLineOn`. Content growing on its own reads it through `QsWindow.window`: a `StyledComboEntry` opens its list inline, no taller than that. An `EdgePopout`'s is `null`: its content doesn't grow the box, so the list keeps to what scrolls around it. Nothing yet keeps content that is already taller than the screen on it.
- **Keyboard:** a popout with a text field sets `wantsKeyboardFocus`.
  - BarPopouts then takes a focus grab and the bar takes keyboard focus on demand.
  - A click outside emits `focusLost`.
- **Mapping only when ready:** content is mapped only once two things are true.
  - **Its payload is in** (`BarPopouts._payloadApplied`). A Loader reports Ready before `onLoaded`.
  - **Its positioners are laid out** (`_layOut`). Row/Column/Grid lay out on polish, which an unmapped window never runs.

  So it never maps small and grows a frame later. On a bottom or right bar the popup would also have to move, and the compositor didn't always follow that.

### Sizing
- **Where it's set:** a bar widget's own popout (`popout.sizing`: its sizes and ranges are in [Sizing](../overlay/pages-and-grid.md#sizing)). The Content size row's description points to a menu for a box and content sized apart (a menu tied as the popout, its own Size group).
- **How it reaches the popout:** `BarWidgetHost.popoutSizing` is the widget's `popout.sizing`; `PopoutAnchor.open()` finds the nearest ancestor declaring it (as `InkHost.find` walks) and puts it in the payload as `sizing`, only when it finds one (a `Submenu` or tray anchor, outside a bar widget, adds no key: `SubPopout` hands every payload key to its content). It also puts `properties` in the payload, when the widget's popout has `properties` (`BarWidgetHost.popoutProperties`) or the anchor a `fromWidget` (the module keys the widget supplies itself, in the module key's unit): the first overlaid by the second, filled with the module's defaults by `OverlayConfig.moduleProperties` at setSource. The payload is a snapshot: an edit in the bar editor reaches a popout on its next open.
- **Laid out small, drawn zoomed:** `PopoutsConfig.layoutFor(screen, content, room, sizing)` → `{ zoom, unit, fit }` (its math: `Sizing.popoutLayout`). The content Loader keeps its own `implicit` size (the layout pair, `contentWidth`/`contentHeight`) and is scaled by `zoom` from its top left, declaring `contentZoom`, `drawnZoom` and `inkHostAbove` (a `ZoomLoader`). Everything about the box and window uses the drawn pair, `Math.ceil(content × zoom)` (`drawnWidth`/`drawnHeight`: the layout pair is an `int`, the product isn't): `targetBox*`, `boxLength`, and the window's declared room (`maxImplicit*` × zoom).
- **Fit:** a popout too big for its screen is shrunk, not run off it. `fit` (at most 1, at least 0.1) is the factor at which the content's layout size, the most it declares (`maxImplicit*` where given, so one that grows while open keeps its zoom), drawn at its zoom fits `contentRoom`: the screen's room for it less the box's chrome, from terms that read neither the box, its length nor the zoom (`Sizing.fitInto`; no binding loop). Across, the room is less `EdgePlacement.contentFromBar`, the deepest the box could attach at its anchor whatever its length, not where it does (`attachAt`, which a box between pills flips with its length), so a box between pills is fitted at a pill's depth. It multiplies card and zoom alike, so `cardUnit` (what content laid out in cards reads: CustomWidget's `_card`) never depends on it. The window still reserves its room up front, at the zoom.
- **Content's room:** `popoutRoom` (read by `StyledComboEntry`) is in the content's px: the room divided by `zoom`.
- **Switching:** `SwitchStill.zoom` (bound to the host's) sizes the still and its grab as the content is drawn; `prepare()` runs before the payload changes, so it reads the outgoing zoom.
- **Submenus:** `SubmenuHost.zoom` (set by `BarPopouts`) gives `SubPopout` the same zoom, for its content Loader, its box and still, and divides `maxContentHeight` by it, so a tray submenu matches its tray popout. Edge popouts and free menus leave it at 1.

### Switching in place
- **When it happens:** a bar popout opened from a widget under the open box, or within a connector gap of it along the bar (`BarPopouts.canSwitchTo`), doesn't close first.
- **The still:** the old content is grabbed as a still (`hosts/popout/SwitchStill`, `grabToImage`), held where it was along the bar.
- **Reload:** the new payload loads under the still.
  - Every payload reloads (`onCurrentDataChanged`), so the same type opened for another widget is rebuilt.
- **While the new content isn't ready:** the window stays up and the box holds its size and place (`SwitchStill.holding`/`held`, from its `snapshot` hook).
- **Once it is ready:** the box glides and resizes to it.
  - The shown-box Behaviors stay on.
  - Given the host's `occupied`, `SwitchStill` also keeps:
    - `showing`: open, with something to show;
    - `settled`: a tick after it first shows, which gates the Behaviors.
  - It ends itself as the host closes.
- **Cross-fade:** the still fades out as the content fades in (`contentOpacity`, animFast).
- **Asked again meanwhile:** the latest payload wins, and a switch also calls off a close under way.
- **Farther away:** a widget farther away closes the popout and reopens it as before.
- Submenus switch the same way; see [Submenus › Switching](submenus.md#switching-in-place).

### Parked cursor
- `PopoutWrapperBase` has a parked-cursor check, because a popup mapping over its anchor steals hover from a still pointer.
- The check arms only when the anchor loses hover. No other hover loss arms it: not the content's, not a submenu closing, not `keepAlive`.
- So nothing holds a popout open under a pointer that is merely still.

### Screen-edge popouts
- **Users:** `EdgePopout.qml` is used by `OSD.qml`, floating edge menus and the attached launcher.
- **Instances:** one independent instance per screen (`Variants` over `General.screensFor(mode)`).
- **Window:** each is an Overlay-layer `PanelWindow` with Normal exclusion and a `-borderWidth` margin.
  - So it lands on the inner stroke of whatever reserves that edge: the border (`surfaces/border/`) or a bar.
- Held boxes, the slide and the fullscreen hold are in [Held off an edge](held-off-edge.md).
