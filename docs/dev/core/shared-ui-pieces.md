# Shared UI pieces

> **Files:** `qml/components/reusable/`, `qml/components/forms/`, `qml/components/content/parts/`, `qml/components/methods/Utils.qml`, `qml/components/methods/Search.qml`, `qml/components/views/Settings/FoldingCard.qml`, `qml/components/views/Settings/EntryListCard.qml`, `qml/components/views/Settings/ScreenSpotPicker.qml`, `qml/components/views/Settings/PlaceIntro.qml`
> **Config:** none
> **Related:** [Editors pattern](editors-pattern.md), [Content roots](../overlay/content-roots.md), [Writing modules](../overlay/writing-modules.md), [Popout surface context](../popouts/surface-context.md), [Translucency and blur](../theming/translucency-blur.md)

An index of reusable pieces. Reach for one of these before drawing your own; when a pattern appears a second time, it becomes one of these. (Rule: AGENTS.md › UI conventions, "Reuse before building".) Every file in `reusable/`, `forms/` and `content/parts/` is named here or in the docs it links to (`scripts/check_docs.py` checks): add a line when you add a piece.

### Sizes
Everything outside the bars follows the Interface scale and Density through `Widget` (`qml/config/Widget.qml`); a size written as a number doesn't, and `scripts/check_sizes.py` fails on one of 3 px or more, set alone or added, subtracted or chosen in a size's expression (`Widget.height - 4` is `Widget.height - Widget.px(4)`; factors like `* 2` and grid units like `span(8)` are fine).

