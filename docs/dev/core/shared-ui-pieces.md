# Shared UI pieces

> **Files:** `components/reusable/`, `components/forms/`, `components/content/parts/`, `components/methods/Utils.qml`, `components/methods/Search.qml`, `components/views/Settings/FoldingCard.qml`, `components/views/Settings/EntryListCard.qml`, `components/views/Settings/ScreenSpotPicker.qml`
> **Config:** none
> **Related:** [Editors pattern](editors-pattern.md), [Content roots](../overlay/content-roots.md), [Writing modules](../overlay/writing-modules.md), [Popout surface context](../popouts/surface-context.md), [Translucency and blur](../theming/translucency-blur.md)

An index of reusable pieces. Reach for one of these before drawing your own; when a pattern appears a second time, it becomes one of these. (Rule: AGENTS.md › UI conventions, "Reuse before building".) Every file in `reusable/`, `forms/` and `content/parts/` is named here or in the docs it links to (`scripts/check_docs.py` checks): add a line when you add a piece.

### Sizes
Everything outside the bars follows the Interface scale and Density through `Widget` (`config/Widget.qml`); a size written as a number doesn't, and `scripts/check_sizes.py` fails on one of 3 px or more, set alone or added, subtracted or chosen in a size's expression (`Widget.height - 4` is `Widget.height - Widget.px(4)`; factors like `* 2` and grid units like `span(8)` are fine).

