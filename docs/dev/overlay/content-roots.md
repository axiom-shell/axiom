# Content: roots and hosts

> **Files:** `components/content/base/Card.qml`, `components/content/base/Panel.qml`, `components/content/base/TitledCard.qml`, `components/content/base/SlotContext.qml`, `components/hosts/overlay/OverlaySlot.qml`, `components/hosts/popout/BarPopouts.qml`
> **Config:** `Overlay.items[].layout.modules`, `EdgeMenus.items[].layout.modules` (module `type`), bar widget `popoutName`
> **Related:** [Writing modules](writing-modules.md), [Pages and grid](pages-and-grid.md), [Popout hosts](../popouts/hosts-and-switching.md), [Submenus](../popouts/submenus.md)

`components/content/<Name>/<Name>.qml` holds every loadable panel: overlay modules and bar popouts. This doc covers the two root types (`Card`, `Panel`), what each host passes in, and when one file serves both roles.

### Loaded by name
- The name is the overlay module `type` (`OverlayModule.oneOf`) and/or a bar `popoutName`.
- One file can be both: AudioMixer, BluetoothDevices, Notifications, NowPlaying, SystemGraphs, Updates, WifiNetworks.
- Hosts load it by URL and pass their context.

### Roots
- **`Card`** (`content/base/`): a free-form card (box, `properties`, slot context). Card-only content uses it.
  - A `Card`'s `compactContent` replaces its children when `compact` (they go into an inner item that hides).
  - Override only what differs, like `color`.
- **`Panel`**: lays its children out in a column and works in either host.
  - In a bar popout it sizes to its content with the popout box (`wrapper` set, `hovered` read for dismissal).
  - In a card the host passes `embedded: true`: it fills the slot with the card box, and `compactContent` (e.g. a `CompactFigure`) replaces the column when `compact` (see [Writing modules](writing-modules.md)).
- **`TitledCard`**: for titled scrolling panels (ThemePicker, the bar editor panels, the settings page's content).
  - A `CardHeader` with `title`, `dirty`, `save()` / `reset()`, `headerExtras`.
  - Children go into the scrolling body.
  - `scrollTo(item, center)` (animated) brings a descendant to the top, or to the middle with `center`.
- All of them expose `properties`, `slotRect`, `cols`/`rows`, `shape`, `compact`, `pad` and `innerWidth`/`innerHeight` (the room inside `pad`). They take what they derive from their place from `base/SlotContext`.
- A popout with a text field sets `wantsKeyboardFocus`: BarPopouts then takes a focus grab and the bar takes keyboard focus on demand; a click outside emits `focusLost`.
- Content that grows in a popout reads which way it grows as `growth` (`growsUp`; always `down` in a card) and sets `flips` to show its column in reverse while it grows up, so its controls stay by the bar (`reusable/LayoutOrder`).
- How a bar popout's window is sized around its content (`spareAcross`, `maxImplicitHeight`/`maxImplicitWidth`, the shown-box animation, growing while open): see [Popout hosts and switching](../popouts/hosts-and-switching.md).

### Content can be both
- A `Panel`-rooted file is a bar popout and a card at once.
- Branch on `embedded` for card-only parts: a header, a mode switch, acquiring with the card's `properties`.

### Hosts
- **`hosts/overlay/OverlaySlot`** (card): passes `properties`, `slotRect`, `embedded: true`. Also used by edge menus, the lock screen, the greeter and the desktop.
- **`hosts/popout/BarPopouts`** (popout): passes `wrapper`, then, once loaded, copies the anchor's payload keys onto matching properties. Popouts declare what they take rather than reading `wrapper.currentData`.
- The tray's menu (`content/SystemTray`) is the one popout-only content rooted in a plain Item. It opens its submenus (`content/parts/TraySubmenu`) in `wrapper.submenu`.
- `content/parts/MenuSubmenu` (an edge menu's modules, opened by a `Submenu` module) is the other submenu content: see [Edge menu submenus](../edge-menus/editing-submenus.md).
- Modules learn where they're shown from `host` (see [Edge menus overview](../edge-menus/overview.md)).

### Paired files
Pairs that look different by design stay separate files:
- `Weather` (card) / `WeatherForecast` (popout).
- `ClockCalendar` / `Calendar` (the month and its events: the Time widget's popout and a module). Both, and the CalendarPage view, are built from `parts/calendar/` (see [Calendar](../features/calendar.md)).
