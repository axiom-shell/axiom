# Utility modules

> **Files:** `components/content/Calculator/Calculator.qml`, `components/content/ClipboardHistory/ClipboardHistory.qml`, `components/content/EmojiPicker/EmojiPicker.qml`, `components/content/WorldClocks/WorldClocks.qml`, `components/content/NightLightControls/NightLightControls.qml`, `components/content/ScreenRecord/ScreenRecord.qml`, `components/content/Cheatsheet/Cheatsheet.qml`, `components/content/Brightness/Brightness.qml`
> **Config:** each module's `properties` (e.g. `WorldClocks.clocks`)
> **Related:** [Writing modules](writing-modules.md), [Launcher providers](../features/launcher-providers.md), [Night light](../theming/night-light.md), [Screenshots and recording](../features/screenshots-recording.md), [Brightness](../features/brightness.md), [Keybinds](../hyprland/keybinds.md)

Tool-like overlay modules. Each keeps its lasting state in its service, so closing the overlay loses nothing.

### Calculator (`CalculatorManager`)
- The field, the answer and a keypad. Keys type at the cursor; = takes the answer into the field.
- Wide: keys beside the field, history under it.
- Tall: the answer over the keys as a display.
- Short: one row.
- The service is described in [Launcher providers](../features/launcher-providers.md).

### ClipboardHistory (`ClipboardManager`)
- A search field, pins first.
- `GridView` columns in a wide card, with two-line previews.

### EmojiPicker (`EmojiManager`)
- A search field, Unicode group tabs and a virtualised `GridView`.
- The strip shows the most used.

### WorldClocks
- `clocks` (`[{ timezone, label }]`, edited as a list) plus the system's time.
- Rows with a day band when there's room; tiles side by side in a wide, short card.
- Offsets come from `TimeZoneManager`: see [Clock and time zones](../features/clock-timezones.md).

### NightLightControls
- Reads the `NightLight` reader. Described in [Night light](../theming/night-light.md).

### ScreenRecord (`ScreenshotManager`)
- Region or screen, the sound, and recent recordings. Described in [Screenshots and recording](../features/screenshots-recording.md).

### Cheatsheet (`KeybindManager`, read-only)
- Its own search.
- `content/parts/KeybindSection` (shared with the Keybinds page) in masonry columns; density, glyphs and folds follow the page's (`KeybindManager.page.refDensity` etc.).
- `view: "keyboard"`: `KeyboardReference` under its own `mods`, no chips.
- A click on an axiom bind opens it in the Keybinds editor (`editBind`, `ShellManager.openOverlayPage("Keybinds")`).

### Brightness (`BrightnessManager`)
- Described in [Brightness](../features/brightness.md). It can expand into every monitor's sliders: see [Growing and expanding](grow-expand.md).
