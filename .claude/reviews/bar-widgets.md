# bar-widgets
reviewed: c4fc397 2026-10-30  (full)

The widget types follow the collection's rules: polling is paired, popouts are gated, and colours come from the bar. Sizing at the edges of the settings is weak. Ticking labels without `steadyDigits` shift under a proportional font. Fixed-px sizes ignore the bar. Things clip or spill on thin and vertical bars: a custom clock format, tray icons, used memory, stacked text. Media's fill style at its minimum shows the meter instead of its icon. Workspaces' measured length glides. About 45 lines can go, most of them BaseWidget's dead background box.

## Open findings
- Major: [Ticking labels without steadyDigits resize the bar under a proportional font](../../docs/dev/issues.md#ticking-labels-without-steadydigits-resize-the-bar-under-a-proportional-font)
- Major: [Media squeezed to its minimum in the fill style shows the meter, not its icon](../../docs/dev/issues.md#media-squeezed-to-its-minimum-in-the-fill-style-shows-the-meter-not-its-icon)
- Major: [The Workspaces widget's measured length glides when the active cell widens](../../docs/dev/issues.md#the-workspaces-widgets-measured-length-glides-when-the-active-cell-widens)
- Major: [A custom clock format without spaces spills past a vertical bar](../../docs/dev/issues.md#a-custom-clock-format-without-spaces-spills-past-a-vertical-bar)
- Major: [Tray icons keep their pixel size on a bar thinner than them](../../docs/dev/issues.md#tray-icons-keep-their-pixel-size-on-a-bar-thinner-than-them)
- Major: [Some bar widget sizes are fixed pixels, not the bar's](../../docs/dev/issues.md#some-bar-widget-sizes-are-fixed-pixels-not-the-bars)
- Major: [SystemStats' used memory clips on a vertical bar](../../docs/dev/issues.md#systemstats-used-memory-clips-on-a-vertical-bar)
- Major: [The stacked style clips on a thin bar](../../docs/dev/issues.md#the-stacked-style-clips-on-a-thin-bar)
- Cleanup: [BaseWidget's background box and panel-size defaults are dead](../../docs/dev/issues.md#basewidgets-background-box-and-panel-size-defaults-are-dead)
- Cleanup: [SystemStats works out ValueStyleWidget's style fallbacks again](../../docs/dev/issues.md#systemstats-works-out-valuestylewidgets-style-fallbacks-again)
- Cleanup: [The workspace switchers find a workspace by id with hand-written loops](../../docs/dev/issues.md#the-workspace-switchers-find-a-workspace-by-id-with-hand-written-loops)

### The docs disagree on which widgets have a popout part
- **Where:** `docs/recipes/bar-widget.md:69`, `components/bar/widgets/AGENTS.md:13`, `docs/dev/bar/composition.md` (Menu popouts)
- **What:** The recipe says Button and the tray have no `popout` part, but Button's is `menu` and the tray's is `plain`. AGENTS.md and composition.md say every widget but Separator has `enabled` and `menu`, but the tray's `plain` has only `enabled`. Fix: one consistent sentence in all three.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the bar-widgets system

### display-styles.md leaves Vpn out of its table
- **Where:** `docs/dev/bar/display-styles.md:55`
- **What:** Vpn offers `[label, icon, stacked]`, but the "Weather, Updates, Tailscale" row leaves it out, and the doc never names it. Fix: add Vpn to the row.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the bar-widgets system

## Contract
- Polling: acquire/release are paired in every polled widget, with requests built from `properties` only. Network and SystemStats ask for history only with the sparkline.
- Popouts: own popouts are gated on `EdgeMenusConfig.opensOwnPopout`; the tray's `popout.enabled` is equivalent (`plain`).
- Schema: every type has a `schema.yaml` with `label`/`icon`/`group`.
- Colours: through `Theme.resolveColor` and `colors`.
- Hidden: `hidden` takes no room and disables clicks.
- Hover: cells and tray items read it through `hitArea.hovers`.
- Models and timers: Repeater models are counts or config; no widget has a repeating Timer.
- Styles: each listed style is drawn.
- Strings: all through `I18n.tr`.
- Tests: BarWidgetStyle and BarAutoColors have a test row for every case.
- Dead members: none with a single hit.
- Broken: `steadyDigits` (C2) and the bar sizing rule (C1, px), as the findings above.

## Coverage
- Read deeply: every widget in `components/bar/widgets/*/` with its schema.yaml, `components/bar/widgets/base/*`, BarWidgetStyle, BarAutoColors, BarStyle, BarDisplay.yaml, WidgetBase.yaml.
- Outlined: BarWidgetHost, BarsConfig (`enrichBarConfig`), WorkspaceGrid and WorkspaceStrips content.
- Skipped, because the bar and popouts audits cover them: BarContainer, WidgetGroup, BarPanel, BarLayout, BarPopouts, PopoutAnchor, BarManager, ScreenEdgeManager, shell/Bar.

## History
- 2026-10-30 full: 14 findings (8 Major, 4 Cleanup, 2 Minor); recorded (one cleanup, the workspace grid's unread fontSize, as part of the popouts audit's Small improvements to WorkspaceGrid)
