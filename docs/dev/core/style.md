# Style

> **Files:** `qml/config/Style.qml`, `qml/config/StyleInk.qml`, `qml/config/StyleTextRole.qml`, `qml/components/methods/Tone.qml`, `qml/components/methods/StyleTokens.qml`
> **Config:** `Appearance.font`, `Appearance.shape`, `Appearance.surface`, `Interface.*`, the theme
> **Related:** [Shared UI pieces](shared-ui-pieces.md), [Themes](../theming/themes.md), [QML pitfalls](qml-pitfalls.md), [Translucency and blur](../theming/translucency-blur.md)

`Style` is the one place UI reads a colour, text role, icon size, radius or hairline from. It derives every colour of the theme once per theme change, aliases `Appearance` and `Widget` as roles, and has a test that sweeps every bundled theme for its contrast targets. The shared pieces (below) read it, and the bar keeps its own readability stack on the same colour math (`Tone`).

### What reads what
| Piece | What | Reads |
|---|---|---|
| `methods/Tone` | the colour math: `mix`, `over`, `alpha`, `cleared`, `faded`, `toward`, `luminance`, `contrast`, `nudged`, `apart`, `step`, `readableOn`, `bestOn`, `isDark`, `reaches`, `alphaFloor`, the contrast constants. Its `*Rgb` twins work on plain `[r, g, b]` arrays. | nothing (pure) |
| `methods/StyleTokens` | `theme(themeData, defaults)` resolves the semantic map as `Theme` does; `derive(theme)` is every colour role, one object; `preview(theme)` is `derive` cut to a theme tile's nine roles; `concentric`, `textPx`, `roleSize`, `reversedRamp` | `Tone` |
| `qml/config/Style` | `_roles: _derive(ThemeManager.currentTheme, ThemeManager.defaults)` (`StyleTokens.derive` of `StyleTokens.theme`, timed and logged), then typed properties | `ThemeManager`, `Theme` (pickers' passthrough, not read yet), `Appearance`, `Widget`, `StyleTokens`, `Tone`, `StyleInk`, `StyleTextRole` and nothing else (`test_scripts.py` › `StyleLayer` holds it): it is built on the lock screen and in the greeter |
| `StyleInk`, `StyleTextRole` | typed value holders Style instantiates once each | nothing |

`Style` derives from `ThemeManager.currentTheme` directly, never from several `Theme.*` reads: those update one at a time on a theme switch, and a binding reading several would run up to 30 times and could pair new and stale values ([QML pitfalls](qml-pitfalls.md) › Bindings). `Theme` itself is unchanged; `StyleTokens.theme` and `Theme._semantic` agree by test.

The roles are computed by formulas of the theme's resolved semantic map (never base slots, so a theme's own mapping is honoured). The numbers are `StyleTokens`' constants, each with a comment.

