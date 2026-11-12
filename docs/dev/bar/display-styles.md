# Display styles

> **Files:** `qml/components/bar/widgets/base/BarWidget.qml`, `qml/components/bar/widgets/base/WidgetSegments.qml`, `qml/components/bar/widgets/base/ValueGraphic.qml`, `qml/components/methods/ValueGraphics.qml`, `qml/config/schema/definitions/widgets/BarDisplay.yaml`, `qml/config/schema/definitions/kinds/WidgetBase.yaml`, `qml/components/bar/widgets/SystemStats/SystemStats.qml`, `qml/components/bar/widgets/CustomWidget/CustomWidget.qml`
> **Config:** a bar widget's `properties.appearance` (`style`, `segments`, `width`); a custom widget's `bar`
> **Related:** [Widget base classes](widget-style.md), [Custom widgets](../features/custom-widgets.md) › The bar widget, [Config manager](../core/config-manager.md#the-shape-of-configjson-format-2)

How a bar widget with a value, a time or a long text draws it: one set of styles shared by the built-in widgets and custom widgets, drawn by the same code.

### The styles
- `label`: the icon and its text (every widget's look before styles).
- `icon`: the icon alone.
- `ring` (`PercentageCircle`), `fill` (`LevelMeter`), `segments` (`SegmentMeter`, `segments` of them), `sparkline` (`Sparkline` over the widget's history): a graphic before the icon, in `IconTextWidget`'s `lead` slot; fill, segments and sparkline are `width` long (0: from the bar's font).
- `pill`: the widget's background filled to its value (`backgroundLevel`, drawn by its background's `LevelFill` in the background's own shape).
- `ticker`: the text, up to `width` long, scrolling past that and centred in its room while it fits; `stacked`: the text over a caption. Both sit after the icon, where the label goes (`leadAfterIcon`); a vertical bar turns the ticker along it and draws stacked as a label.
- The ring is drawn on whole pixels, centred exactly on the icon's middle beside it (`IconTextWidget.iconMiddle`, passed as `ValueGraphic.middle`), its side's parity following whether that's on a whole or a half pixel. IconTextWidget centres the label's letters on the same middle (`TextBandPadding`), so ring, icon and label line up; the ticker centres on its letters the same way.
- The pill's colour is `colors.level`, shared with SystemStats. The graphics draw in `colors.icon`.

### The schema
`BarDisplay` holds the four settings (an `x-inline` definition). A custom widget's `bar` extends it (`x-properties`: its icon and popout). A built-in widget picks WidgetBase's `appearance` part and names the styles it can draw (the default stays `label` unless it overrides `default` too):
```yaml
appearance:
  variant: value
  style:
    enum: [label, icon, ring, fill, pill, segments, stacked]
    description: Stacked puts the charge over the time to full or left.
```
A part's override reaching into a setting that `$ref`s a definition inlines that definition first (`backend/internal/schema/yamlsrc/kinds.go`, `inlineRef`), so the enum narrows per widget. Every style a widget lists is one it draws; the default `label` keeps a widget's look from before.

### ValueStyleWidget
The base (a `BarIconWidget`) for a widget drawing one value. It takes:
- `appearance` (default `properties.appearance`; CustomWidget passes its definition's `bar`);
- `ratio`, 0–1, below 0 while there's no value (ring, fill, segments and pill then draw as a label);
- `history` with `graphMin`/`graphMax` (null: none kept, the sparkline draws as a fill);
- `styleText` (the ticker's text and stacked's first line, default `text`) and `subtext` (stacked's caption);
- `labelShown` in place of `showText` (the widget's own "show the value" setting; the style hides the label where it's the graphic).

`style` is the style it draws now, after those fallbacks (`ValueGraphics.resolvedStyle`, which SystemStats' segments read too). The graphic is a `ValueGraphic`, which a widget drawing several values places itself: SystemStats lays each metric out as an `IconTextWidget` (as every icon + label widget is; `uprightLabel` keeps its small upright values on a vertical bar) with one in its lead slot, pill only with one metric in its box, ticker and stacked split like a label on a split bar, and with Boxes: One each metric gets its own icon part there (Boxes: One per item gives each metric its own box and pill: [widget style](widget-style.md#boxes-one-per-item)), and a disk's sparkline as a fill (SystemManager keeps no disk history).

How far its graphic reaches across the bar is `ValueGraphic.across` (`ValueGraphics.across`, from the sizes ValueGraphic draws at, which it reads from the helper too; from the style, the bar's thickness and font, never measured): the ring 0.62 of the thickness, the sparkline 0.6 of it on a horizontal bar (inset 0.2 either side) and the whole of it on a vertical one (its inset is along the bar there), stacked its two lines (1.2 × (0.8 + 0.6) of the font, at the fit that shrinks them to the room inside the widget's box: `ValueGraphics.stackedFit` in `boxRoom`, the thickness less the look's outline stroke band either side, `BarShapes.strokeBand` (a tab's too: it's open along the edge it hangs from, but the lines are centred across the thickness, so clearing its inner stroke takes the same margin on both sides), or the whole thickness where no box is drawn); fill, segments and the ticker no more than a line. `ValueStyleWidget` declares the larger of that and its icon's line as its `contentAcross`, SystemStats the largest over its shown metrics' styles, so a run's capsule or arrow end keeps clear of the graphic ([Shapes and runs](widget-shapes-runs.md#backgrounds-and-shapes)).

### Which widget draws what
| Widget | Value | Stacked caption |
|---|---|---|
| SystemStats | each metric's percent (temperature on 0–100 °C); sparkline from SystemManager's history, asked for only with that style | the metric's short name |
| Battery | the charge | time to full or left |
| Volume, Microphone (`AudioLevelWidget`) | the device's level, full at 100% | none (no stacked) |
| ClaudeUsage | the fullest account's percent (the first's with Accounts shown: first) | the limit's name |
| Pomodoro | how far through the phase | Focus / Break |
| Stopwatch | the timer's progress, or the stopwatch round the minute | Timer / the lap |
| IdleInhibitor | a timed caffeine's time left | none |
| Media | the track's position (fill, pill); ticker scrolls the label | the artist under the title |
| Window | ticker scrolls the title | the app id |
| NextEvent | how far through an event under way | the title under when |
| Network | the Wi-Fi signal; sparkline the download speed (SystemManager's `net` history, acquired only then) | the address under the name |
| Bluetooth | a lone device's battery | its battery under its name |
| Markets | none; sparkline the shown symbol's day (its own `graphMin`/`graphMax`), ticker scrolls every symbol | the price and change under the name |
| Weather, Updates, Tailscale | none (label, icon, stacked) | the condition / the AUR's share / this machine's address |

Widgets with no value, time or long text (Workspaces, tray, Separator, Notifications, Todo, KeyboardLayout, Privacy, ScreenRecord, DevMode, Time, Button) have no `appearance`.

While its check fails, Updates draws in the icon style whatever its own: an error icon after the download icon, in the error colour, in place of the count.
