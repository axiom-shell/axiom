---
paths:
  - "qml/components/hosts/popout/**"
---

# Popout hosts (`qml/components/hosts/popout/`)

The pieces every popout is built from: bar popouts, edge popouts (OSDs, floating menus, launcher, dock), submenus. Docs: `docs/dev/popouts/` (start at `surface-context.md`; `registry.md` for collisions).

- **Geometry has one source**: what each end meets, where the box goes, detachment, shadow and stroke openings come from `methods/SurfaceContext` and `methods/EdgeAttach`, gathered by `EdgePlacement`, drawn by `EdgeSurface` (`SubmenuHost` for submenus). While backed the backing window draws every stroke with its fill in `PaintOrder` and its copies cut the openings (`HoledCopy`); a host draws content only. A new case is a `SurfaceContext` rule plus a `tst_SurfaceContext` row, never a rule in a host. A host keeps only its window and content.
- **Every popout holds a `PopoutClaim`** in `PopoutManager` with its footprint; never check other popouts yourself.
- **An open popout never moves**, except an `EdgePopout` whose screen gains or loses a fullscreen window, or whose screen's auto-hiding bars go out of place or back (`_away`): it jumps, unanimated, to where it would open now, its window kept mapped (`docs/dev/popouts/held-off-edge.md`).
- Shadows go through `OutsideShadow` (explicit padding), never a `MultiEffect` on the item's own layer.
- Layer order is `LayerStack.layers`; nothing draws over fullscreen or maps a Top window in response to it.
- Verify with `tst_SurfaceContext` rows and one targeted screenshot, not a matrix of popouts.
- A host's box: the edge family's `Style.surfacePage` / `Style.frameStroke` / `Style.edgeFill`; never `fillPage`, `Qt.alpha` or an `Appearance` alpha (that's free-standing surfaces').
- Colours, text and icon sizes: `Style` roles and the style pieces (`docs/dev/core/style.md`); never `Theme.`, a `fontSizeBy`, an opacity dim or `font.bold`. `check_style.py` fails a file that has them.