| What | Use |
|---|---|
| A gap: 3–6 / 8 / 12–14 px | `Widget.spacing` / `Widget.spacing * 2` / `Widget.padding` |
| Inner margins of a row, field or dropdown (6–8 px) | `Widget.smallPadding` |
| A panel's or card's padding (10–22 px) | `Widget.padding` (× 2 for 18–22) |
| A control's height (fields, switches, tabs) | `Widget.height` (or a fixed share of it) |
| A square icon button | `Widget.iconButton` (`FlatIconButton`'s default) |
| A chip, pill or small button (18–22 px) | `Widget.smallHeight` |
| An icon or text size | `Appearance.fontSize`, `fontSizeLarge`, or `Appearance.fontSizeBy(n)` for n px more or less (never `fontSize ± n`: the offset wouldn't scale) |
| A width, an avatar, a dot, a thin bar | `Widget.px(n)` (the Interface scale only) |
| A hairline (0–2 px, `border.width`) | the number |
| Measured against the screen, a measuring font, a placeholder or stand-in, a layout weight | the number, marked `// fixed px: <reason>` |

A size setting in px outside the bars (`Launcher.width`, `Notifications.width`, tile sizes, `Popouts.padding`, an edge menu's `padding`) is scaled in its reader (`Widget.px(_c.width)`), so it follows the Interface scale too; gaps that line up with the compositor's (an edge menu's or dock's `gap`) and hover strips stay as set.

Bars size their own widgets (`BarsConfig.enrichBarConfig`) and never use these: a shared piece the bar uses takes its size from the bar (`CountBadge.textSize`, `IconTextWidget.spacing`).

### Text and structure (`reusable/`)
- `StyledText` / `StyledIcon`.
- `SectionHeading`: accent title + muted description, folded past three lines.
- `ClampedText`: muted help text cut to `maxLines` (3) with a More / Less link, shown only when it's longer. Field and card descriptions use it.
- `FieldGroup`: a titled card of fields; `headerExtras` beside the heading.
- `StyledContainer`: a themed box (surface opacity or solid, optional border and radius).
- `StyledScrollView`: a ScrollView with the shell's padding and a thin accent scroll bar.
- `KeyHint`: a keycap and what it does (`[↵] open`), for a controls hint.
- `content/parts/KeyCap` (a key, optionally with an icon), `ModifierCap` (a combo's modifiers in one cap, as glyphs or words), `KeyCluster` (a folded direction set, H J K L): keycaps for binds. `KeybindSection` / `KeybindRow` draw the keybinds reference (the Keybinds page and the Cheatsheet); `compact` follows `KeybindManager.page.refDensity`; a modifier group folds (`KeybindManager.page.refFolded`). `KeyboardMap`: a US keyboard (`methods/KeyMap`) whose keys are coloured, labelled and clicked through hooks (the editor's key map); `KeyboardReference`: the reference drawn on it, under picked modifiers.
- `StyledSeparator`: border-coloured divider (accent where a divider is accent by design).
- `SeparatorMark`: a line, dot, slash or chevron divider (the Separator widget's, the bar's `separatorStyle` and a custom widget's Separator element).
- `StatusChip` (filled status pill), `CountBadge` (a count on a button's or icon's corner; bumps when it changes), `UnsavedDot` (`onAccent` on a selected row).
  - All three are `PopInRectangle`s: set `shown` (not `visible`) and they pop in and out; `pulse()` for a bump.
- `IssueList`: `[{ level, text }]`, errors red, warnings amber.
- `IssueIcon`: one problem's icon in those colors (`level`, `tone`), saying what's wrong in a tooltip on hover (`tip`). Every warning or error icon shown without its text beside it is one (a bind row, a bind section, the onboarding's binds table, the keybinds reference).
- `DropdownSurface`: the box of anything that drops down.
- `TileFlow`: equal tiles, as many columns as fit.
- `TypeLibrary`: the editors' libraries of types to add.
  - An A–Z / By category switch over equal tiles of a caller's `delegate`, by label or under a heading per group (`methods/LibraryOrder`).
  - The label and heading come from the caller's `labelOf` / `headingOf` hooks (the editors translate the schema's).
  - The caller keeps `grouped`.
  - A search box beside the switch, at the right, narrows the tiles to the types whose label, type or group heading holds the text (`LibraryOrder.filtered`); the query lasts as long as the library is built (the layouts editor keeps it under a module's options).
- `KeyedLoader`: rebuilds a form when `key` changes, so rows never write old values onto a new selection.
- `StreamedLoader`: a Loader built a moment later from `BuildQueueManager`'s queue, then faded in: a page's panels, cards, sections and long lists, so a page shows at once. `wanted` gates it like `active`; `always` streams after the page's first build too. See [streamed-building](streamed-building.md).
- `LayoutOrder`: shows a layout's items in reverse order while `reversed` (`Panel.flips`: a popout growing up keeps its controls last, by the bar). Only for a layout of plain items, no Repeater directly in it.

### Controls (`reusable/`)
- `StyledTextButton`, `StyledIconButton`, `SquareIconButton`, `FlatIconButton`, `StyledRectButton` (icon, hover and press colors, optional `CountBadge`).
- `StyledToolTip`: a hover tooltip in a popup window of its own, so the small layer windows buttons live in don't clip it. Buttons take `tooltipText`. It stays in `reusable/` though it reads services (blur, capture freeze): the buttons here use it (AGENTS.md › Layout).
- `StyledSlider`: trough, fill and handle; `moved` while dragged, `released` at the end; a value pushed in animates.
- `StyledVolumeBar`: a volume bar with its icon, mute and optional percentage (drag, click or scroll; its trough clips the fill, so a low level keeps to its rounded ends); `surfaces/osd/PipewireVolumeBar` binds one to a Pipewire stream or the system volume (the OSD's).
- `PercentageCircle`: a ring gauge with an icon in the middle; `sweep` below 360 opens it at the bottom (a gauge).
- `LevelMeter`: a level shown, not set: `StyledSlider`'s trough and fill without the handle, across or filling up (`vertical`); the fill is never shorter than its rounded ends. Any meter in a rounded trough is one (the custom widgets', Disks, Claude usage).
- `SegmentMeter`: a level as blocks or dots lit up to `share`, in a row or a column filling up.
  - Both are drawn by the bar's display styles (`bar/widgets/base/ValueGraphic`, [Display styles](../bar/display-styles.md)) and a custom widget's elements; a bar sets their sizes from its font.
- `SegmentButton`: a choice, accent when `active`; `Layout.fillWidth: false` in a row of pills.
- `SegmentRow`: a single choice of SegmentButtons on one track, the accent sliding to the active one. Toggles and multi-select chips stay plain rows or Flows.
- `StyledTabBar` (of `StyledTabButton`s): its current tab's highlight slides between tabs.
- `StyledTextEntry`: see [QML pitfalls](qml-pitfalls.md) (push the value in, act on `textEdited`). Search boxes set `clearable`: an X at the right while there's text, which clears it as a typed edit (`clear()`) and keeps the focus; with `escapeClears`, Escape clears it too (passed on when it's empty). The launcher's own field has the same X. `StyledTextArea`: multi-line, optionally growing with its text (`expandable`, capped at `maxLines`, then it scrolls); `singleLine` makes it a one-line value that wraps (line breaks become spaces, Enter submits, Tab moves on).
- `PasswordEntry`: a password field with a message, a busy bar and `shake()`.
  - It has no authenticator of its own: the lock screen's `PasswordField`, the greeter's `LoginField` and the polkit prompt wire it.
- `StyledComboEntry`: a choice from a list dropping down under a field, optionally typed. In a popout or edge menu (its window declares `popoutRoom`) the list opens inline (`expandsInline`), inside the field's layout, since a dropdown Popup there is a window the popout's hover and blur don't reach. It's capped by the room the box has left to grow, or in an edge menu by the Flickable around it, which scrolls it into view.
  - `options` `[{ value, label, icon? }]`, `value` pushed in, `picked(value)`.
  - Used by the greeter's user and session pickers.
- `StyledSwitch`.
- `TypePickerPopup`: pick a type, `{ type, label, icon }`.
- `ActionTile`: an icon well over a label. With `opens`, a right click or long press is `opened`.
- `ActionPill`: the wide one, a well beside a name and status. With `opens`, the well toggles and the rest opens.

### Editor lists and drags (`reusable/`)
- `ListEntryRow` (+ `RowAction`, `AddEntryButton`).
- `DragArea`: drag vs tap; with `dragLayer` + `payload` it carries.
- `DragLayer`: one drag, a target registry, and a hit test.
  - `accepts` / `priority` hooks; `priority` defaults to a target's `dropPriority`.
  - Signals: `started` / `moved` / `dropped`.
- `TrashTarget`: a "Drop to remove" pill shown while `active`, `targetKind: "trash"`, above overlapping targets. The layer's `accepts` says what it takes and its `dropped` removes it.
- `DragChip`: a carryable icon + name pill.
- `views/Layouts/EntryListTarget`: a list of rows that reorders its own carried rows.
- `InspectorHeader`: icon well, name, place, actions, divider.
- `content/base/SaveResetActions`: an editor's Save/Discard pair, both shown only with unsaved edits or typed text. `compact` drops to icons, as `CardHeader` does when its row is too narrow. Items placed in a `CardHeader` sit just after its title.

### Forms (`forms/`)
- `SchemaField`: one schema row, any type. It picks `SchemaSwitch`, `SchemaNumberField` (slider or stepper), `SchemaComboBox`, `SchemaTextField` (commits on Enter, focus loss or a suggestion; a long value wraps, growing to four lines, then scrolls; a Browse button with `x-control: "folder"`) or `SchemaObjectArray` (a list of `SchemaArrayItem`s): use `SchemaField`, not those, unless you need one alone.
- `FieldHeader`: a field's label (medium weight) with its description right under it, and a `trailing` slot on the label's line (the settings row's unsaved dot and reset, passed down as `SchemaField.headerExtra`). Every schema control draws its label through it; a switch sits at the row's right end, centred on the label and description, the row clickable. On a field at least `Widget.fieldInlineFrom` wide, a dropdown or slider sits beside the label too (`Widget.fieldControlWidth`); text boxes stay under it. The settings page's reset button's tooltip names the default.
- `FormRow`: one row of any schema form (the settings page's `SettingsField`, `SchemaPropertiesForm`'s and `SettingRows`' rows): a hairline across the gap above it (`dividerGap`; none on the top row, which the host marks `first` from `Utils.firstFormRow`, and none above an empty row; never from the row's own `y`, which the layout sets from its height: a row flipping between the two once kept the layout polishing forever and froze the shell), an accent rail beside a row shown by a sibling's value (`indented`: `SchemaField.followsSibling`), and a fold open and shut as `shown` flips. A form's grid or column keeps no row spacing of its own.
- `SchemaPropertiesForm`: a flat object; `order`.
- `SettingRows`: dotted config paths as rows, saved debounced.
- `OptionsGroup`: an inspector's Options card (problem, form, empty text).
- `IntegrationHookup`: a theme integration's hookup (text to copy, what Apply does, Apply).
- `SettingsLink`: an accent text link to where something else is set: a `setting` (a key path: `SettingsManager.openSetting`, which opens its card and outlines its row) or a `page` (a view type, or `Layouts:lockscreen` / `greeter` / `desktop`: `OverlayManager.followPageLink`). Named from its target unless `text` is set, and followed as a link, so the navigator offers the way back. It hides itself when its target isn't there; a host hiding it on its own condition binds `visible` to `available` and that.
- `FieldLinks`: a schema's `x-link` (one or a list) as `SettingsLink`s, hidden while none shows. Form rows (`SettingsField`, `SchemaPropertiesForm`) put one under each field; the bar widget and module inspectors one for the type's own.
- `GreeterSetup`: setting up the login screen (what Install changes, Install/Update/Remove, the commands left to run). Used by Settings' `GreeterStatusCard` and the onboarder.

### Bar pieces (`bar/`)
- `bar/widgets/base/BaseWidget`: the rounded box a bar widget sits in; `base/IconTextWidget`: an icon and a label along the bar's axis (rotated on a vertical bar), and a graphic of `leadLength` in `lead` before the icon (after it with `leadAfterIcon`); `steadyDigits` sizes a ticking label by its digit count.
- `WidgetBackground`: a widget's or merged run's background in the bar's widget style and shape, with the hover outline and editor highlight.
- `methods/BarShapes` (caps and SVG outlines), `methods/BarWidgetStyle` (colors per widget style), `methods/BarAutoColors` (Auto widget colors).

### Workspace pieces
- **Active workspace** (`bar/widgets/Workspaces/ActiveCellIndicator`): the active cell's box or underline (`CellUnderline`, shared with `WorkspaceCell`), drawn once under a switcher's row of cells and sliding between them.
  - Lives in `WorkspaceCellRow`; cells it stands in for set `indicated`.
  - Dots-only bars keep the cells' own recolour.
- **Strip windows** (`bar/widgets/Workspaces/StripWindows`): a workspace's windows in strip order as bar `WorkspaceCell`s (app icons, the last focused active, click focuses). Used by `ActiveStrip` (both switchers) and the `WorkspaceStrips` popout.
- **Window previews** (`surfaces/workspaces/WindowPreview`): a Hyprland client's capture, rounded.
  - Shows the app icon until it gives a frame.
  - One frame per open unless `live` (or `hovered` / `resizing`).
  - Used by the overview's windows and the switcher's tiles.

### Motion (`reusable/`)
- `Glide` / `ColorGlide` (`Glide on width {}`): a Behavior with the shell's animation, animFast eased by `Appearance.easing`.
  - `duration` for animNormal/animSlow; `enabled` to gate it.
  - A Behavior with another easing or animation is written out.
- `CrossFade`: `value` shown through a `delegate` with `required property var value`; a new copy fades in over the old on change.
  - A copy with `ready` false (an image loading) waits. Used by the cover and track text, weather and OSD icons.
- Everything else animates with Behaviors on `Appearance.animFast` / `animNormal` / `animSlow` and `Appearance.easing`.
  - Gate it with a `_settled` / `_placed` flag (`Qt.callLater` from `Component.onCompleted`) where a first layout would otherwise fly in from 0.
- (Rule: AGENTS.md › Config, "Animation".)

### Small helpers
- **Last found** (`reusable/LastFound`): the last non-null `source`, for an entry looked up by id whose delegates must never be handed null as it's removed (`shell/Dock`, `shell/OSD`).
- **Frame nudge** (`reusable/FrameNudge`): `burst()` makes its window draw and commit a few more frames. For where Hyprland keeps showing a layer's frame from before a change (a bar's stretches, the blur window's shapes).
- **Backdrop** (`reusable/BackdropRequest`): a full-screen surface's dim background (overlay, overview, launcher, power menu, onboarding), under the bars and the border. It's drawn by the screen's one backdrop window (`surfaces/backdrop/ScreenBackdrop`, built by `shell/Backdrops`), which shows the request that showed last there (`BackdropManager`).
- **Scroll memory** (`reusable/ScrollMemory`): keeps where a Flickable was scrolled to, by `key` (`EditsManager.scrollOf`, in memory), and puts it back when it's rebuilt (overlay pages are unloaded while it's closed), applied as soon as its content is long enough while it settles. A user's scroll or `cancel()` (a jump) stops it. `TitledCard.scrollKey` sets one up for a panel; an empty key keeps nothing.
- **Flash outline** (`reusable/FlashOutline`): an accent outline that shows for a moment on `flash()`: what a jump to a settings card or row lands on.
- **Surface group** (`reusable/SurfaceGroup`): keeps a surface's instances on every monitor in step when its `monitors` mode is `all`.
- **Folding** (`reusable/FoldingColumn`): a column whose height animates open and shut on `open` (not when built), clipped, its content fading with it, with paddings that fold too. `shown` stays true until fully shut, so content can be held until then. `reusable/FoldingSection` puts a `reusable/FoldHeader` (a clickable `SectionHeading` and chevron, with the unsaved dot and a section line when asked) over one, for a folding section inside a card (the theme list's groups); `FoldingCard` is the card version, on the same header.

### Blur and joins
- `reusable/CornerPiece`: a concave "inverted corner" filled up to a quarter circle, with its two edges stroked.
- `reusable/HoledItem`: its children with rects cut out (a stroke left open where something joined to it carries on).
- `hosts/popout/BlurShape` + `LayerOrigin`: a chrome surface's shape for the blur window, and where its layer window is on screen (worked out by `LayerManager`, on every compositor). `LayerSlot`: a window with a fixed place in the stack maps through it, in `LayerStack` order.
- `reusable/BlurRegion` / `reusable/BoxBlurRegion`: a window's blur region where the compositor blurs only what a window asks (`supports.blurRegion`, niri): from region pieces (`SurfaceOutline.blurRegion`/`placeRegion`), or one box mapped into its window, following a `moving` value (a slide), a scale and a fade (`opacity`; nothing while its fill's `alpha` × `opacity` is under `threshold`, as Hyprland's `ignore_alpha`).
- See [Translucency and blur](../theming/translucency-blur.md).

### Popouts
- `methods/SurfaceContext`: what a surface growing out of an edge meets at each end, and every rule that follows (joins, walls, room, detached, shadow, openings). See [Surface context](../popouts/surface-context.md).
- `hosts/popout/EdgePlacement`: all of it for a surface on a screen edge (bar popouts, edge popouts, docks).
- `hosts/popout/EdgeSurface`: an `AttachedSurface` wired from an `EdgePlacement`. A host sets only where it is, its box, `active`, colours and content.
- `hosts/popout/SubmenuHost`: a host's submenu and what it shares with it. The host sets `submenuHost`; `PopoutWrapperBase` gives it `submenu`, `openToLeft` and `childOpen`.
- `hosts/popout/ClosedLatch`: a value followed only while its host is closed (a window's layer or namespace).
- `hosts/popout/StrokeOpening`: a stroke a surface covers, left open by whatever draws it.
- `hosts/popout/SubmenuSide`: what a submenu meets on its parent's side.
- `methods/SurfaceOutline`: the shape of anything growing out of an edge (metrics, fill and stroke paths, footprint); `AttachedSurface` draws from it.
- `hosts/popout/PopoutClaim`: a host's place among the popouts; what it overlaps closes, what's above refuses it. See [Popout registry](../popouts/registry.md).
- `hosts/popout/SubPopout`: a popout's submenu.
- `PopoutAnchor`: opens one from anything in a bar or popout; `openOnHover: false` leaves opening to its owner's click.
- `content/Submenu`: a module opening another edge menu as a submenu.

### Settings cards (`views/Settings/`)
- `FoldingCard`: fold header + a `FoldingColumn` body.
- `SettingsGroupCard`: generated.
- `EntryListCard`: a list of entries as tabs with a screen picker.
- `ScreenSpotPicker`: a small screen with a spot and preset dots to click; `edgeSpot(edge, along, across)`. Used by docks, OSDs, and the launcher's `LauncherPlace` intro.
- See [Settings page](settings-page.md).

### Content and calendar parts
- **Content parts** (`content/parts/`): see [Content roots](../overlay/content-roots.md) and [Writing modules](../overlay/writing-modules.md). Also `AudioRow` (a mixer line: icon, title, volume slider, percentage, mute) `TrayMenuList` / `TrayMenuItem` (a tray menu's entries, for the tray popout and its submenus) and `CodeLine` (text to paste, a command, in a monospace box with Copy: the greeter setup, onboarding and Settings status cards).
- **Todo and pomodoro parts** (`content/parts/`): `TodoList` (the add field and the items, `fill` or capped at `maxListHeight`) `PomodoroDial` (the timer's ring, session dots, controls and task picker, `horizontal` for a wide card) `TimeRing` (a countdown ring with the time and a label in the middle, used by `PomodoroDial` and `CountdownTimer`) and `CountdownTimer` (a countdown to start from a typed duration or presets, then its ring, reset, pause and more time; the one-off timer in `content/Stopwatch` and caffeine's popout `content/Caffeine`, so both look the same); see [Todo and pomodoro](../features/todo-pomodoro.md).
- **Calendar parts** (`content/parts/calendar/`): see [Calendar](../features/calendar.md).

### Pure helpers (`methods/`)
- **Search** (`methods/Search`): shared by LauncherManager and EmojiManager.
  - `score(text, q)`: the launcher's 0–100 fuzzy match.
  - `frecency(useRecord, now)`.
  - `looksLikeMath(text)`.
- `methods/ScreenEdge`: the screen edges as numbers (`ScreenEdge.Top`, `Bottom`, `Left`, `Right`, an order code indexes arrays by) and their config names: `name(edge)`, `fromName(name)` (-1 if unknown), `fromConfig(name)` (Top if unknown), `opposite(edge)`.
- `methods/ColorTemperature.color(kelvin)`: light's color at a temperature (the night light's button).
- `KeybindFilter.columns(sections, count)`: the masonry split of the Keybinds page and the Cheatsheet module.
- **Utils** (`methods/Utils`):
  - `clone`, `freeId(base, taken, sep)` (`dock2` → `dock3`)
  - `valueAt(object, path)`: a value by its key path (every form's `valueAt`, `SettingsManager.configValueAt`, `ConfigDraft`'s read); a schema property's default by path is `SchemaLayout.defaultAt`
  - `spaceWords` (CamelCase → words), `edgeArrow(edge)`
  - `formatRate` / `rateParts` / `formatSize`, `formatBytes` (a file size, "4.2 MiB")
  - `recordUse`, `truncate`.
- `Paths.expandHome` / `shortenHome`; `KeyNames.modifierLabel`.
