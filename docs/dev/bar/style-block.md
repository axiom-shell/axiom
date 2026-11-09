# Bar style block

> **Files:** `qml/components/views/Settings/BarStyleBlock.qml`, `qml/components/views/Settings/BarLookSample.qml`, `qml/components/reusable/ChoiceTiles.qml`, `qml/config/schema/definitions/widgets/BarStyle.yaml`, `qml/components/views/BarEditor/BarsPanel.qml`, `backend/internal/schema/yamlsrc/check.go`
> **Config:** `Bars.style` (a `BarStyle`), and each bar's own `style` (`Bars.items[].style`)
> **Related:** [Settings page](../core/settings-page.md), [Schema annotations](../core/schema-annotations.md), [Bar editor](bar-editor.md), [Shared UI pieces](../core/shared-ui-pieces.md)

Every BarStyle setting in one block: the settings page's wide Bar style card, and the bar editor's Style tab for the selected bar's style.

### Where it's used
- **Settings page:** `Bars.style` has `x-row: BarStyleBlock` and `x-wide`, so the whole object is one row on a card spanning both columns ([schema annotations](../core/schema-annotations.md) › `x-row`). Edits go through the page's form (`SettingsManager`), as the page's own rows' do.
- **Bar editor:** `BarsPanel` puts the block on the Style tab (the tab's `styles` in `BarsConfig.editorTabs` are the sections it shows), over the selected bar's look, each section shared or the bar's own ([bar editor](bar-editor.md)). A shared section collapses to its heading and a link to the settings page's card. An owned section where some keys are still null (a bar saved when the sections were grouped otherwise, `BarManager.ownsAllStyle` false) says "Some of these follow the shared style." beside a "Make all this bar's own" button: `setStyleOwned(keys, true)`, one undo step, keys already set keeping their values.

### What it holds
- **Sections** by BarStyle's `x-group`s: Look across the whole width, then Colors beside Accents and Size beside Shadow, stacked below `Widget.px(720)`. Each is a `SchemaPropertiesForm` with `keepsPlace`. Below that width the forms don't pair `x-beside` fields, so the tiles keep their room.
- **Look:** the rows marked `x-keepsPlace` (style, shape, grouping) stay where they are, greyed with why while they don't apply. Under them are the rows placed there (`x-placeUnder`: tab sides and ends under the shape, `SchemaLayout.placedUnder`), then the chosen style's own options in one panel ("Tinted options"). Which rows show is the schema's `x-showIf` alone; the block holds no style rules.
- **Tiles:** an enum with `x-control: tiles` draws as `ChoiceTiles`. An option whose `x-enumShowIf` fails is greyed, with its `x-tileHint` as the reason.
- **The live strip:** the bar's own widgets, live, in the look being edited (`BarManager.previewConfigOf`, `BarWidgetHost` with `preview: true`), streamed in. On the settings page that's the first bar; in the editor it's the selected one.
- **Presets:** the header's Presets menu (`StyledContextMenu`) lists BarStyle's `x-presets`. Picking one sets its keys at once and keeps every other key. On the settings page that's one `SettingsManager.setValues`, which the card's Discard puts back. In the editor it's `BarManager.setStyleOwned(keys, true, values)`: one undo step, the bar owning each section the preset touches. The build checks each preset against BarStyle (`yamlsrc.Check`), so a renamed key or a dropped option fails it.

### Drawing bars: one file
`BarLookSample.qml` is the only file of the block that imports bar drawing code. It draws each tile's sample (three fixed widgets on a strip of bar, with one key set to the tile's value) and the live strip.
- **What it uses today:** `qs.components.bar`'s `WidgetBackground` and `BarWidgetHost`, `SeparatorMark`, and the `BarShapes` and `BarWidgetStyle` helpers. It reads the look through `BarsConfig.lookOf`, `enrichBarConfig`, `groupingOf` and `boxedStyles`.
- **When the drawing pieces move** into the bar components' new look folder, `qs.components.bar.look` (the bar style rewrite), this is the one file to switch: to `LookBox` over `BarLook.resolve`. `BarStyleBlock`, `ChoiceTiles` and the forms don't change.
- **Seams with the rewrite:** this file is the first. The second is the bar editor's tab list (`BarsConfig.editorTabs`): the block owns its `styles` entries, and the tab's label, changed from "Widgets" to "Style". Whichever of the two changes merges second carries both: the `styles` entries and the label.
