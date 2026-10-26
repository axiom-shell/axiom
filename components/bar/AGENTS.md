# Bars (`components/bar/`)

The bar window (`BarPanel`), its container (`BarContainer`: sections, pills, islands, shadows, openings) and its pieces; widget types are in `widgets/` (its own `AGENTS.md`). Docs: `docs/dev/bar/` (start at `composition.md`; corners in `layering-and-corners.md` and `bar-ends-pills.md`).

- **Layer ordering** (bars, border, popouts, dock, edge menus, backdrops, screenshot) is `LayerStack.layers`, made into Hyprland rules by `HyprLua.layerRulesLua` (which `HyprlandManager` evaluates; the daemon's `render.LayerRulesLua` writes them into its files), mapped in that order elsewhere (`docs/dev/compositor/layer-arrangement.md`), and listed with the reason for each in `docs/dev/generated/layers.md`. Change the table (and `tst_LayerStack`'s order test), never a number in a doc. Hyprland reads `order` only as a surface maps, so a window whose namespace changes is remade (`shell/Bar` keys on `Bar.layerNamespace`).
- **Which bar owns a corner, and what each end meets, is `methods/BarEnds` alone** (`ends` on each `ScreenEdgeManager.bars` entry). A host never works it out again from `vertical`, `location` or the background: read the end's `kind`, or add a case to `BarEnds` with a `tst_BarEnds` row. (`CornerMerge` once assumed the side bar always yields; it broke when the tiebreak changed.)
- Bars and the border must never draw over a fullscreen window, and nothing maps a Top window in response to fullscreen (`docs/dev/testing.md`).
- Bar geometry animates what's drawn, never what's measured (`docs/dev/bar/composition.md`).
- Before changing how surfaces sit on an edge, read `docs/dev/bar/layering-and-corners.md` and `docs/dev/popouts/surface-context.md`.
