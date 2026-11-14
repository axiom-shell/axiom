# Style

> **Files:** `qml/config/Style.qml`, `qml/config/StyleInk.qml`, `qml/config/StyleTextRole.qml`, `qml/components/methods/Tone.qml`, `qml/components/methods/StyleTokens.qml`
> **Config:** `Appearance.font`, `Appearance.shape`, `Appearance.surface`, `Interface.*`, the theme
> **Related:** [Shared UI pieces](shared-ui-pieces.md), [Themes](../theming/themes.md), [QML pitfalls](qml-pitfalls.md), [Translucency and blur](../theming/translucency-blur.md)

`Style` is the one place UI reads a colour, text role, icon size, radius or hairline from. It derives every colour of the theme once per theme change, aliases `Appearance` and `Widget` as roles, and has a test that sweeps every bundled theme for its contrast targets. Nothing in the UI reads it yet: the pieces that do arrive with the next changes, and the bar keeps its own readability stack on the same colour math (`Tone`).

### What reads what
| Piece | What | Reads |
|---|---|---|
| `methods/Tone` | the colour math: `mix`, `over`, `alpha`, `faded`, `toward`, `luminance`, `contrast`, `nudged`, `apart`, `step`, `readableOn`, `bestOn`, `isDark`, `reaches`, `alphaFloor`, the contrast constants. Its `*Rgb` twins work on plain `[r, g, b]` arrays. | nothing (pure) |
| `methods/StyleTokens` | `theme(themeData, defaults)` resolves the semantic map as `Theme` does; `derive(theme)` is every colour role, one object; `preview(theme)` is `derive` cut to a theme tile's nine roles; `concentric`, `textPx`, `roleSize`, `reversedRamp` | `Tone` |
| `qml/config/Style` | `_roles: _derive(ThemeManager.currentTheme, ThemeManager.defaults)` (`StyleTokens.derive` of `StyleTokens.theme`, timed and logged), then typed properties | `ThemeManager`, `Theme` (pickers' passthrough, not read yet), `Appearance`, `Widget`, `StyleTokens`, `Tone`, `StyleInk`, `StyleTextRole` and nothing else (`test_scripts.py` › `StyleLayer` holds it): it is built on the lock screen and in the greeter |
| `StyleInk`, `StyleTextRole` | typed value holders Style instantiates once each | nothing |

`Style` derives from `ThemeManager.currentTheme` directly, never from several `Theme.*` reads: those update one at a time on a theme switch, and a binding reading several would run up to 30 times and could pair new and stale values ([QML pitfalls](qml-pitfalls.md) › Bindings). `Theme` itself is unchanged; `StyleTokens.theme` and `Theme._semantic` agree by test.

The roles are computed by formulas of the theme's resolved semantic map (never base slots, so a theme's own mapping is honoured). The numbers are `StyleTokens`' constants, each with a comment.

