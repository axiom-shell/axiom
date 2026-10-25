# Dock

> **Files:** `services/ui/DockManager.qml`, `config/DockConfig.qml`, `shell/Dock.qml`, `components/surfaces/dock/DockWindow.qml`, `components/surfaces/dock/DockMenu.qml`, `components/methods/DockLayout.qml`, `components/views/Settings/DockListCard.qml`
> **Config:** `Dock.*` (reader `DockConfig`); entries are `definitions/DockEntry`; `Apps.pinned` (reader `Apps`)
> **Related:** [Held off an edge](../popouts/held-off-edge.md), [Edge attach](../popouts/edge-attach.md), [Popout registry](../popouts/registry.md), [Layering and corners](../bar/layering-and-corners.md), [OSD](osd.md)

App docks on screen edges: pinned and running apps, magnification, hover and intellihide, placement against bars and the border, and the settings preview.

### Config
- The `Dock` section, read by `DockConfig`.
- `docks` is `[DockEntry]`, each with its own `enabled`; the default dock starts off (the section-wide `enabled` went in config v69).
- Docks are edited on `views/Settings/DockListCard`, the section's `x-card`, in its own `Dock` settings category.
- **Pinned apps** are the shared `Apps.pinned` (personal), which every dock shows, unless a dock's `pinnedOwn` is on: then its own `pinned` (`DockConfig.pinnedOf`). The card's switch picks which; turning it on starts the dock's own list as a copy of the shared one.
  - So a shared setup's docks (`pinnedOwn` is look, `pinned` personal) show the importer's apps, never the author's.
  - Config v71 moved the first dock's `pinned` to `Apps.pinned`; another dock with a different list kept it as its own.

### Building (shell/Dock)
- `shell/Dock` builds one `surfaces/dock/DockWindow` per enabled dock, per screen it shows on.
- The screens come from the dock's `monitors`, the same way as an OSD's (`DockConfig.screensOf`, filtered by `ShellManager.showsOn`).
- On "focused" the dock is rebuilt on whichever monitor focus moves to.

### Items (DockManager + methods/DockLayout)
- `itemsFor(dock, screen)` groups `CompositorManager.windows` by app.
  - The app key (`appKey`) is `DesktopEntries.heuristicLookup(appId)`, else the window's app id.
- `methods/DockLayout` is pure:
  - **`buildItems`:** pinned items first, then running ones when `showRunning` is on.
  - **`inScope`:** `windowScope` is `all` | `monitor` | `workspace`.
  - **`clickTarget`:** focus the most recent window; cycle through them when one is already focused.
  - **`magnifiedSizes`.**
  - **`covered`.**
- Delegates are keyed by the joined item keys.
- **Pinning from the dock** saves at once through `SettingsManager.commitValues`, to the list the dock shows (`DockManager._editPinned`):
  - right-click `DockMenu`;
  - dragging icons;
  - dragging an icon off the dock unpins it.

### The window
- `DockWindow` is a Top-layer `axiom-dock` strip, as deep as the magnified icons, masked to the box.
- **Layer order:** its layer rule arranges it after the border and every bar ([layer stacking](../generated/layers.md)).
  - It sits inside them, and never shortens the bars on other edges.
  - It is blurred.
- **Fullscreen:** a fullscreen window covers it, and its hover trigger is off then.
- **Put away** (`away`):
  - while the overlay is open on its screen, unless the dock reserves its strip;
  - while any popout covers it. Its `PopoutClaim`, a resident, has yielded (see [Popout registry](../popouts/registry.md)).
  - A reserving dock keeps its zone while put away.

### Placement
**Held** (`detached`, the default):
- A plain box, `gap` away from the frame lines on its edge and at its ends.
- Uses `boxOffset` and `startInset` / `endInset`.
- See [Held off an edge](../popouts/held-off-edge.md).

**Attached:** it meets its edge exactly as an `EdgePopout` does (`EdgeAttach`, see [Edge attach](../popouts/edge-attach.md)). That means one of:
- an `AttachedSurface` growing out of the border's or a solid bar's stroke (`edgeMargin` from `attachAt`);
- straight off a bare edge;
- joining a perpendicular stroke at an end;
- standing on, or merged around, a pill bar's pills, or between them over the bar where it fits (`between`);
- out of a floating bar's island, stretching the island while it shows;
- a detached box past a transparent bar.

Along the edge:
- its window reaches onto the perpendicular strokes (`strokeInset`);
- the icons sit where they want (`place.contentStart`), and the surface grows around them.

### Visibility
- **`always`:** `reserveSpace` sets its zone.
- **`hover`:** an `EdgeTrigger`.
- **`intellihide`:**
  - Hover, plus shown while no window covers it (`obscured`).
  - What counts as covering: a window on the output's active workspace, or on its open special workspace (the output's `specialWorkspaceId`; Hyprland's monitors are refreshed on `activespecial`).
  - Where windows are: their geometry with `supports.windowGeometry`, else their `cover` with `supports.windowCover` (niri's tiled windows: their column, or the whole output while the strip is wider than it); with neither, nothing covers the dock.
  - Coverage is computed from the output's `reserved` ([contract](../compositor/contract.md#shapes)).

### Zones and what reaches past it
- A dock reports what it reserves (`setZone` / `zoneOn`, per screen edge).
- Anything that the dock would otherwise push in reaches past it instead:
  - **`EdgePopout`s:** the OSD and floating edge menus, on the dock's own edge and at both ends.
  - **The border's corner pieces** (`RoundedBorders.cornerMargin`).
- **Layer orders that put them over the dock:**
  - The `axiom-edge-popout` layer rule ([layer stacking](../generated/layers.md)) draws floating edge menus over the dock, and over the overlay and the OSD.
  - The OSD's `axiom-osd` (`overNamespace`) layer rule draws the OSD over the dock and over the overlay.
- **Retiling:** Hyprland sends no event when windows retile around a changed zone. So `refreshSoon()` re-reads monitors and windows after layer and zone changes. Layer events are only listened to while a dock is built.

### Entry points
- IPC `dock`: `open` / `close` / `toggle <id>`.
  - An empty id means every dock.
  - There is no `show`, because qs's CLI takes that word.
- Bind action `dock`.

### Settings preview
- The settings card's Show button is a preview: `DockManager.preview(entry)`, with the entry as edited, saved or not.
- **Why a second window:** the dock is put away under the overlay that the card sits in. So `shell/Dock` builds a second `DockWindow` with `preview: true`:
  - on the screen the dock would show on (`previewScreen`, `ShellManager.targetFor`);
  - an Overlay-layer `axiom-dock-preview`, whose layer rule orders it after the overlay's panel;
  - with no trigger, zone, input or IPC;
  - reaching back past the docks' zones on its edge, to where a dock sits.
- It slides in, holds for 2 s and slides out.
- Meanwhile the dock's own copy there hides its content (`previewing`) and keeps its zone.
- **Exception:** an always-shown dock that reserves its strip is visible beside the overlay, so it isn't slid out. The preview is dropped at once and the dock shows again.
