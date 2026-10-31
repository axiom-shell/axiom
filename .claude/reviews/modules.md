# modules
reviewed: 6678e4a 2026-10-31  (full)

The roots, shared parts, lock screen and greeter rules and acquire/release pairing hold. Sizing is the weak spot: `SlotContext` compares `fullMin*` with the whole slot (padding included) while modules write content px, and eight modules' minimums are under their full layouts' needs anyway, so full layouts squeeze or clip just above their minimum (several at their own default size). Many modules also build parts their current mode hides.

## Open findings
- Major: [fullMinWidth and fullMinHeight are compared with the slot's size, padding included](../../docs/dev/issues.md#fullminwidth-and-fullminheight-are-compared-with-the-slots-size-padding-included)
- Major: [Eight modules' full layouts need more room than their fullMin sizes, even inside the padding](../../docs/dev/issues.md#eight-modules-full-layouts-need-more-room-than-their-fullmin-sizes-even-inside-the-padding)
- Major: [SystemGraphs has no px minimum, so its full panels are cut on strips and tall columns](../../docs/dev/issues.md#systemgraphs-has-no-px-minimum-so-its-full-panels-are-cut-on-strips-and-tall-columns)
- Major: [The Clock's date and label keep their room while the time shrinks to nothing](../../docs/dev/issues.md#the-clocks-date-and-label-keep-their-room-while-the-time-shrinks-to-nothing)
- Major: [The Cheatsheet's keyboard view is cut off below about 530 px, with no scroll and no small layout](../../docs/dev/issues.md#the-cheatsheets-keyboard-view-is-cut-off-below-about-530-px-with-no-scroll-and-no-small-layout)
- Major: [A DeviceList squeezed to nothing wants no growth](../../docs/dev/issues.md#a-devicelist-squeezed-to-nothing-wants-no-growth)
- Major: [Parts shown in one mode are built hidden in every mode, in ten modules and parts](../../docs/dev/issues.md#parts-shown-in-one-mode-are-built-hidden-in-every-mode-in-ten-modules-and-parts)
- Major (filed from a Minor, maintainer 2026-10-31): [What a lock screen module may do is a list kept by hand in two docs that disagree](../../docs/dev/issues.md#what-a-lock-screen-module-may-do-is-a-list-kept-by-hand-in-two-docs-that-disagree)
- Cleanup: [Card and Panel each spell out the grow and expand members](../../docs/dev/issues.md#card-and-panel-each-spell-out-the-grow-and-expand-members)
- Cleanup: [Tailscale's PeerRow redraws DeviceRow without its buttons](../../docs/dev/issues.md#tailscales-peerrow-redraws-devicerow-without-its-buttons)
- Cleanup: [WifiNetworks' WPA password form repeats WifiJoinForm's](../../docs/dev/issues.md#wifinetworks-wpa-password-form-repeats-wifijoinforms)
- Cleanup: [Three row options nothing sets](../../docs/dev/issues.md#three-row-options-nothing-sets)
- Cleanup: [Login and Password each carry the same required-field report](../../docs/dev/issues.md#login-and-password-each-carry-the-same-required-field-report)
- Cleanup: [Three keycap parts draw the same cap, and KeyCap's icon slot has no user](../../docs/dev/issues.md#three-keycap-parts-draw-the-same-cap-and-keycaps-icon-slot-has-no-user)
- Cleanup: [WeatherForecast repeats the Weather card's current conditions](../../docs/dev/issues.md#weatherforecast-repeats-the-weather-cards-current-conditions)
- Noted on existing entries: [Modules inside borders aren't sized evenly](../../docs/dev/issues.md#modules-inside-borders-arent-sized-evenly), [Compact cards still build their full layout](../../docs/dev/issues.md#compact-cards-still-build-their-full-layout), [NowPlaying builds its strip layout and a second transport hidden in every mode](../../docs/dev/issues.md#nowplaying-builds-its-strip-layout-and-a-second-transport-hidden-in-every-mode).

Unrecorded (Minor):
- **Template-string labels:** `VolumeDials.qml:58` (unmuted label) and `Updates.qml:85` (section title) build text by concatenation instead of `I18n.tr("{0} …", …)`.
- **Calculator reopened after `=` says "No result" for its own answer:** the answer flag lives in the module, not `CalculatorManager`, so it's lost on close (utility-modules.md: lasting state in the service).
- **A short ClipboardHistory card on a compositor without clipboard control says "Nothing copied yet"** instead of that it's unsupported.
- **Submenu picks tile or row from grid-unit `shape`** (`Submenu.qml:95`), though it only lives in edge menus, whose units aren't square: it should read `innerWidth`/`innerHeight`.
- **EmojiPicker's group-tab threshold is bare px** (`10 × 26 + 30`), not `Widget.iconButton`, so tabs squeeze on roomy density.
- **Keycap text sizes are `Appearance.fontSize - n`**, not `fontSizeBy(-n)` (four places).
- **NowPlaying's `drawsBox: true` is unconditional**, so a bare edge-menu NowPlaying keeps 18 px of padding with no cover box drawn.
- **Battery's charge circle is about 7 px tall at `fullMinHeight`** (6f).
- **Greeting and Session draw an opaque `Theme.background` box**, not `Appearance.fill(...)`, so they ignore surface translucency.
- **AudioMixer's slider-only row** needs about 163 px at its 168 px `fullMinWidth` (132 inside): percent and mute squeeze in 168–199 px wide one-row cards.
- **Stale lines:** `docs/dev/features/grow-expand.md` leaves Tailscale and VpnConnections out of the modules with `grow`; AudioMixer's header comment says the Devices tab adjusts each device (it only picks the default).

## Contract
Holds: roots are Card, Panel or TitledCard (SystemTray is a popout-only Item); `SlotContext` gives every root the same `cols`/`rows`/`shape`/`compact`/`bare`/`pad`/`inner*` with no binding loop between `compact` and `pad`; CompactFigure, EmptyState and TileGrid shrink as documented; DeviceList is a ListView of DeviceRows; every polled module acquires in `onCompleted` and releases in `onDestruction` (Clock and WorldClocks re-acquire on change, Notes per path); utility modules keep lasting state in their services except Calculator's answer flag (Minor); greeter modules (Login, Session, KeyboardLayout) are inert unless `host.kind === "greeter" && !host.preview && Paths.greeter`; Password only acts on the target lock surface, not in previews; ClockCalendar shows events on the lock screen only with its setting on, read-only, never on the greeter; text fields set `x-keyboard`; the lock screen hosts list matches lockscreen.md. Modules with no `fullMin*` by design: Notes (its own `tiny`), and the small fixed-figure modules (Caffeine, ColorSwatch, Greeting, Power, Session, Screenshot, KeyboardLayout, VolumeDials, WorkspacesMap, QuickActions, Favourites); Clock and SystemGraphs lack one wrongly (findings).

## Coverage
Read deeply (five reviewer agents, one per chunk): the roots and figure parts and the small modules (A); network, VPN, Bluetooth and audio modules and device parts (B); utility modules and timer parts (C); notifications, quick actions, clocks, calendar, agenda, weather, pickers, submenus, Login and Password (D); NowPlaying, Updates, the keyboard parts (E). Outlined: Chat, ThemePicker, WorkspacesMap, WallpaperPicker, CodeLine; WeatherForecast, WorkspaceGrid, WorkspaceStrips and SystemTray (popout-only, reviewed in batch 5's popouts audit). Seams outlined, not reread: `BarPopouts.qml` (popouts audit), `GridPlacement.qml` (overlay audit); tray parts (popouts audit); CustomWidget (custom-widgets audit). Nothing was run in the shell: the sizing figures are arithmetic at font 14, normal density.

## History
- 2026-10-31 full (--deep): 14 findings recorded (7 Major, 7 Cleanup), 12 Minor left open