| What | Use |
|---|---|
| A gap: 3–6 / 8 / 12–14 px | `Widget.spacing` / `Widget.spacing * 2` / `Widget.padding` |
| Inner margins of a row, field or dropdown (6–8 px) | `Widget.smallPadding` |
| A panel's or card's padding (10–22 px) | `Widget.padding` (× 2 for 18–22) |
| A control's height (fields, switches, tabs) | `Widget.height` (or a fixed share of it) |
| A square icon button | `Widget.iconButton` (`StyledIconButton`'s default `size`) |
| A chip, pill or small button (18–22 px) | `Widget.smallHeight` |
| An icon or text size | `Appearance.fontSize`, `fontSizeLarge`, or `Appearance.fontSizeBy(n)` for n px more or less (never `fontSize ± n`: the offset wouldn't scale) |
| A width, an avatar, a dot, a thin bar | `Widget.px(n)` (the Interface scale only) |
| A hairline (0–2 px, `border.width`) | the number |
| Measured against the screen, a measuring font, a placeholder or stand-in, a layout weight | the number, marked `// fixed px: <reason>` |

A size setting in px outside the bars (`Launcher.width`, `Notifications.width`, tile sizes, `Popouts.padding`) is scaled in its reader (`Widget.px(_c.width)`), so it follows the Interface scale too; gaps that line up with the compositor's (the toasts' `gap`) stay as set, and hover strips are a fixed `ScreenEdge.triggerSize` deep.

Bars size their own widgets (`BarsConfig.enrichBarConfig`) and never use these: a shared piece the bar uses takes its size from the bar (`CountBadge.textSize`, `IconTextWidget.spacing`).

### Text and structure (`reusable/`)
- `StyledText` / `StyledIcon`.
- `SpinningIcon`: a `StyledIcon` that turns while `spinning` (gated on `Appearance.animations`), upright again when it stops: the busy mark (the radio menus' scan, the dev build in the DevMode widget and the Settings banner).
- `SlashedIcon`: an icon struck through while `slashed`, one drawn slash (top left to bottom right, Material's direction) over a `cutout` line in what it sits on. Every off state is the base icon slashed, never an icon's own `_off` form, so they all look the same (the OSD's bars and status icons).
- `SectionHeading`: accent title + muted description, folded past three lines.
- `ClampedText`: muted help text cut to `maxLines` (3) with a More / Less link, shown only when it's longer. Field and card descriptions use it.
- `FieldGroup`: a titled card of fields, with a faint border (as `FoldingCard`'s); `headerExtras` beside the heading.
- `StyledContainer`: a themed box (surface opacity or solid, optional border and radius).
- `StyledScrollView`: a ScrollView with the shell's padding and a thin accent scroll bar.
- `KeyHint`: a keycap and what it does (`[↵] open`), for a controls hint.
- `content/parts/KeyCap` (a key, or a folded direction set's keys spaced in one cap, H J K L), `ModifierCap` (a combo's modifiers in one cap, as glyphs or words): keycaps for binds. `KeybindSection` / `KeybindRow` draw the keybinds reference (the Keybinds page and the Cheatsheet); `compact` follows `KeybindManager.page.refDensity`; a modifier group folds (`KeybindManager.page.refFolded`). `KeyboardMap`: a US keyboard (`methods/KeyMap`) whose keys are coloured, labelled and clicked through hooks (the editor's key map); `KeyboardReference`: the reference drawn on it, under picked modifiers.
- `StyledSeparator`: border-coloured divider (accent where a divider is accent by design).
- `SeparatorMark`: a line, dot, slash or chevron divider (the Separator widget's, the bar's `separatorStyle` and a custom widget's Separator element).
- `StatusChip` (filled status pill), `CountBadge` (a count on a button's or icon's corner; bumps when it changes), `UnsavedDot` (`onAccent` on a selected row).
  - All three are `PopInRectangle`s: set `shown` (not `visible`) and they pop in and out; `pulse()` for a bump.
- `IssueList`: `[{ level, text }]`, errors red, warnings amber.
- `TipIcon`: an icon saying what it means in a tooltip on hover (`tip`), for a flag or a problem shown without its text (the bind list's flags).
- `IssueIcon`: one problem's icon in those colors (`level`, `tone`), a `TipIcon` saying what's wrong (`tip`). Every warning or error icon shown without its text beside it is one (a bind row, a bind section, the onboarding's binds table, the keybinds reference).
- `DropdownSurface`: the box of anything that drops down. In a `Popup` (a combo box's list, `TypePickerPopup`, `StyledContextMenu`) it fills solid, `Theme.backgroundAlt`: nothing blurs behind a Popup, so a translucent fill shows the page through it.
- `TileFlow`: equal tiles, as many columns as fit.
- `TypeLibrary`: the editors' libraries of types to add.
  - An A–Z / By category switch over equal tiles of a caller's `delegate`, by label or under a heading per group (`methods/LibraryOrder`).
  - The label and heading come from the caller's `labelOf` / `headingOf` hooks (the editors translate the schema's).
  - The caller keeps `grouped`.
  - A search box beside the switch, at the right, narrows the tiles to the types whose label, type or group heading holds the text (`LibraryOrder.filtered`); the query lasts as long as the library is built (the layouts editor keeps it under a module's options).
- `KeyedLoader`: rebuilds a form when `key` changes, so rows never write old values onto a new selection.
- `StreamedLoader`: a Loader built a moment later from `BuildQueueManager`'s queue, then faded in: a page's panels, cards, sections and long lists, so a page shows at once. `wanted` gates it like `active`; `always` streams after the page's first build too, and so do the loaders inside it while it fills in. See [streamed-building](streamed-building.md).
- `LayoutOrder`: shows a layout's items in reverse order while `reversed` (`Panel.flips`: a popout growing up keeps its controls last, by the bar). Only for a layout of plain items, no Repeater directly in it.

### Controls (`reusable/`)
- `StyledTextButton`, `StyledIconButton`, `SquareIconButton`, `FlatIconButton`, `StyledRectButton` (icon, hover and press colors). `StyledIconButton` is a square of side `size` that doesn't stretch in a layout; `FlatIconButton` is one with a dimmer icon.
- `StyledToolTip`: a hover tooltip in a popup window of its own, so the small layer windows buttons live in don't clip it. Buttons take `tooltipText`; `rich` draws rich text (line breaks as `<br>`); a bar widget's is a `BarToolTip`. It stays in `reusable/` though it reads services (blur, capture freeze): the buttons here use it (AGENTS.md › Layout).
- `StyledSlider`: trough, accent fill and a round handle (`handleSize`); `moved` while dragged, `released` at the end (still `pressed`, so a value pushed in from it shows without a snap back). `value` is only pushed in (a drag never writes it, so bind it) and animates when it changes; `position` is what it shows (the drag's place while `pressed`).
- `StyledVolumeBar`: a volume bar with its icon, mute and optional percentage (drag, click or scroll; its trough clips the fill, so a low level keeps to its rounded ends); muted, its icon (the base one) is a `SlashedIcon`; with `iconClickable` the icon is a button (`iconClicked`, hover highlight, `iconTip`); `surfaces/osd/PipewireVolumeBar` binds one to a Pipewire stream or the system volume (the OSD's).
- `PercentageCircle`: a ring gauge with an icon in the middle; `sweep` below 360 opens it at the bottom (a gauge).
- `LevelMeter`: a level shown, not set: `StyledSlider`'s trough and fill without the handle, across or filling up (`vertical`); the fill is never shorter than its rounded ends. Any meter in a rounded trough is one (the custom widgets', Disks, Claude usage).
- `SegmentMeter`: a level as blocks or dots lit up to `share`, in a row or a column filling up.
  - Both are drawn by the bar's display styles (`bar/widgets/base/ValueGraphic`, [Display styles](../bar/display-styles.md)) and a custom widget's elements; a bar sets their sizes from its font.
- `SegmentButton`: a choice, accent when `active`; `Layout.fillWidth: false` in a row of pills.
- `SegmentRow`: a single choice of SegmentButtons on one track, the accent sliding to the active one. Toggles and multi-select chips stay plain rows or Flows.
- `StyledTabBar` (of `StyledTabButton`s): its current tab's highlight slides between tabs.
- `StyledTextEntry`: see [QML pitfalls](qml-pitfalls.md) (push the value in, act on `textEdited`). Search boxes set `clearable`: an X at the right while there's text, which clears it as a typed edit (`clear()`) and keeps the focus; with `escapeClears`, Escape clears it too (passed on when it's empty). The launcher's own field has the same X. A field hiding its text (`echoMode` not Normal) warns while Caps Lock is on by itself: it loads `CapsLockHint` (plumbing, the one reusable piece reading `LockKeysManager`) at the right only while it has focus, and says so in `capsHintShown`; no host sets anything ([Lock keys](../features/lock-keys.md)). `StyledTextArea`: multi-line, optionally growing with its text (`expandable`, capped at `maxLines`, then it scrolls); `singleLine` makes it a one-line value that wraps (line breaks become spaces, Enter submits, Tab moves on).
  - Both draw their cursor with `TextCursor` (an accent bar blinking while its input has focus), the `cursorDelegate` of any text input drawn by hand.
- `PasswordEntry`: a password field with a message, a busy bar and `shake()`. Its `inputMethodHints` keep every input method out (sensitive, no prediction, hidden: [input sources](../features/input-sources.md)). While its message is empty and Caps Lock is on, the message line (or the placeholder, `inlineMessage`) says so in `Theme.warning` (unless `capsMessage` is off).
  - It has no authenticator of its own: the lock screen's `PasswordField`, the greeter's `LoginField` and the polkit prompt wire it.
- `StyledComboEntry`: a choice from a list dropping down under a field, optionally typed. `search` (a function of the typed text returning the options) stands in for `options` when the list is too long to hold, asked only once the list opens or something is typed: the icon field (`x-control: icon`, [icons](icons.md)). In a popout or edge menu (its window declares `popoutRoom`) the list opens inline (`expandsInline`), inside the field's layout, since a dropdown Popup there is a window the popout's hover and blur don't reach. It's capped by the room the box has left to grow, or in an edge menu by the Flickable around it, which scrolls it into view. The dropdown Popup (a shadowed surface and a ListView) is built the first time the list opens, never for a closed field.
  - `options` `[{ value, label, icon? }]`, `value` pushed in, `picked(value)`.
  - Used by the greeter's user and session pickers.
- `StyledSwitch`.
- `StyledToggle`: a two- or three-way toggle, a capsule with each option's label in an equal segment (as wide as the widest label) and an accent thumb that glides to the chosen one. With two a click anywhere flips it (Space too); with three a click picks the segment under the pointer; Left/Right step. `options` (two or three values), `labels` `{ value: label }`, `value` pushed in, `picked(value)`. Drawn for a two- or three-value enum by `SchemaToggle` (`x-control: toggle`).
- `NotchWheel`: a `WheelHandler` that steps once per wheel notch (120, a touchpad's scroll adding up to one first), `stepped(direction)` -1 up/left, 1 down/right. Used by the workspace switchers and the overlay's page navigator.
- `TypePickerPopup`: pick a type, `{ type, label, icon }`.
- `StyledContextMenu`: a right-click menu on a `DropdownSurface`, opened at a point (`openAt(item, x, y)`). `items` `[{ id, text, icon, shortcut, enabled, checked, submenu }]` (or `{ separator: true }`); a `submenu` opens in place under a row leading back; `triggered(id)`. Up/Down, Enter or Right, Left, Escape; a press outside closes it (Popup's `closePolicy`, as `TypePickerPopup`). The bar editor's chips.
- `ActionTile`: an icon well over a label. With `opens`, a right click or long press is `opened`.
- `ActionPill`: the wide one, a well beside a name and status. With `opens`, the well toggles and the rest opens.
  - Both drain a `CountdownBar` (a bar along the bottom emptying over `duration` while `running`) over their `countdown` while active.

### Editor lists and drags (`reusable/`)
- `ListEntryRow` (+ `RowAction`, `AddEntryButton`).
- `DragArea`: drag vs tap; with `dragLayer` + `payload` it carries.
- `DragLayer`: one drag, a target registry, and a hit test.
  - `accepts` / `priority` hooks; `priority` defaults to a target's `dropPriority`.
  - Signals: `started` / `moved` / `dropped`.
- `TrashTarget`: a "Drop to remove" pill shown while `active`, `targetKind: "trash"`, above overlapping targets. The layer's `accepts` says what it takes and its `dropped` removes it.
- `DragChip`: a carryable icon + name pill; `highlighted` draws it hovered for a pointer elsewhere, and with `hasMenu` a right click is `menuRequested(x, y)`.
- `views/Layouts/EntryListTarget`: a list of rows that reorders its own carried rows.
- `InspectorHeader`: icon well, name, place, actions, then a wrapping row of `links` (shown while the host's `showsLinks`), divider.
- `UndoRedoButtons`: an editor's Undo and Redo buttons, enabled from its `canUndo` / `canRedo` (an `EditHistory`'s, `qml/services/ui/EditHistory`: snapshots before each edit, edits to one field joining a step, up to 50).
- `content/base/SaveResetActions`: an editor's Save/Discard pair, both shown only with unsaved edits or typed text. `compact` drops to icons, as `CardHeader` does when its row is too narrow. Items placed in a `CardHeader` sit just after its title. Its `help` is a "?" after the title saying what the panel is for in a `StyledToolTip` on hover (wrapped at its `maxWidth`).

### Forms (`forms/`)
- `SchemaField`: one schema row, any type. It picks `SchemaSwitch`, `SchemaNumberField` (slider or stepper), `SchemaComboBox`, `SchemaToggle` (a two- or three-value enum with `x-control: toggle`: a `StyledToggle` at the row's end; with two, a click anywhere on the row flips it), `SchemaTextField` (commits on Enter, focus loss or a suggestion; a long value wraps, growing to four lines, then scrolls; a Browse button with `x-control: "folder"`) or `SchemaObjectArray` (a list of `SchemaArrayItem`s): use `SchemaField`, not those, unless you need one alone.
- `FieldHeader`: a field's label (medium weight) with its description right under it, and a `trailing` slot on the label's line (the settings row's unsaved dot and reset, passed down as `SchemaField.headerExtra`). Those marks are `FieldChangeMarks` (`schema`, `current`, `optionLabels`, `changed`; `reset(value)` with a copy of the default, `discard()`): a schema form gets them on every field with its `changedAt` hook (`SchemaPropertiesForm`, `OptionsGroup`; the dot's click is `discardAt(path)`). Every schema control draws its label through it; a switch sits at the row's right end, centred on the label and description, the row clickable. On a field at least `Widget.fieldInlineFrom` wide, a dropdown or slider sits beside the label too (`Widget.fieldControlWidth`); text boxes stay under it. The settings page's reset button's tooltip names the default.
- `FormRow`: one row of any schema form (the settings page's `SettingsField`, `SchemaPropertiesForm`'s and `SettingRows`' rows): a hairline across the gap above it (`dividerGap`; none on the top row, which the host marks `first` from `Utils.firstFormRow`, and none above an empty row; never from the row's own `y`, which the layout sets from its height: a row flipping between the two once kept the layout polishing forever and froze the shell), an accent rail beside a row shown by a sibling's value (`indented`: `SchemaField.followsSibling`), and a fold open and shut as `shown` flips. A form's grid or column keeps no row spacing of its own.
- `SchemaPropertiesForm`: a flat object; `order`.
- `SettingRows`: dotted config paths as rows, saved debounced.
- `OptionsGroup`: an inspector's Options card (problem, form, empty text).
- `IntegrationHookup`: a theme integration's hookup (text to copy, what Apply does, Apply).
- `SettingsLink`: an accent text link to where something else is set: a `setting` (a key path: `SettingsManager.openSetting`, which opens its card and outlines its row) a `page` (a view type, or `Layouts:lockscreen` / `greeter` / `desktop`: `OverlayManager.followPageLink`), or a bar `widget` (the edge menu or page it opens, selected in the layouts editor: `OverlayManager.openedBy` / `editOpenedBy`). Named from its target unless `text` is set, and followed as a link, so the navigator offers the way back. It hides itself when its target isn't there; a host hiding it on its own condition binds `visible` to `available` and that.
- `FieldLinks`: a schema's `x-link` (one or a list) as `SettingsLink`s, hidden while none shows. Form rows (`SettingsField`, `SchemaPropertiesForm`) put one under each field; the bar widget and module inspectors one for the type's own.
- `GreeterSetup`: setting up the login screen (what Install changes, Install/Update/Remove, the commands left to run). Used by Settings' `GreeterStatusCard` and the onboarder.

### Bar pieces (`bar/`)
- `bar/widgets/base/BaseWidget`: the sizing wrapper a bar widget sits in; `base/IconTextWidget`: an icon and a label along the bar's axis (rotated on a vertical bar), and a graphic of `leadLength` in `lead` before the icon (after it with `leadAfterIcon`); its label never resizes with its digits (equal-width figures, measured as zeros, never under `minimumText`).
- `WidgetBackground`: a widget's or merged run's background in the bar's widget style and shape, with the hover outline and editor highlight.
- `methods/BarShapes` (caps and SVG outlines), `methods/BarWidgetStyle` (colors per widget style), `methods/BarAutoColors` (Auto widget colors).

### Workspace pieces
- **Active workspace** (`bar/widgets/Workspaces/ActiveCellIndicator`): the active cell's box or underline (`CellUnderline`, shared with `WorkspaceCell`), drawn once under a switcher's row of cells and sliding between them.
  - Lives in `WorkspaceCellRow`; cells it stands in for set `indicated`.
  - Dots-only bars keep the cells' own recolour.
- **Strip windows** (`bar/widgets/Workspaces/StripWindows`): a workspace's windows in strip order as bar `WorkspaceCell`s (app icons, the last focused active, click focuses). Used by `ActiveStrip` (both switchers: a `Loader` that loads only on a strip monitor, shows only with windows, and says when the strip shows alone, `stripOnly`) and the `WorkspaceStrips` popout.
- **Workspace popout root** (`bar/widgets/Workspaces/WorkspacePopoutPanel`): the `Panel` both workspace popouts (`WorkspaceGrid`, `WorkspaceStrips`) are, with the widget's payload (output, cell size and spacing, the bar's config) and the cells' colours. A cell's colours by state are `BarsConfig.workspaceCellColors`, which the bar's row reads too.
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
- Everything else animates with Behaviors on `Appearance.animFast` / `animNormal` / `animSlow` and `Appearance.easing`. A `duration:` in ms fails `check_structure` unless its line says why it's a behaviour timing (`// behaviour timing: the cursor blink`).
  - Gate it with a `_settled` / `_placed` flag (`Qt.callLater` from `Component.onCompleted`) where a first layout would otherwise fly in from 0. Hand `callLater` a method of the item (`Qt.callLater(root._settle)`), not a closure: a method's call is dropped if the item is destroyed first (a bar rebuilt), a closure's runs and throws on its null `root`.
- (Rule: AGENTS.md › Config, "Animation".)

### Small helpers
- **Cover art** (`reusable/CoverArt`): a track's cover (`source`, `MediaManager.artSource`), rounded, a new one fading in over the old (`CrossFade`), decoded at most 640 px across, a note while there's none. The Now Playing module's and the OSD's now playing card's.
- **Confirm gate** (`qml/services/core/ConfirmGate`, a services part so the launcher can use it too): the press-twice gate of a destructive action. `pass(key, needsConfirm)` arms `key` and refuses, or passes when it's already armed (or needs no confirm); `armed` (the key waiting) and `timeout` (3 s, an armed tile's `countdown`) drive the tile; `disarm()` drops it, `expired` says it ran out. The power menu's, the QuickActions module's and the Power module's session actions, and the launcher's confirming commands.
- **Last found** (`reusable/LastFound`): the last non-null `source`, for an entry looked up by id whose delegates must never be handed null as it's removed (`qml/shell/Dock`, `qml/shell/OSD`).
- **Frame nudge** (`reusable/FrameNudge`): `burst()` makes its window draw and commit a few more frames. For where Hyprland keeps showing a layer's frame from before a change (a bar's stretches, the blur window's shapes).
- **Backdrop** (`reusable/BackdropRequest`): a full-screen surface's dim background (overlay, overview, launcher, power menu, onboarding), under the bars and the border. It's drawn by the screen's one backdrop window (`surfaces/backdrop/ScreenBackdrop`, built by `qml/shell/Backdrops`), which shows the request that showed last there (`BackdropManager`).
- **Scroll memory** (`reusable/ScrollMemory`): keeps where a Flickable was scrolled to, by `key` (`EditsManager.scrollOf`, in memory), and puts it back when it's rebuilt (overlay pages are unloaded while it's closed), applied as soon as its content is long enough while it settles. A user's scroll or `cancel()` (a jump) stops it. `TitledCard.scrollKey` sets one up for a panel; an empty key keeps nothing.
- **Flash outline** (`reusable/FlashOutline`): an accent outline that shows for a moment on `flash()`: what a jump to a settings card or row lands on.
- **Surface group** (`reusable/SurfaceGroup`): keeps a surface's instances on every monitor in step when its `monitors` mode is `all`.
- **Folding** (`reusable/FoldingColumn`): a column whose height animates open and shut on `open` (not when built), clipped, its content fading with it, with paddings that fold too. `shown` stays true until fully shut, so content can be held until then. `reusable/FoldingSection` puts a `reusable/FoldHeader` (a clickable `SectionHeading` and chevron, with the unsaved dot and a section line when asked) over one, for a folding section inside a card (the theme list's groups); `FoldingCard` is the card version, on the same header. `reusable/FoldRow` is the compact one: any content, then a chevron, the whole row clickable (`toggled`; children read `hovered`), for a line that folds something open inside a popout (the Wi-Fi menu's connection details, VPN section and More options).

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
- `methods/SurfaceOutline`: the shape of anything growing out of an edge (metrics, fill and stroke paths, footprint); `AttachedSurface` draws from it. Its far corners are capped at the room the box has, as a Rectangle's radius is: the radius never changes a surface's size.
- `hosts/popout/PopoutClaim`: a host's place among the popouts; what it overlaps closes, what's above refuses it. See [Popout registry](../popouts/registry.md).
- `hosts/popout/SubPopout`: a popout's submenu.
- `PopoutAnchor`: opens one from anything in a bar or popout; `openOnHover: false` leaves opening to its owner's click.
- `content/Submenu`: a module opening another edge menu as a submenu.

### Settings cards (`views/Settings/`)
- `FoldingCard`: fold header + a `FoldingColumn` body, in a faint border so neighbouring cards stay apart.
- `SettingsGroupCard`: generated.
- `EntryListCard`: a list of entries as tabs with a screen picker.
- `ScreenSpotPicker`: a small screen with a spot and preset dots to click, and a press or drag anywhere on it that places the thing on the nearest edge (`ScreenEdge.spotPlace`, the inverse of `ScreenEdge.edgeSpot`; a tie keeps its `edge`, so the middle doesn't flip). With `floats` the drag also sets `distance` and `detached`, attaching it within `snap` of an edge. Either way it emits `picked(values)`, as a preset does, only when the whole-percent values change. With `floats` its dots are the same nine for every placed surface (`placeSpots`: the centre, each edge's middle, the corners), each applying what a drag to it would. Used by docks and OSDs (`EntryListCard`, floating), `PlaceIntro` (floating) and notifications (`NotificationsPreview`, its own dots).
- `PlaceIntro`: the `x-intro` of a section placed anywhere (`edge`, `position`, `detached`, `distance`): a floating `ScreenSpotPicker` (its nine spots) and its hint, writing `sectionKey` through the settings draft. `LauncherPlace` and `WindowSwitcherPlace` only name their section.
- See [Settings page](settings-page.md).

### Content and calendar parts
- **Content parts** (`content/parts/`): see [Content roots](../overlay/content-roots.md) and [Writing modules](../overlay/writing-modules.md). Also `AudioRow` (a mixer line: icon, title, volume slider, percentage, mute) `TrayMenuList` / `TrayMenuItem` (a tray menu's entries, for the tray popout and its submenus) `VpnRow` (one VPN of `VpnManager.rows` as a `DeviceRow`: toggles on click, and shows a password field per secret while NetworkManager asks for them; the VPN popout and the Wi-Fi menu) `DriveRow` (one drive of `DrivesManager.drives` as a `DeviceRow`: opens on click, ejects from its end button, lists several volumes under it and shows the passphrase field of a LUKS volume asked to unlock) `RequiredFieldReport` (tells the greeter or lock surface its Login or Password module shows, `SurfaceManager.reportRequiredField`, so it draws no field of its own) `SecretField` (a secret typed inline: a hidden-text field and the button submitting it, Enter submits and Escape cancels; VpnRow's secrets, WifiJoinForm's password, DriveRow's passphrase) `WifiJoinForm` (what joining a Wi-Fi network asks for by its security, `NetworkingManager.join`'s fields: password, WEP key, LEAP or PEAP/TTLS login with the inner method, outer identity and CA check under More; `hidden` adds the name and a choice of security) `WeatherCurrent` (the weather now: place, condition icon, temperature, condition and details; the Weather card and its popout) `ConnectionDetails` (`NetworkingManager.details` as label / value lines, the addresses copyable) `DeviceRow`'s `hoverActions` (buttons shown on hover before forget, over the end of the name so no row's layout depends on them: the Wi-Fi menu's autoconnect) and `iconBadge` (a small icon on the icon's corner: the Wi-Fi menu's lock) and `RadioHeader`'s children (before the switch: Wi-Fi's airplane mode; `switchShown` false drops the switch) and `CodeLine` (text to paste, a command, in a monospace box with Copy: the greeter setup, onboarding and Settings status cards).
- **Todo and pomodoro parts** (`content/parts/`): `TodoList` (the add field and the items, `fill` or capped at `maxListHeight`) `PomodoroDial` (the timer's `DialControls` (stop, start-pause, skip), then the session dots and the task picker, built only with `showTask`) `TimeRing` (a countdown ring with the time and a label in the middle, the label growing with the ring; it sweeps on between progress steps a `tick` apart and turns the warning colour while `urgent`; used by `DialControls`), `DialControls` (a `TimeRing` over or beside three round buttons, the middle one filled in the ring's colour, centred in the room it has; `fill` in a card sizes the ring and buttons to the room, `horizontal` (on by itself when that room is wide and short) puts them side by side; the wheel and + / - step it with `steps`, a right click on the right button offers `choices`, and once clicked it takes Space and two keys; the countdown's, the stopwatch's and the pomodoro's running view) and `CountdownTimer` (a countdown to start from a typed duration, what it reads as shown at the field's end, or from presets and recent ones spread evenly over full-width rows (`methods/ChipRows`), then `DialControls` with the time left and when it ends; the one-off timer in `content/Stopwatch` and caffeine's popout and module `content/Caffeine`, so both look the same); see [Todo and pomodoro](../features/todo-pomodoro.md).
- **Calendar parts** (`content/parts/calendar/`): see [Calendar](../features/calendar.md).
- **Default app pickers** (`content/parts/DefaultAppPickers`): a picker per default app role (`DefaultAppsManager.roleList`, or those `roles` names), the installed apps with their icons (`StyledComboEntry` options' `image`), saved at once to the user's mimeapps.list; a line under a role the Apps section's command stands in for. Settings' Default apps card and the onboarder's Apps page.
- **Tool checks** (`content/parts/ToolChecks`): the optional programs features use (`DependencyManager.tools`), each installed or not, `columns` to a line, and a `CodeLine` installing the missing ones here; checked when built, `check()` again. The onboarder's Checks page and Settings › System's Optional packages.

### Pure helpers (`methods/`)
- **Search** (`methods/Search`): shared by LauncherManager and EmojiManager.
  - `score(text, q)`: the launcher's 0–100 fuzzy match.
  - `frecency(useRecord, now)`, and `useBonus(frecency)`: the 0–25 it adds to a match's score (apps, commands, emoji).
  - `looksLikeMath(text)`.
- `methods/ScreenEdge`: the screen edges as numbers (`ScreenEdge.Top`, `Bottom`, `Left`, `Right`, an order code indexes arrays by) and their config names: `name(edge)`, `fromName(name)` (-1 if unknown), `fromConfig(name)` (Top if unknown), `opposite(edge)`.
- `methods/ChipRows.split(count, fit)`: a set of equal chips spread evenly over as few rows as `fit` allows (5 at 3 a row: 3 + 2), so each row can fill its width; `starts(sizes)`.
- `methods/ColorTemperature.color(kelvin)`: light's color at a temperature (the night light's button).
- `KeybindFilter.columns(sections, count)`: the masonry split of the Keybinds page and the Cheatsheet module.
- **Utils** (`methods/Utils`):
  - `clone`, `freeId(base, taken, sep)` (`dock2` → `dock3`)
  - `valueAt(object, path)`: a value by its key path (every form's `valueAt`, `SettingsManager.configValueAt`, `ConfigDraft`'s read); a schema property's default by path is `SchemaLayout.defaultAt`
  - `spaceWords` (CamelCase → words), `edgeArrow(edge)`
  - `formatRate` / `rateParts` / `formatSize`, `formatBytes` (a file size, "4.2 MiB")
  - `recordUse`, `truncate`.
- `Paths.expandHome` / `shortenHome`; `KeyNames.modifierLabel`.
