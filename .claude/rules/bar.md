---
paths:
  - "qml/components/bar/**"
---

# Bars (`qml/components/bar/`)

`BarPanel` (the window), `BarContainer` (sections, pills, islands, shadows, openings), the drawing kit `look/`, and widget types in `widgets/<Type>/<Type>.qml` + `<Type>/schema.yaml` (loaded by name, `Paths.widgetUrl`). Docs: `docs/dev/bar/` (start at `composition.md`; corners in `layering-and-corners.md`, `bar-ends-pills.md`; looks in `widget-style.md`). Recipes: `/bar-widget`, `/bar-popout`.

## The bar
- **Layer order** (bars, border, popouts, dock, menus, backdrops, screenshot) is `LayerStack.layers` alone, turned into compositor rules by the daemon. Change the table and `tst_LayerStack`'s order test, never a number in a doc. Hyprland reads `order` only when a surface maps, so a window whose namespace changes is remade (keyed on `BarsConfig.layerNamespace`).
- **Corners and ends are `methods/BarEnds`' alone** (`ends` on each `ScreenEdgeManager.bars` entry): read the end's `kind`; a new case is a `BarEnds` rule plus a `tst_BarEnds` row.
- **Widget styles are traits in `methods/BarLook`**: nothing else compares a `widgetStyle` string (`check_structure`). Code branches on the look's traits and resolved fields (`barConfig.look`); a schema asks `$bar.<trait>`. A new style is a trait record (`docs/dev/bar/widget-style.md` › Adding a widget style).
- Bars and the border never draw over a fullscreen window, and nothing maps a Top window in response to fullscreen.
- Geometry animates what's drawn, never what's measured.
- Before changing how surfaces sit on an edge, read `docs/dev/bar/layering-and-corners.md` and `docs/dev/popouts/surface-context.md`.

## Widgets
- Every widget's root is `BarWidget` (data only: `docs/recipes/bar-widget.md`; Volume and Microphone `AudioLevelWidget`). Copy `Weather` (polled data + popout) or `Updates` (a request, both buttons).
- The schema (expanded over `definitions/kinds/WidgetBase.yaml`) needs `label`, `icon` and a `group` from the root's `x-libraryGroups`. Every widget but Separator and Spacer has a `popout` part (`own`, or `menu` for one that only opens a menu).
- Settings are `properties.<key>`; bar-level values `barConfig.<key>` (some derived by `BarsConfig.enrichBarConfig`).
- **Sized by the bar**: cross size `barConfig.thickness`; padding, gap, font size and radius from `barConfig`, never `Widget.*` or fixed px, so it looks the same on a 16, 26 or 40 px bar.
- **A changing number never resizes the bar**: labels use equal-width digits, measured as zeros; a value whose digit count changes sets `minimumText` to its widest usual value (`"00%"`).
- Colors: color fields are `$ref: WidgetColor` with `x-autoColor` where the bar should pick one, shown only in looks they affect through `$bar.<trait>` conditions (`BarLook.contextTraits`), never a list of styles. A widget names fields (`accentField`, `iconField`, badge and mark `field`) and never resolves a colour; the guard rules T1-T8 and their exceptions (`scripts/bar-widget-exceptions.json`) are in `docs/dev/bar/widget-style.md` › The widget template.
- A popout opens through `PopoutAnchor { hitArea: root.hitArea; popoutName: "<Name>"; active: MenusConfig.opensOwnPopout(root.properties) && … }`; its content is `qml/components/content/<Name>/<Name>.qml`.
- Polled data: `readonly property var <x>Request` built from `properties` only; acquire on completion and on its change, release on destruction.
- A widget must never see a content type of the same name (`check_structure`).
