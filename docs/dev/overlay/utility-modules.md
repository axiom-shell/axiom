# Utility modules

> **Files:** `qml/components/content/Calculator/Calculator.qml`, `qml/components/content/ClipboardHistory/ClipboardHistory.qml`, `qml/components/content/EmojiPicker/EmojiPicker.qml`, `qml/components/content/WorldClocks/WorldClocks.qml`, `qml/components/content/NightLightControls/NightLightControls.qml`, `qml/components/content/ScreenRecord/ScreenRecord.qml`, `qml/components/content/Cheatsheet/Cheatsheet.qml`, `qml/components/content/Brightness/Brightness.qml`
> **Config:** each module's `properties` (e.g. `WorldClocks.clocks`)
> **Related:** [Writing modules](writing-modules.md), [Launcher providers](../features/launcher-providers.md), [Night light](../theming/night-light.md), [Screenshots and recording](../features/screenshots-recording.md), [Brightness](../features/brightness.md), [Keybinds](../hyprland/keybinds.md)

Tool-like overlay modules. Each keeps its lasting state in its service, so closing the overlay loses nothing.

Options the tools share: `showHeader` (Calculator, Chat, ClipboardHistory, ScreenRecord, Notifications; Todo and Notes too) hides the title row, and `showSearch` (ClipboardHistory, EmojiPicker, Cheatsheet) hides the search field. Each is ANDed with the room rule, so a card never shows more than it did, and a popout honours them too.

### Calculator (`CalculatorManager`)
- The field, the answer and a keypad. Keys type at the cursor; = takes the answer into the field.
- Wide: keys beside the field, history under it.
- Tall: the answer over the keys as a display.
- Short: one row.
- The service is described in [Launcher providers](../features/launcher-providers.md).

### ClipboardHistory (`ClipboardManager`)
- A search field, pins first.
- `GridView` columns in a wide card, with two-line previews.
- `showImages` (default on) leaves image entries out of the list.

### EmojiPicker (`EmojiManager`)
- A search field, Unicode group tabs and a virtualised `GridView`.
- The strip shows the most used.

### WorldClocks
- `clocks` (`[{ timezone, label }]`, edited as a list) plus the system's time.
- `style`: rows with a day band when there's room, tiles side by side in a wide, short card; Auto (default) picks by the card's size (`shownStyle`). `showSeconds` adds the seconds.
- Offsets come from `TimeZoneManager`: see [Clock and time zones](../features/clock-timezones.md).

### Notifications
- `showQuiet` (default on) turns the Quiet section and its count off; the alerts stay.

### Stopwatch
- `showLaps` (default on) hides the lap list and its copy button.

### Palette
- `labels`: `show` (default) or `hide` the semantic role names under each colour. No Auto: the card has no fit rule.

### ThemePicker
- `groups` picks which theme groups list (built-in, imported, generated); `showControls` hides the Dark/Light switch, Auto and the schedule rows.

### NightLightControls
- Reads the `NightLight` reader. Described in [Night light](../theming/night-light.md).

### ScreenRecord (`ScreenshotManager`)
- Region or screen, the sound, and recent recordings (`count`, 0-12, how many are listed; 0 hides the list). Described in [Screenshots and recording](../features/screenshots-recording.md).

### Cheatsheet (`KeybindManager`, read-only)
- Its own search (`showSearch`, when there's room).
- `content/parts/KeybindSection` (shared with the Keybinds page) in masonry columns; density, glyphs and folds follow the page's (`KeybindManager.page.refDensity` etc.).
- `style`: `auto` (default) shows the keyboard when its full layout fits, else the list (`shownStyle`); `compact` keys on the setting, never on the pick. `"keyboard"`: `KeyboardReference` under its own `mods`, no chips. It doesn't scroll, so its minimums are the keyboard's own (`keyboardHeight`, from KeyboardMap's rows): a smaller card shows the count.
- A click on an axiom bind opens it in the Keybinds editor (`editBind`, `ShellManager.openOverlayPage("Keybinds")`).

### Brightness (`BrightnessManager`)
- Described in [Brightness](../features/brightness.md). It can expand into every monitor's sliders: see [Growing and expanding](grow-expand.md).