### The roles
The member list is `docs/dev/generated/api/Style.md`. The groups:
- **Surfaces** (tonal layering): `surfacePage` (the theme's raw background: chrome touching the screen), `surface` (cards), `surfaceSunken` (fields, troughs, wells), `surfaceRaised` (dropdowns, tooltips), `surfaceHighest` (switch tracks, chips, tonal buttons). `surfaceSunken` lies between the page and the card in dark themes and is a step darker than the card in light themes.
- **Text**: `text`, `textMuted`, `textFaint`, `textDisabled`, `textAccent`.
- **Accent and status**: `accent`, `accentAlt`, `success`, `warning`, `error`, `info`, each with `…Text`, `…Container`, `on…` and `on…Container`; `series` (8 colours for charts); `segmentTrackTone` / `segmentThumbTone` (a segmented control's chosen option is always the lighter of the pair).
- **Lines**: `divider`, `borderSubtle`, `borderStrong`, `focusRing`, `rail`, `frameStroke` (the theme's raw foreground, for what joins the screen frame).
- **State layers and washes** (translucent colours): `stateHover`, `statePressed`, `stateDrag`, `stateRest`, `stateOnAccent…`, `scrim`, `shadowSoft`, `veil`, `accentWash`, `errorWash`; `opacityDisabled` (the alphas as numbers live in `StyleTokens`).
- **Inks**: `inkPage`, `inkSurface`, `inkSunken`, `inkRaised`, `inkHighest`, `inkAccent`, `inkAccentContainer`, `ink<Status>` and `ink<Status>Container`: what reads on each fill (`StyleInk`: `text`, `muted`, `faint`, `accent`, `icon`, `graphic`, `divider`); a solid fill's `graphic` (a switch's knob) is the page colour where it reaches 3.0 on the fill, else its on-colour; there are no `on*` colour properties (read the fill's ink). `inkOf(tone)`, `toneColor(name)`, `toneOn(ink, tone)` look them up; `toneFill(name)` is a meter or bar fill by tone (accent, success, warning, error, info); `trendLine(tone)` the line colour of a `MarketMath.trendTone` (success, error, else faint).
- **Text roles** (`StyleTextRole`: size, weight, default tone, default overflow): `roleMicro`, `roleCaption`, `roleBody`, `roleLabel`, `roleTitle`, `roleHeadline`, `roleDisplay`, `textRole(name)`; the sizes `typeMicro` … `typeDisplay` and weights `weightNormal`, `weightMedium`, `weightStrong`. Micro and caption never fall under 9 px at 100 % (on the Interface scale) or above body.
- **Icon sizes**: `iconXs` … `iconXl`, `iconSize(name)`. `minHit(icon)` is the hit square of a small icon button (the small control height, or the glyph plus a gap each side).
- **Shape**: `radiusOuter`, `radius`, `radiusInner` (concentric: the radius less the spacing, never under `radiusMin`; a row inside a rounded box uses `Style.radiusInner`, never `Widget.radius / 2`), `radiusMin`, `hairline`, `dividerWidth`, `focusWidth`. UI never reads `Widget.radius` (R19): `Style.radius` / `radiusInner`. A shape inset inside another (a segment thumb, a switch knob, a stepper's buttons) takes `Style.concentric(the holder's radius, its inset)` (`StyleTokens.concentric` with `radiusMin`).
- **Row heights**: `Style.listRowHeight` (a list entry row), `Style.chipRowHeight` (`Widget.height + Widget.padding / 2`: bar lane chips, grid drag chips, keybind rows) and `Widget.compactHeight` (`Widget.height` less 6 px at scale: a list row's action, a lane's tool button), `Widget.slimHeight` (`Widget.height` less 4 px at scale: a switch's or segmented row's track, a chip or button in a full-height line).
- **Spacing**: `space1` … `space5`, `cardGap` (the gap between two cards, down and across: `space2`, the settings page's), `rowHeight`, `rowPadding`, `rowBleed`, `columnTarget` (a distance on screen, not on the Interface scale), `columnMin` (`Widget.textPx(400)`), `columnLeast`, `columnMax`.
- **Motion**: `enterOffset`, `shimmerPeriod`.
- **Config colour names**: `resolve(name)` reads one closed map `StyleTokens.theme` builds per theme (every semantic name, `white` and `bg3` included, and `base00`–`base0F`), then a `#hex`, then anything Qt parses.
- **Revision**: `revision` increments whenever the roles change. A `Canvas` puts it in its repaint key ([QML pitfalls](qml-pitfalls.md) › Canvas).

`Widget.textPx(n)` is a width that holds text: `Widget.px(n)` grown with the font setting (equal to it at 14 px).

### Light themes
- The semantic map already inverts the ramp for light themes: `theme-defaults.json`'s light map is in base16 order, the same slots as the dark one, as every bundled light theme's own map is. Style reads the map, never base slots, so `text` is dark and `surfacePage` light without a branch.
- Four things differ by variant, all in `StyleTokens.derive`: `surface` steps toward black (a light page is usually near white, so lighter is impossible) and `surfaceRaised` toward white; `surfaceHighest` steps at least 1.45 from the card (1.20 in dark themes: an equal luminance ratio reads weaker on a light card); `surfaceSunken` is the card mixed toward the text and moved a step darker (1.07; in dark themes the page/card mix); the accent container mixes as far as in dark themes (0.24) and is kept at least 1.25 from the page and the card; only the state, status-container and divider alphas are lower, since a dark ink over a light surface reads stronger.
- The light fallback theme (a missing light theme) is `theme-defaults.json`'s palette with the grey ramp reversed (`StyleTokens.reversedRamp`, called by `ThemeManager._parseTheme`): the defaults' palette is dark, and with the light map in base16 order it would be a dark theme marked light.
- `nudged` picks its pole by contrast, so an accent too weak to read is darkened on a light theme and lightened on a dark one without a variant check.

### Guaranteed pairs and the test
Every colour a piece draws sits on a pair this list guarantees, on every bundled theme (42), two hand-made edge fixtures (`tests/fixtures/style/flat-dark.json`, `flat-light.json`: the three backgrounds equal and a weak accent, so the `step` and `apart` guards are exercised where no bundled theme reaches them), the two fallback themes and the 50 generated themes of `backend/internal/theme/palette/testdata/*.golden`. `tests/tst_StyleTokens.qml` › `test_contrast_targets` asserts it. The rows:
- text roles (`text`, `textMuted`, `textAccent`, `<s>Text`) 4.5 and `textFaint` 3.0 on the four reading tones (`surfacePage`, `surface`, `surfaceSunken`, `surfaceRaised`); `textDisabled` 2.0 on `surface`.
- `accent`, `accentAlt`, `focusRing`, `<s>` and every `series` colour 3.0 on the reading tones.
- an on-colour on its fill 4.5 (the best that exists, at least 3.0, where nothing reaches it), and the ink of every tone on its fill (`text`, `muted`, `accent`, `icon` 4.5; `faint`, `graphic` 3.0; a divider 1.12).
- the surfaces against each other (`surface` vs the page 1.08 dark / 1.06 light, `surfaceHighest` vs `surface` 1.20 / 1.45, `surfaceSunken` vs `surface` (its minimum is in the test), a segmented control's thumb vs its track 1.25, `accentContainer` vs the page and vs the card 1.25 in both variants), `borderSubtle` 1.12 vs the page, `borderStrong` 1.30 on the reading tones.
- `text` over the `veil` over mid grey 4.5; `text` over the page and over the card at the translucency floor over the opposite pole 3.0 (the inks of the nested tones too); `text` over the unknown-tone shade, bare and under the lock's dim, 4.5.

**Content on a fill reads that fill's ink**, never a global text role: global roles only on the four reading tones, and on `surfaceHighest`, a container or a solid fill the fill's own ink. A new pair is a row in `tst_StyleTokens`, a formula that meets it and a line here.

Each `nudged` is derived at its minimum plus a margin (`StyleTokens.margin`, 0.05; steps at half of it), so rounding a colour to 8 bits never drops a pair under it; the tests assert the plain minimum.

`tests/fixtures/style/expected.json` holds every role, translucent role and ink of four themes (catppuccin-mocha, catppuccin-latte, gruvbox-dark, tokyo-night), produced from the formulas by an independent implementation, and `test_reference_values` compares `derive` with it within 1/255 per channel. It is the only bridge to that implementation: a formula change is a change in `StyleTokens` and a regenerated `expected.json`, and drift on the other themes is caught by the pair sweep.

### Translucency
Two families, one opacity setting:
- **Free-standing surfaces** (the overlay page box, cards, prompts, pickers' boxes, lock and greeter cards): `Style.surfaceAlpha` is `Appearance.surfaceAlpha` raised to the theme's readability floor (`alphaFloor`, the least alpha at which `text` on the page and on the card, over the variant's opposite pole, still reaches 3.0), and `fillPage`, `fill`, `fillSunken`, `fillRaised`, `fillHighest` are the roles at that alpha. At 100 % opacity there is no floor.
- **The edge family** (whatever joins the screen frame or a bar: the bars, `AttachedSurface` and what is built on it, docks, menus' edge boxes): fill `surfacePage`, outline `frameStroke` (bit-equal to the raw background and foreground the bar draws today, so one colour runs where they join), at `Style.edgeAlpha` (the user's opacity, raised to the wallpaper's edge floor: `Appearance.wallpaperEdgeFloor`, [Translucency and blur](../theming/translucency-blur.md)) through `Style.edgeFill(color, opaque)`.
  - Edge family files: `AttachedSurface` and what is built on it (bar popouts, `EdgePopout`, `EdgeSurface`, `SubPopout`), the launcher, floating edge and free menus, docks, `MenuTile`, `IntegratedEdgeMenu`'s strip and frame, `RoundedBorders`, `BorderPanel`. Toasts take its fill and translucency but join nothing: their outline is `borderSubtle`.
  - Free-standing (`Surface { tone: "page" }`: `fillPage`, `borderSubtle`, `radiusOuter`): the prompt and polkit cards, the power menu card, the monitor prompt, the screen-share and screenshot pickers' boxes, the workspace overview box, onboarding, the lock and greeter cards; `raised` for popup menus (the dock's context menu).

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
4. **Delegates only read properties.** No UI binding calls a colour function (`Tone.*`, `Utils` colour functions, `Qt.alpha/lighter/darker/tint/color`). Style's lookups are not colour math and are allowed: `Style.inkOf`, `toneColor`, `toneOn`, `toneFill`, `trendLine`, `textRole`, `iconSize`, `resolve` (a `switch` or a map read) and `edgeFill` (one alpha, one binding per surface).

### Pieces
What to reach for (every piece is in `qml/components/reusable/`; [shared-ui-pieces](shared-ui-pieces.md) › Style pieces has each one's API):
| You need | Use |
|---|---|
| A box | `Surface` (`tone`, `outlined`, `solid`, `shadowed`) |
| An editor page | `ToolPane` + `WorkArea` + `InspectorHeader` (recipe [tool-page](../../recipes/tool-page.md)) |
| Hover, press, drag on a control | `StateLayer`, first in the control |
| Keyboard focus | `FocusRing` (only on controls that take Tab focus) |
| A loading placeholder | `Skeleton` |
| A list that grows and shrinks | `MotionListView` |
| A menu or dropdown row | `MenuRow` |
| Text | `StyledText` / `StyledLabel` with a `role` and a `tone`; an icon: `StyledIcon` with a `size` |

Text and icons inside a Surface take its `ink` by default: `InkHost.find` walks from a text up its visual parents to the nearest item with an `inkScope` (or a relay, which answers for the host above it), in a binding, so it follows a reparent and the first colour is already the ink. Put content inside the Surface it sits on (a sibling fill is not inherited); a Popup's content sits in another window, finds no Surface, and takes the global roles. A colour set explicitly is still a role (`<surface>.ink.*`, `Style.*`), never a literal: `scripts/check_style.py` ([testing](../testing.md) › The checks) enforces it.

The old way to the new, by what the code wrote:
| Old | New |
|---|---|
| `Appearance.fontSizeBy(-4)`, `(-3)` | `role: "micro"` |
| `fontSizeBy(-2)`, `(-1)` | `role: "caption"` (or `body` for reading text) |
| `Appearance.fontSize` | `role: "body"`, or `"label"` for a control or row name |
| `fontSizeBy(1)`, `(2)` | `role: "label"` / `"title"` |
| `fontSizeBy(3)`, `(4)`, `fontSizeLarge` | `role: "headline"` |
| `fontSizeBy(6)` and up | `"headline"`, `"display"`, or a fitted size |
| `Theme.foreground` / `foregroundInactive` | `Style.text` / `Style.textMuted` (a `tone` on a StyledText) |
| `Theme.accent` as text | `Style.textAccent`; as a fill `Style.accent` with `Style.inkAccent.text` on it |
| `Qt.alpha(...)` over a fill, `opacity: 0.5` | a role (`Style.stateHover`, `scrim`, `veil`, `textFaint`) or `Style.opacityDisabled` |
| `font.bold: true` | the role's weight, or `font.weight: Font.Bold` where bold must stay |
| `Theme.resolveColor(name)` | `Style.resolve(name)` |
| `Qt.lighter`/`darker` hover tint | `StateLayer` |

### Crisp text
Text and icons are native at rest (hinted, snapped to device pixels) and distance field only under a declared zoom: `StyledText.renderType` is `TextRender.typeFor(_drawnZoom, ...)`, where `_drawnZoom` is `TextRender.zoomAt(parent)`, the product of every `contentZoom` above it up to the nearest publisher. Both walks stop at the nearest publisher: a Surface or a MenuRow (each has an `inkScope` and `drawnZoom`) or a relay (`StreamedLoader`, `StyledIconButton`, `FormRow`, the page and module zoom hosts: `inkHostAbove` and `drawnZoom`). `qml/shell.qml` and `qml/greeter.qml` carry `//@ pragma NativeTextRendering` (Controls internals and anything missed) and `//@ pragma Env QSG_DISTANCEFIELD_ANTIALIASING=gray` (no colour fringes on zoomed or rotated distance-field text).
- A raw `Text`, `TextInput`, `TextEdit`, `TextField` or `TextArea` carries `renderType: TextRender.typeFor(TextRender.zoomAt(parent), false, 0)` (R16).
- Shows fade and slide; nothing scales over text but a declared zoom.
- An item with a persistent `scale` other than 1 that holds text declares `readonly property real contentZoom: scale` (R18).
- Never `layer.enabled` / `layer.effect` on an item that holds text (a layer resamples it, blurred at any fractional scale): a soft shadow is a `RectangularShadow` (`Surface.shadowed`). Masks, shadow sources, art and blur sources keep theirs with `// style-exempt: no text` (R17).
- `Screen.devicePixelRatio` is the rounded-up integer under fractional scaling: use `item.Window.window.devicePixelRatio`. `font.hintingPreference` is never set.

### Text layout
Three units for a size: control sizes from `Widget` (`Widget.px(n)`), text measures from `Widget.textPx(n)` (a width whose job is to hold n characters: label columns, column minimums, panel widths), screen measures from `GridPlacement`. A text decides what happens when it does not fit through `overflow` (`line`: one line, elided; `wrap`: wraps and breaks a long token; `none`) and `maxLines`, with the role's default when unset; never `wrapMode`, `elide` or `maximumLineCount` on a StyledText (R14); an identifier (a path, a key) that should lose its middle, not its end, adds `elide: Text.ElideMiddle` on a line marked `// style-exempt: middle`. An elided text needs a bound in a `RowLayout` (`Layout.fillWidth` or a maximum width, R15). A fitted size is `Math.max(Style.typeMicro, ...)` on a line marked `// fitted:` (R4). Sizes that hold a text round their width up (`Math.ceil`) so it never elides by a fraction.

### Over the wallpaper
Where text sits straight on the wallpaper, the style layer decides from what is under it (D-72…D-75; `theme.backdrop`, [Themes](../theming/themes.md)): Go samples each shown wallpaper into a small luminance grid, `WallpaperToneManager` maps a rectangle onto it (`Backdrop.region`, through the wallpaper's own placement and parallax travel) and `Tone` decides.
- One alpha function serves three uses: `Tone.alphaFloor(fill, ink, backs, 4.5 + margin)`, the least alpha of `fill` over every back at which `ink` reads. A translucent bar's fill floor (`Style.edgeAlpha`, [Translucency and blur](../theming/translucency-blur.md)), a transparent bar's shade ([Bar widget style](../bar/widget-style.md)), and a bare module's shade (`BackdropScrim`, [Shared UI pieces](shared-ui-pieces.md)).
- The shade is the theme background (`Style.surfacePage`), never a halo; colours the user picked stay as set and get the shade computed from them, which stops at the opaque background where they can't read.
- Unknown tone: at shell start, until the daemon answers, nothing changes (no shade, no floor) and then it glides (on a wallpaper change the previous wallpaper's grid stands in until the new one's arrives); a wallpaper the daemon can't decode, no daemon, or the lock before an answer is the pole under the dim (white behind a dark theme, black behind a light one), the worst case, deterministic. `BackdropScrim` never waits for the daemon (lock-on-start budget).
- No setting turns any of it off.

### Bar colours
`qml/config/BarColors.qml` holds what the bar draws in, beside `Style` and never read by it (`Style` builds on the lock screen and in the greeter, D-44; `StyleLayer.test_style_imports` catches a reference). The bar keeps today's raw theme colours (D-24):
- `env` is one object per theme (`foreground`, `background`, `resolve`, all `Style.resolve`), which `BarsConfig.enrichEnv` hands `BarEnrich`; a theme switch re-enriches every bar once. `resolve(name)` is the bar's name lookup (`WidgetLook`, `BarsConfig.workspaceColors`).
- `widgetColors(barConfig, accent, foreground, flags)` is `BarWidgetStyle.widgetColors` memoised: the last 32 enriched `barConfig` objects (an array searched by identity: a bar's object is replaced on any theme, look or geometry change, kept while equal), each holding a plain dictionary keyed on the exact text of the accent, foreground and every flag (`spot` unrounded); a hit returns the same object; a bar's dictionary past 1024 entries starts over. It reads no QML property, so a binding calling it keeps its dependencies on a hit; it copies its colour arguments to plain values first (a `color` property handed to JS can be a reference a stored result would follow).
- `pulseLadder(colors, muted)` is the 17 steps of a pulse (`BarWidgetStyle.pulseLadder`), memoised per pair (the last 64, an array searched by identity).
- A bounded self-check (256 hits of `widgetColors`, 64 of `pulseLadder`, again after each theme switch) compares a hit with a direct call and warns `BarColors: memo MISMATCH`. Under `--debug` every 4096th call logs `BarColors: widget colours memo <hits>/<calls> hits`.
- The bar's chrome (its fill, inner stroke, pills and islands) and everything joined to it read the edge family's `Style.surfacePage` / `Style.frameStroke`, bit-equal to the theme's background and foreground (D-64).

### Shadows
`Style.shadowBaseColor(look)` is a shadow's colour (`look.shadowColor`; Automatic the theme's raw accent, not the nudged `Style.accent`); `Style.shadowColor(look)` is what it is drawn in: capped at `Appearance.shadowAlphaMax` while surfaces blur and premultiplied, memoised per look. It reads `_roles` and the cap before its lookup, so a binding that hits still depends on both, and empties its cache in place when the roles changed.

### The lint
`scripts/check_style.py` fails on every hit (rules R1–R20, listed in its docstring); a line is waived with `// style-exempt: <reason>`, a file with an entry in `scripts/style-exceptions.json` (rules and reason; an entry no longer needed fails). It then runs the role check: a public member of `Style.qml` (a `property` or `function` not starting with `_`) that no `.qml` under `qml/` outside `Style`, `StyleInk` and `StyleTextRole` reads as `Style.<member>` fails as `unused role`. The pieces count as readers (`Surface`, `StateLayer`, `FocusRing`, `Skeleton`, `StyledScrollIndicator` and `BarColors` read the `fill*`, `ink*`, `state*` and `focus*` roles), and a role returned by `toneColor`, `textRole`, `iconSize` or `inkOf` counts as read when that function is read (`StyledText.tone: "success"` reaches `successText` through `toneColor`). `--roles` runs only the role check; `--files <paths>` prints the hits of those files.

### Adding a role
A formula in `StyleTokens.derive` (its constants at the top, each with a comment), a row in `tst_StyleTokens` (a pair, if the role is drawn on a fill), a property in `Style`, a reader in the same change (the role check fails a role nothing reads), and a line here. Regenerate `tests/fixtures/style/expected.json` if the role is in it. The generated `docs/dev/generated/api/Style.md` lists the members.
