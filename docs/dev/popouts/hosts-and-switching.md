# Popout hosts, window sizing and switching in place

> **Files:** `components/hosts/popout/PopoutWrapperBase.qml`, `components/hosts/popout/BarPopouts.qml`, `components/hosts/popout/EdgePopout.qml`, `components/hosts/popout/FloatingPopout.qml`, `components/hosts/popout/AttachedSurface.qml`, `components/hosts/popout/SlideAnimation.qml`, `components/hosts/popout/SwitchStill.qml`, `shell/OSD.qml`
> **Config:** none directly
> **Related:** [Surface context](surface-context.md), [Edge attach](edge-attach.md), [Submenus](submenus.md), [Registry](registry.md), [Content roots](../overlay/content-roots.md), [Pill and floating bars](pill-and-floating-bars.md)

This doc covers the shared host pieces in `components/hosts/popout/`, how a bar popout's window is sized, how it switches to another payload without closing, and how screen-edge popouts sit.

### Shared pieces (`components/hosts/popout/`)
- **`PopoutWrapperBase`:**
  - Open/close/queue state: `isOpen`, `show(data)`, `hide()`, and a timer that dismisses on hover loss.
  - A wrapper may switch an open popout to another payload in place instead of closing it first, via its `canSwitchTo(anchor, data)` and `prepareSwitch(done)` hooks.
- **`FloatingPopout`:** a box floating in the free area, placed at a fraction across and down inside per-side margins.
  - `xAlign`/`yAlign` say which part of the box sits at that point.
  - It fades in, once granted its `PopoutClaim` (`claimKey`; its footprint is its box where it's placed).
  - Used by the detached launcher and the window switcher.
- **`SlideAnimation`.**
- **`AttachedSurface`:** the content box, connector and `CornerPiece` fillets that make a popout look like it grows out of a bar or the screen border. `edge` is a `ScreenEdge`.
  - **Attached:**
    - The box starts on the attach edge, with the fillets curving outside its walls (`boxStart`).
    - `boxStart` is pushed back only as far as a box too shallow for its fillet and far corner needs.
  - **Detached:** the box sits half a connector gap past its lead.
    - Past a transparent bar, the lead moves the box in line with the windows (`BarsConfig.detachedPush`). This is negative where the windows start nearer.
    - A bar's pills keep that half gap too, since their depth is sized by it.
- **`BarPopouts.qml`:** bar popouts share one wrapper, and one box, per bar.

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
  - **Which do:** the radio menus (`parts/DeviceList`, 2 rows up to `visibleRows`, 5, Wi-Fi's 6: WifiNetworks, BluetoothDevices, Tailscale), AudioMixer (2 to 4 rows), Notifications (empty, one notification's height, so it only grows), Todo, Stopwatch's laps, Calendar's day.
- **Room to grow:** the window's `popoutRoom` is how much more the box can grow before it meets what's on the screen's far side (along a vertical bar, its ends), from `ScreenEdgeManager.frameLineOn`. Content growing on its own reads it through `QsWindow.window`: a `StyledComboEntry` opens its list inline, no taller than that. An `EdgePopout`'s is `null`: its content doesn't grow the box, so the list keeps to what scrolls around it. Nothing yet keeps content that is already taller than the screen on it.
- **Keyboard:** a popout with a text field sets `wantsKeyboardFocus`.
  - BarPopouts then takes a focus grab and the bar takes keyboard focus on demand.
  - A click outside emits `focusLost`.
- **Mapping only when ready:** content is mapped only once two things are true.
  - **Its payload is in** (`BarPopouts._payloadApplied`). A Loader reports Ready before `onLoaded`.
  - **Its positioners are laid out** (`_layOut`). Row/Column/Grid lay out on polish, which an unmapped window never runs.

  So it never maps small and grows a frame later. On a bottom or right bar the popup would also have to move, and the compositor didn't always follow that.

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
