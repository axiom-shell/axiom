# ui-kit
reviewed: 4d8f880 2026-10-31  (full)

The kit is in use everywhere, with no piece nothing uses and the service-import and duration rules held. Its oldest controls predate the motion conventions (nine animate with their own easings in written-out Behaviors) and carry defaults every user overrides (the slider, the icon button). At its seams, the notes and chat rename fields bind `text` and bring a cancelled rename back, and `Icons.overrides` reaches only the tray.

## Open findings
- Major: [Icons.overrides never reaches window icons](../../docs/dev/issues.md#iconsoverrides-never-reaches-window-icons)
- Major: [A cancelled rename's typed text comes back in the notes and chat rename fields](../../docs/dev/issues.md#a-cancelled-renames-typed-text-comes-back-in-the-notes-and-chat-rename-fields)
- Major: [Nine shared controls animate with their own easing, written out where Glide does it](../../docs/dev/issues.md#nine-shared-controls-animate-with-their-own-easing-written-out-where-glide-does-it)
- Cleanup: [Every StyledSlider overrides its look and its value the same way](../../docs/dev/issues.md#every-styledslider-overrides-its-look-and-its-value-the-same-way)
- Cleanup: [Eleven StyledIconButtons undo its stretching to be FlatIconButtons](../../docs/dev/issues.md#eleven-stylediconbuttons-undo-its-stretching-to-be-flaticonbuttons)
- Cleanup: [StyledRectButton's badge and border press colour have no user](../../docs/dev/issues.md#styledrectbuttons-badge-and-border-press-colour-have-no-user)
- Cleanup: [ActionTile and ActionPill carry the same countdown bar](../../docs/dev/issues.md#actiontile-and-actionpill-carry-the-same-countdown-bar)
- Cleanup: [StyledTextEntry and StyledTextArea carry the same blinking cursor](../../docs/dev/issues.md#styledtextentry-and-styledtextarea-carry-the-same-blinking-cursor)
- Cleanup: [TileGrid and StyledVolumeBar keep lines nothing reads](../../docs/dev/issues.md#tilegrid-and-styledvolumebar-keep-lines-nothing-reads)
- Minor (unrecorded): TypePickerPopup clears its search by assignment (`components/reusable/TypePickerPopup.qml:72`); StyledTextEntry has two push forms (`text` and `input.text = …`) and qml-pitfalls.md names neither; shared-ui-pieces.md's Utils list misses 13 functions; PasswordEntry's header leaves out the greeter's LoginField; Utils.rateParts names decimal units for a 1024 divisor.

## Contract
Holds: every file in `reusable/`, `forms/` and `content/parts/` is used (none has zero users) and named in the docs (check_docs); only StyledToolTip, StreamedLoader, BackdropRequest, ScrollMemory and SurfaceGroup in `reusable/` import services; looping animations gate on `Appearance.animations` (PasswordEntry's busy bar, RadioHeader's scan) except the text cursors' blink, which is behaviour (gating it would leave the cursor at whatever opacity it stopped at); every `duration:` is an `Appearance.anim*` or marked behaviour timing; `Appearance.borderRadius` appears only in Widget's fallback and CornerPiece (an outer join); StyledComboEntry's push pattern (`value` in, `picked` out, `_showText` never counted as typing, the pick shown before the owner hears it), its inline mode in popouts and edge menus and its keyboard paths; CrossFade's latest-wins swap and `ready` wait; StyledTextEntry's `typed` / `textEdited` contract inside the kit (the combo, PasswordEntry, the clear button); DragArea/DragLayer's tap vs drag and target choice; Widget's density table and `px`; IconResolver is pure and AppIconManager caches per class and resets on desktop-entry changes. Broken: the easing rule and the write-back contract at two callers (above).

## Coverage
Read deeply: StyledComboEntry, StyledTextEntry, StyledSlider, StyledVolumeBar, ActionTile, ActionPill, the icon and text buttons (StyledIconButton, FlatIconButton, SquareIconButton, StyledRectButton, StyledTextButton, RowAction), StyledToolTip, StyledTabBar/StyledTabButton, SegmentRow/SegmentButton, PercentageCircle, PasswordEntry, CrossFade, DragArea, DragLayer, TypePickerPopup, LevelMeter, StyledIcon, Widget, IconResolver, AppIconManager, IconsConfig; Utils by function (each counted, the formatters read). · Outlined (the collection table: users per file, members no other file names, durations, easings, loops, radii, service imports, Timers, `ConfigManager.config`, `onTextChanged` and `input.text =` callers): the rest of `reusable/`. · Skipped (deeply reviewed this month by their own systems, seams only): `forms/` and the Settings cards (config, `--deep`), `content/parts/` (modules, `--deep`), CornerPiece, HoledItem, BlurRegion, BoxBlurRegion (blur), ScrollMemory (config), StreamedLoader (overlay).
Checked and fine: no piece with zero users; TypePickerPopup (the bar editor's per-section add) and TypeLibrary (the inspectors') overlap but serve two places; StyledTabBar's tabs switch a pane where SegmentRow is a choice, so not merged; the `_settled` flags read from outside are other objects' of the same name.

## History
- 2026-10-31 full: 14 findings (3 Major, 6 Cleanup, 5 Minor); recorded
