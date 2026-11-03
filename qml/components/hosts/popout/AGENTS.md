# Popout hosts (`components/hosts/popout/`)

The shared pieces every popout is built from: bar popouts, edge popouts (OSDs, floating edge menus, launcher, dock), submenus. Docs: `docs/dev/popouts/` (start at `surface-context.md`; `registry.md` for collisions).

- **Geometry has one source.** What each end meets, where the box goes, whether it's detached, its shadow and where strokes open come from `methods/SurfaceContext` (`frame`/`layout`) and `methods/EdgeAttach`, gathered by `EdgePlacement` and drawn by `EdgeSurface` (`SubmenuHost` for submenus). Never add a rule in a host: a new case is a `SurfaceContext` rule plus a `tst_SurfaceContext` row.
- A new host keeps only its window and content.
- **Every popout holds a `PopoutClaim`** in `PopoutManager` with its footprint; never check other popouts yourself. An open popout never moves.
- Shadows of visible surfaces go through `OutsideShadow` (explicit padding), never a `MultiEffect` on the item's own layer.
- Layer order comes from `LayerStack.layers` (`docs/dev/generated/layers.md`; see `components/bar/AGENTS.md`). Bars and the border must never draw over fullscreen; never map a Top window in response to fullscreen (`docs/dev/testing.md`).
- Verify with `tst_SurfaceContext` rows and one targeted screenshot.