### The roles
The member list is `docs/dev/generated/api/Style.md`. The groups:
- **Surfaces** (tonal layering): `surfacePage` (the theme's raw background: chrome touching the screen), `surface` (cards), `surfaceSunken` (fields, troughs, wells), `surfaceRaised` (dropdowns, tooltips), `surfaceHighest` (switch tracks, chips, tonal buttons). `surfaceSunken` lies between the page and the card.
- **Text**: `text`, `textMuted`, `textFaint`, `textDisabled`, `textAccent`.
- **Accent and status**: `accent`, `accentAlt`, `success`, `warning`, `error`, `info`, each with `…Text`, `…Container`, `on…` and `on…Container`; `series` (8 colours for charts); `segmentTrackTone` / `segmentThumbTone` (a segmented control's chosen option is always the lighter of the pair).
- **Lines**: `divider`, `borderSubtle`, `borderStrong`, `focusRing`, `rail`, `frameStroke` (the theme's raw foreground, for what joins the screen frame).
- **State layers and washes** (translucent colours): `stateHover`, `statePressed`, `stateDrag`, `stateRest`, `stateOnAccent…`, `scrim`, `shadowSoft`, `veil`, `accentWash`, `errorWash`; the alphas as numbers (`alphaHover`, … `alphaWash`) and `opacityDisabled`.
- **Inks**: `inkPage`, `inkSurface`, `inkSunken`, `inkRaised`, `inkHighest`, `inkAccent`, `inkAccentContainer`, `ink<Status>` and `ink<Status>Container`: what reads on each fill (`StyleInk`: `text`, `muted`, `faint`, `accent`, `icon`, `graphic`, `divider`). `inkOf(tone)`, `toneColor(name)`, `toneOn(ink, tone)` look them up.
- **Text roles** (`StyleTextRole`: size, weight, default tone, default overflow): `roleMicro`, `roleCaption`, `roleBody`, `roleLabel`, `roleTitle`, `roleHeadline`, `roleDisplay`, `textRole(name)`; the sizes `typeMicro` … `typeDisplay` and weights `weightNormal`, `weightMedium`, `weightStrong`. Micro and caption never fall under 9 px at 100 % (on the Interface scale) or above body.
- **Icon sizes**: `iconXs` … `iconXl`, `iconSize(name)`.
- **Shape**: `radiusOuter`, `radius`, `radiusInner` (concentric: the radius less the spacing, never under `radiusMin`), `radiusMin`, `hairline`, `dividerWidth`, `focusWidth`.
- **Spacing**: `space1` … `space5`, `rowHeight`, `rowPadding`, `rowBleed`, `columnTarget` (a distance on screen, not on the Interface scale), `columnMin` (`Widget.textPx(400)`), `columnLeast`, `columnMax`.
- **Motion**: `staggerStep`, `enterOffset`, `shimmerPeriod`.
- **Config colour names**: `resolve(name)` reads one closed map `StyleTokens.theme` builds per theme (every semantic name, `white` and `bg3` included, and `base00`–`base0F`), then a `#hex`, then anything Qt parses.
- **Revision**: `revision` increments whenever the roles change. A `Canvas` puts it in its repaint key ([QML pitfalls](qml-pitfalls.md) › Canvas).

`Widget.textPx(n)` is a width that holds text: `Widget.px(n)` grown with the font setting (equal to it at 14 px).

### Light themes
- The semantic map already inverts the ramp for light themes: `theme-defaults.json`'s light map is in base16 order, the same slots as the dark one, as every bundled light theme's own map is. Style reads the map, never base slots, so `text` is dark and `surfacePage` light without a branch.
- Three things differ by variant, all in `StyleTokens.derive`: `surface` steps toward black (a light page is usually near white, so lighter is impossible) and `surfaceRaised` toward white; `surfaceHighest` steps at least 1.45 from the card (1.20 in dark themes: an equal luminance ratio reads weaker on a light card); state, container and divider alphas are lower, since a dark ink over a light surface reads stronger.
- The light fallback theme (a missing light theme) is `theme-defaults.json`'s palette with the grey ramp reversed (`StyleTokens.reversedRamp`, called by `ThemeManager._parseTheme`): the defaults' palette is dark, and with the light map in base16 order it would be a dark theme marked light.
- `nudged` picks its pole by contrast, so an accent too weak to read is darkened on a light theme and lightened on a dark one without a variant check.

### Guaranteed pairs and the test
Every colour a piece draws sits on a pair this list guarantees, on every bundled theme (42), two hand-made edge fixtures (`tests/fixtures/style/flat-dark.json`, `flat-light.json`: the three backgrounds equal and a weak accent, so the `step` and `apart` guards are exercised where no bundled theme reaches them), the two fallback themes and the 50 generated themes of `backend/internal/theme/palette/testdata/*.golden`. `tests/tst_StyleTokens.qml` › `test_contrast_targets` asserts it. The rows:
- text roles (`text`, `textMuted`, `textAccent`, `<s>Text`) 4.5 and `textFaint` 3.0 on the four reading tones (`surfacePage`, `surface`, `surfaceSunken`, `surfaceRaised`); `textDisabled` 2.0 on `surface`.
- `accent`, `accentAlt`, `focusRing`, `<s>` and every `series` colour 3.0 on the reading tones.
- an on-colour on its fill 4.5 (the best that exists, at least 3.0, where nothing reaches it), and the ink of every tone on its fill (`text`, `muted`, `accent`, `icon` 4.5; `faint`, `graphic` 3.0; a divider 1.12).
- the surfaces against each other (`surface` vs the page 1.08 dark / 1.06 light, `surfaceHighest` vs `surface` 1.20 / 1.45, `surfaceSunken` vs `surface` (its minimum is in the test), a segmented control's thumb vs its track 1.25), `borderSubtle` 1.12 vs the page, `borderStrong` 1.30 on the reading tones.
- `text` over the `veil` over mid grey 4.5; `text` over the page and over the card at the translucency floor over the opposite pole 3.0 (the inks of the nested tones too); `text` over the unknown-tone shade, bare and under the lock's dim, 4.5.

**Content on a fill reads that fill's ink**, never a global text role: global roles only on the four reading tones, and on `surfaceHighest`, a container or a solid fill the fill's own ink. A new pair is a row in `tst_StyleTokens`, a formula that meets it and a line here.

Each `nudged` is derived at its minimum plus a margin (`StyleTokens.margin`, 0.05; steps at half of it), so rounding a colour to 8 bits never drops a pair under it; the tests assert the plain minimum.

`tests/fixtures/style/expected.json` holds every role, translucent role and ink of four themes (catppuccin-mocha, catppuccin-latte, gruvbox-dark, tokyo-night), produced from the formulas by an independent implementation, and `test_reference_values` compares `derive` with it within 1/255 per channel. It is the only bridge to that implementation: a formula change is a change in `StyleTokens` and a regenerated `expected.json`, and drift on the other themes is caught by the pair sweep.

### Translucency
Two families, one opacity setting:
- **Free-standing surfaces** (the overlay page box, cards, prompts, pickers' boxes, lock and greeter cards): `Style.surfaceAlpha` is `Appearance.surfaceAlpha` raised to the theme's readability floor (`alphaFloor`, the least alpha at which `text` on the page and on the card, over the variant's opposite pole, still reaches 3.0), and `fillPage`, `fill`, `fillSunken`, `fillRaised`, `fillHighest` are the roles at that alpha. At 100 % opacity there is no floor.
- **The edge family** (whatever joins the screen frame or a bar: the bars, `AttachedSurface` and what is built on it, docks, menus' edge boxes): fill `surfacePage`, outline `frameStroke` (bit-equal to the raw background and foreground the bar draws today, so one colour runs where they join), at `Style.edgeAlpha` (the user's opacity, unfloored) through `Style.edgeFill(color, opaque)`, the twin of `Appearance.fill`.

Only `text` is guaranteed over the translucent fill, the veil and the shade; muted and accent lines are guaranteed opaque.

### Previews
`StyleTokens.preview(theme)` is `derive` cut to `surfacePage`, `surface`, `text`, `textMuted`, `accent`, `onAccent`, `accentContainer`, `onAccentContainer` and `divider`. `ThemeManager._preview(json)` adds it as `roles` beside the keys the theme list reads today, so a theme tile can read `modelData.preview.roles.surface` and call nothing. The theme folders' scan logs its time once under `scripts/log.sh --debug`.

### Contrast in QML and Go
One formula (WCAG 2.x relative luminance), one implementation in QML (`Tone.luminance` / `Tone.contrast`) and two in Go, one per contract: `palette.Luminance` / `palette.Contrast` (Go's `math.Pow`) for Go's own decisions and tests, and `render.Luminance` (the JS `Math.pow` port, frozen to the shell's output) for the compositor files, whose frozen cases compare exact text. They cannot be one: `math.Pow` differs from the correctly rounded `pow` in the last bit for 109 of the 245 channel values above the linearisation knee. `tests/fixtures/style/contrast.json` (24 pairs with their luminances and ratio) is asserted by `tst_Tone` › `test_contrast_fixture` and by `TestContrastFixture` in `backend/internal/theme/palette`.

### Accent and status
In 11 bundled themes the accent is within OKLab distance 0.05 of a status colour (eight of them equal one: Everforest ×2 and Submarine Sonar ×2 `success`, Gruvbox Material ×2 `warning`, Nordfox and Terafox `info`). Style keeps the theme's colours (they match the terminal and apps the integrations theme), so a piece never shows status by colour alone: a chip shows its word, a dot sits beside an icon or word. `tests/fixtures/style/collisions.json` lists the themes; `test_collisions_listed` fails on an unlisted one.

### Performance rules
1. **Theme-level colours are computed once per theme change, in one binding.** `Style._roles` depends only on `ThemeManager.currentTheme` and `ThemeManager.defaults` (one object each), so a theme switch evaluates `StyleTokens.derive` exactly once; every colour property is a plain read of `_roles`. It does not read `Theme.*` properties. `derive` makes 216–1794 contrast evaluations per theme (median 733); on `color` values that cost 2.3–5.5 ms, so `StyleTokens` runs its inner math on plain `[r, g, b]` arrays (a back's luminance once per `nudged` / `apart` call), builds `color` values only for the returned roles, and **the budget is `derive` ≤ 4 ms on the dev machine for the worst bundled theme**. No cache by theme name: a switch back costs the same one derive. Style logs `Style derived in <n> ms` (an unconditional `console.log`, shown by `scripts/log.sh --debug`), and `tst_StyleTokens` › `test_derive_time` logs the 20-run mean per theme.
2. **Setting-level values re-evaluate only when their setting changes**: `fill*` (surface opacity, blur availability, the floor), the text roles, icon sizes, `radius*`, `space*`, `hairline` bind `Appearance` / `Widget` members directly, each a typed property.
3. **Per surface context, never per delegate.** On-fill colours (`Style.ink*`), state layers and containers are precomputed. A row on an accent fill reads `Style.inkAccent.text`; it never calls `readableOn`.
4. **Delegates only read properties.** No UI binding calls a colour function (`Tone.*`, `Utils` colour functions, `Qt.alpha/lighter/darker/tint/color`). Style's lookups are not colour math and are allowed: `Style.inkOf`, `toneColor`, `toneOn`, `textRole`, `iconSize`, `resolve` (a `switch` or a map read) and `edgeFill` (one alpha, one binding per surface).

### Adding a role
A formula in `StyleTokens.derive` (its constants at the top, each with a comment), a row in `tst_StyleTokens` (a pair, if the role is drawn on a fill), a property in `Style`, and a line here. Regenerate `tests/fixtures/style/expected.json` if the role is in it. The generated `docs/dev/generated/api/Style.md` lists the members.
