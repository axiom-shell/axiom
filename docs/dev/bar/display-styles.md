# Display styles

> **Files:** `components/bar/widgets/base/ValueStyleWidget.qml`, `components/bar/widgets/base/ValueGraphic.qml`, `config/schema/definitions/widgets/BarDisplay.yaml`, `config/schema/definitions/kinds/WidgetBase.yaml`, `components/bar/widgets/SystemStats/SystemStats.qml`, `components/bar/widgets/CustomWidget/CustomWidget.qml`
> **Config:** a bar widget's `properties.appearance` (`style`, `segments`, `width`, `colorText`); a custom widget's `bar`
> **Related:** [Widget base classes](widget-style.md), [Custom widgets](../features/custom-widgets.md) › The bar widget, [Config v2](../core/config-v2.md)

How a bar widget with a value, a time or a long text draws it: one set of styles shared by the built-in widgets and custom widgets, drawn by the same code.

### The styles
- `label`: the icon and its text (every widget's look before styles).
- `icon`: the icon alone.
- `ring` (`PercentageCircle`), `fill` (`LevelMeter`), `segments` (`SegmentMeter`, `segments` of them), `sparkline` (`Sparkline` over the widget's history): a graphic before the icon, in `IconTextWidget`'s `lead` slot; fill, segments and sparkline are `width` long (0: from the bar's font).
- `pill`: the widget's background filled to its value (`backgroundLevel`, drawn by its WidgetGroup in the background's own shape).
- `ticker`: the text, up to `width` long, scrolling past that; `stacked`: the text over a caption. Both sit after the icon, where the label goes (`leadAfterIcon`); a vertical bar turns the ticker along it and draws stacked as a label.
- The ring and meters centre on the bar font's glyphs rather than its line box (`ValueGraphic.inkOffset`, from the descent), so they line up with the icon and label beside them.
- `colorText` colours the text in the widget's state colour (its `accentColor`) where that isn't already the background's fill. The graphics draw in `colors.icon`, which reads on a filled background.

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
- `labelShown` in place of `showText` (the widget's own "show the value" setting; the style hides the label where it's the graphic);
- `stateColor` / `hasState`, for `colorText` (default the accent colour; a custom widget's only when its script gives a state).

`style` is the style it draws now, after those fallbacks. The graphic is a `ValueGraphic`, which a widget drawing several values places itself: SystemStats draws one per metric (before the icon, or stacked in place of the value), pill only with one metric shown, and a disk's sparkline as a fill (SystemManager keeps no disk history).

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
| Weather, Updates, Tailscale | none (label, icon, stacked) | the condition / the AUR's share / this machine's address |

Widgets with no value, time or long text (Workspaces, tray, Separator, Notifications, Todo, KeyboardLayout, Privacy, ScreenRecord, Time, Button) have no `appearance`.
