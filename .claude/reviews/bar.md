# bar
reviewed: c4fc397 2026-10-30  (full)

The bar's core holds its contract: only `BarEnds` decides corners and ends, geometry animates only what's drawn, and the helper suites pass. What's open:
- A second bar on one edge is invisible to the screen-edge answers. This is a maintainer question: are stacked bars supported?
- An "every monitor" bar is remade on hotplug.
- The editor's selection jumps when another bar is removed.
- A dead `layoutUpdated` chain runs on every layout change.

## Open findings
- Major: [Nothing listens to the bar's layoutUpdated any more](../../docs/dev/issues.md#nothing-listens-to-the-bars-layoutupdated-any-more)
- Major: [A bar made while the bar editor is open may never report to it](../../docs/dev/issues.md#a-bar-made-while-the-bar-editor-is-open-may-never-report-to-it)
- Major: [A second bar on an edge is invisible to the screen-edge answers, and New bar makes one](../../docs/dev/issues.md#a-second-bar-on-an-edge-is-invisible-to-the-screen-edge-answers-and-new-bar-makes-one)
- Major: [Plugging in or unplugging a monitor remakes the bar that stays](../../docs/dev/issues.md#plugging-in-or-unplugging-a-monitor-remakes-the-bar-that-stays)
- Major: [Removing or copying another bar moves the editor's selection to a different bar](../../docs/dev/issues.md#removing-or-copying-another-bar-moves-the-editors-selection-to-a-different-bar)
- Major: [A corner piece's pull-out re-derives a bar's reserve and misses its clamp](../../docs/dev/issues.md#a-corner-pieces-pull-out-re-derives-a-bars-reserve-and-misses-its-clamp)
- Cleanup: [The pill merge in BarContainer repeats BarLayout's, untested](../../docs/dev/issues.md#the-pill-merge-in-barcontainer-repeats-barlayouts-untested)
- Cleanup: [StandaloneBar only wraps BarPanel's BarContainer](../../docs/dev/issues.md#standalonebar-only-wraps-barpanels-barcontainer)
- Cleanup: [BarContainer._withEntry rebuilds Utils.withEntry](../../docs/dev/issues.md#barcontainer_withentry-rebuilds-utilswithentry)
- Cleanup: [enrichBarConfig hands out two fields nothing reads and keeps three dead fallbacks](../../docs/dev/issues.md#enrichbarconfig-hands-out-two-fields-nothing-reads-and-keeps-three-dead-fallbacks)
- Cleanup: [A bar's reserve trim is worked out again by callers holding the enriched bar](../../docs/dev/issues.md#a-bars-reserve-trim-is-worked-out-again-by-callers-holding-the-enriched-bar)
- Cleanup: [Missing test rows for two helper decisions](../../docs/dev/issues.md#missing-test-rows-for-two-helper-decisions)
- Outside: [An overlay misses a transparent bar's inner accent line](../../docs/dev/issues.md#an-overlay-misses-a-transparent-bars-inner-accent-line)
- Outside: [WindowLookConfig rebuilds BarStyle.look](../../docs/dev/issues.md#windowlookconfig-rebuilds-barstylelook)

Unrecorded (Minor):
- **A plain bar's accent line runs onto a solid bar's stroke at its end:** `components/bar/BarContainer.qml:881` (`AccentLine`); key the clearance on `ends.start.reach > 0 || ends.start.held`, and the same for the end.
- **Lane chips name a widget by its spaced type name, missing seven types' keys and custom widgets' names:** `components/views/BarEditor/BarDragLayer.qml:80` (`shortLabel`); label `CustomWidget:` keys through `label()`, and read short labels from the schema or complete the list.
- **The section lane's scroll bar room is a bare 8 px:** `components/views/BarEditor/SectionLane.qml:33`; `Widget.px(8)` and `Appearance.easing`.
- **The bar docs and comments describe code that has changed:** composition.md, widget-style.md, bar-ends-pills.md, layering-and-corners.md, `shell/Bar.qml:24`, `BarsPanel.qml:100`: seven stale statements.

## Contract
- **C1:** hosts read `ends`. Only BarEnds and `barStartOn` (through `BarEnds.yieldsTo`) decide; the popouts' `vertical` reads are orientation. The accent line is the one exception (Minor).
- **C2:** glides only on drawn host geometry and Section drawnPos/drawnLength. Measures, allocation, slots and hidden are plain bindings.
- **C3:** bar and border windows are Top-layer LayerSlots that never react to fullscreen, keyed on `BarsConfig.layerNamespace`, all gated on `surfacesReady`.
- **C4:** every edge, kind, border off and animations off has its branch.
- **Ends:** end kinds and reach, the pill-bar corner merge, `endReaches` and the `yieldsTo` order matching LayerStack hold.
- **Look:** `lookOf` inherits null keys; `lookContext` counts grouping only when boxed; auto colours use contrast 1.3 for a filled, unmerged bar and 3 otherwise; `shadowColor` is capped and premultiplied; `borderShadowed` holds.
- **Editor:** pieces are StreamedLoaders, every edit goes through a ConfigDraft and `setPreview`, live reports clear on unwatch and destruction; zero bars, the last bar, a multi-screen bar and a chip dropped after itself are handled.
- **Border:** RoundedBorders' strips, corners and shadow window match layering-and-corners.md, apart from the `cornerMargin` clamp.

## Coverage
Read deeply: `components/bar/{BarContainer,BarPanel,WidgetGroup,BarWidgetHost,WidgetBackground,CornerMerge,StandaloneBar}.qml`, `shell/Bar.qml`, `shell/ScreenBorder.qml`, `components/methods/{BarLayout,BarEnds,BarShapes,BarWidgetStyle,BarAutoColors}.qml`, `config/BarsConfig.qml`, `config/BarStyle.qml`, `services/ui/{BarManager,ScreenEdgeManager,EditsManager}.qml`, `components/surfaces/border/*`, `components/reusable/{CornerPiece,SeparatorMark}.qml`, `components/views/BarEditor/*`, the bar schema YAML.
Outlined: `components/hosts/popout/*` (popouts audit), `services/compositor/HyprlandManager.qml` (`surfacesReady`), `components/bar/widgets/*` (bar-widgets audit).
Skipped: the widget files themselves.

## History
- 2026-10-30 full: 18 findings (6 Major, 6 Cleanups, 4 Minor, 2 outside the system); recorded
