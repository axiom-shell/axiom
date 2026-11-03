# Icons

> **Files:** `qml/assets/fonts/MaterialSymbolsRounded.ttf`, `qml/assets/fonts/VERSION`, `qml/config/json/material-symbols.json`, `scripts/generate_icons.py`, `qml/config/Appearance.qml`, `qml/components/reusable/StyledIcon.qml`, `qml/services/ui/IconManager.qml`, `qml/components/methods/Search.qml`, `qml/components/reusable/StyledComboEntry.qml`, `qml/components/forms/SchemaField.qml`, `scripts/check_icons.py`
> **Config:** none of its own; `x-control: "icon"` on a string setting makes it an icon field
> **Related:** [Shared UI pieces](shared-ui-pieces.md), [Schema annotations](schema-annotations.md), [Testing](../testing.md)

Every icon is a Material Symbols name (`"wifi"`, `"battery_full"`) that `StyledIcon` draws in the icon font. Axiom bundles that font, so there's nothing to install and every machine draws the same version.

### The font
- `qml/assets/fonts/MaterialSymbolsRounded.ttf` is Google's Material Symbols Rounded variable font, cut down to the two axes `StyledIcon` sets: `FILL` (`fill`) and `wght` (`weight`). `GRAD` is fixed at 0 and `opsz` at 24, the values Qt drew with anyway. That takes it from 14.5 MB to about 4 MB.
- It's renamed **Axiom Material Symbols**, so a system copy of the font (`ttf-material-symbols-variable`, still installed on older setups) can never be drawn in its place. Apache-2.0 (`qml/assets/fonts/LICENSE`) allows the change and the rename. `qml/assets/fonts/VERSION` names the upstream commit.
- `qml/config/Appearance.qml` loads it with a `FontLoader`, and `Appearance.iconFamily` is the loaded family. It sits in a reader, not a service, because every `StyledIcon` reads `iconFamily`, in the shell and the greeter alike: the font is loaded wherever an icon is drawn. If the file can't be loaded, it warns once and icons show as their names.
- It reaches the greeter's copy (`git ls-files`) and the packages (`cp -r .`) with the rest of the tree.
- `StyledIcon` draws text that isn't a name (a pasted Nerd Font glyph, a word with capitals) in the text font instead.

### Updating it
- `scripts/generate_icons.py` downloads the font, its codepoints and its licence at the commit pinned in its `COMMIT` (or `--commit <sha>`) from `google/material-design-icons`. It then writes the cut-down font, `LICENSE`, `VERSION` and the catalog.
- It needs `fonttools` (Arch `python-fonttools`), only to run it. The results are committed and nothing downloads at runtime.
- After a bump, run `scripts/check_icons.py`: Google sometimes renames or drops an icon.

### The catalog
- `qml/config/json/material-symbols.json` holds one `[name, "search words"]` per icon the font has (from its `.codepoints`), most popular first.
- The words are Google's tags from `fonts.google.com/metadata/icons`, split into words, less the name's own and the few that tag over a tenth of all icons (`icon`, `symbol`, …). If that unofficial endpoint fails, the script writes names only.
- `IconManager` reads it the first time it's asked, never before an icon field is shown, and never while a page builds:
  - `search(query, limit)`: `Search.rankIcons`, below. With no query, the most popular. It reads the catalog then if it isn't read yet (a list opened or typed in).
  - `isKnown(name)`: whether the font has the name. Until the catalog is read (or when it can't be) every name is known, and asking schedules the read after the frame (`Qt.callLater`), so a page of icon fields never reads it while it builds. The binding runs again once it's read. The names are an object's keys, not a `Set`: building a `Set` of 4,300 names took ~30 ms in qs's engine, the object ~1 ms.
- `Search.rankIcons(entries, query, limit)` (pure, `tst_Search`):
  - It ranks by name with `Search.score`, reading the query's spaces as underscores (`volume up` → `volume_up`).
  - An icon whose search words (or name parts) contain every query word at a word start ranks with a name matched inside a word (50). That test is a plain substring check, not `Search.score`: its fuzzy pass over every icon's search words took 55-140 ms a keystroke, the check ~10 ms.
  - The catalog's popularity order breaks ties.

### The icon field (`x-control: "icon"`)
- `SchemaField`'s `iconField` is a `StyledComboEntry` with `editable` on and `search` from `IconManager.search`.
  - Each row shows the icon and its name.
  - The field leads with the current value drawn as an icon (a glyph shows as itself).
  - Typing filters the list; Up/Down/Enter pick. Anything typed or pasted that isn't in the list is kept on Enter or focus loss, as any typed combo does.
- When the value reads as a name the font doesn't have, a warning under the field says it will show as text.
- Every icon setting takes it:
  - a custom widget's `icon`
  - an OSD level's `icon`
  - a Chat preset's `icon`
  - a Custom page's `icon`
  - the Window, Button and Claude usage widgets' `icon`, and Tailscale's `connectedIcon` / `disconnectedIcon`
  - the custom Button and Toggle elements' `icon`
- Not it: `CustomWidget.formatIcons`, Waybar's list or object of glyphs, edited as JSON in the widget editor's Bar tab.

### The check
- `scripts/check_icons.py` (verify.sh and CI) fails on a name the catalog doesn't have, in:
  - **the built schema:** `x-icon`, `x-enumIcons`, `x-categories` icons, an `x-control: icon` default, and any `icon` / `…Icon` / `glyph` string in a default;
  - **QML:** a literal set to `icon`, `…Icon`, `glyph` or `iconText`, a `StyledIcon`'s own `text`, and the values of a `…Icons` object property.
- Only literals the expression can come out as count (each branch of `a ? "b" : "c"`, not one inside a call, an array or a comparison), and only those reading as a name. Names built at runtime aren't checked.
- `// not an icon: <reason>` skips a line.
- Tests: `CheckIcons` in `tests/scripts/test_scripts.py`.
