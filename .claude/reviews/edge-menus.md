# edge-menus
reviewed: b519ddd 2026-10-31  (full)

A compact system whose sharing holds: one body and one sync for both hosts, placement through the popout system and `GridPlacement`, the editor on a `ConfigDraft` with previews. Open: the integrated host's exclusive zone isn't moved when the menu changes edge or screen and grows with its modules while open, and the hover strip's length and the editor's "fits its edge" are worked out from config where the running host or the placement helper already knows.

## Open findings
- Major: [An integrated menu's zone stays behind when it changes edge or screen](../../docs/dev/issues.md#an-integrated-menus-zone-stays-behind-when-it-changes-edge-or-screen)
- Major: [An integrated top or bottom menu's zone follows its growing modules](../../docs/dev/issues.md#an-integrated-top-or-bottom-menus-zone-follows-its-growing-modules)
- Major: [A whole-edge menu's hover strip covers only its modules' length while closed](../../docs/dev/issues.md#a-whole-edge-menus-hover-strip-covers-only-its-modules-length-while-closed)
- Major: [The layouts editor says a menu fits its edge when it scrolls](../../docs/dev/issues.md#the-layouts-editor-says-a-menu-fits-its-edge-when-it-scrolls)
- Major: [Previewing a submenu menu doesn't open it once a module above its row has grown](../../docs/dev/issues.md#previewing-a-submenu-menu-doesnt-open-it-once-a-module-above-its-row-has-grown)
- Cleanup: [IntegratedEdgeMenu's empty engage exists only for EdgeMenuSync's call](../../docs/dev/issues.md#integratededgemenus-empty-engage-exists-only-for-edgemenusyncs-call)
- Cleanup: [MenuSubmenu repeats EdgeMenuBody's module grid](../../docs/dev/issues.md#menusubmenu-repeats-edgemenubodys-module-grid)

Deletion pass: the two Cleanups (15 and 33 lines out) plus `EdgeMenusConfig.lengthOf` (7 lines, unused once the hover strip and fit check are fixed): 55 lines.

Minor (unrecorded):
- `docs/dev/edge-menus/overview.md` › An entry's fields uses old flat field names (`openOnHover`, `openDelay`, `triggerSize`, `triggerLength`, `closeOnLeave`, `closeDelay`, `closeOnOutsideClick`, `moduleScale`, `grid.fine`, `moduleBorders`); the schema has `open.*`, `trigger.*`, `close.*`, `layout.*`. editing-submenus.md › Draft says `ConfigDraft { path: ["EdgeMenus"] }`; it's `["EdgeMenus", "items"]`.
- `EdgeMenuManager`'s IPC `pin`/`unpin` skip `_exists`: a mistyped id is saved to the state file (dropped at the next start).
- `EdgeMenuManager.frameOf`'s fallback pads an integrated menu by `borderWidth + padding`, not its `pad` (frame inset and stroke): a disabled integrated menu draws slightly off in the editor.
- An id left in `openMenus` by a menu that's removed, disabled or has no host (a `submenu`-mode menu toggled by a bind) stays "open" until toggled; a later menu given that id opens at once.

Known before this review: [An edge menu can be bigger than its screen](../../docs/dev/issues.md#an-edge-menu-can-be-bigger-than-its-screen), [High module padding clips edge menu modules](../../docs/dev/issues.md#high-module-padding-clips-edge-menu-modules), [Opening a hover-closing edge menu by IPC closes it at once](../../docs/dev/issues.md#opening-a-hover-closing-edge-menu-by-ipc-closes-it-at-once), and the popouts audit's EdgePopout entries.

## Contract
Holds: one `EdgeMenu` per enabled entry, keyed by id, hosts lazily loaded by mode, the last live entry kept; the body's card unit (`cardUnitOn` × `moduleScale`, fine grid), gap and zoom; `fillsEdge` stretching and the cap; the pin and Escape; the lattice (`menuAlong`, `offset`, `gridOffset`, `startPad`/`endPad`); frames reported and cleared on rename or destruction, `frameOf`'s fallback; EdgeMenuSync's following, close reporting, held/revealing/`autoDismiss`, warp, grab partners, strips centred from config; the floating host's `detached`/`gap`, reserved space, `alongOrigin`, `popoutAtWidget` taken as it opens, claim kinds; the integrated host's layer, `LayerSlot` hold, frame inset, inner stroke, zone report; `EdgeMenuManager`'s persistent open/pinned state, pins saved and reopened at start, `isHeld`, `covered`, `toggle` bringing a covered menu forward, the IPC target; the editor's draft and preview, field groups, `MenuOpening` (preview following selection and renames, references, opener buttons), `_keepPlace`, nudging and centring, `setGridOffset` within half a cell, `submenuParentOf`/`previewParent`, `references` and the self-opening problem; Submenu rows dimmed without a `SubPopout`; `popoutMenuOf` never a submenu menu. Broken: the integrated zone "set once".

## Coverage
Read deeply: shell/EdgeMenus, EdgeMenu, EdgeMenuSync, EdgeMenuBody, FloatingEdgeMenu, IntegratedEdgeMenu, EdgeMenuManager, EdgeMenusConfig, EdgeMenuEditor, MenuTarget, MenuOpening, OpenerButtons, Submenu, MenuSubmenu (about 2300 lines). Outlined: EdgePopout, PopoutWrapperBase (popouts' core, audited 2026-10-30), ScreenEdgeManager's zones, GridPlacement's menu helpers and `grown`, ModuleGrid's growth, OverlaySlot, PopoutAnchor's menu path, LayerSlot, QuickActions' pin, the EdgeMenu schema. Skipped: GridEditor (the overlay audit's, 2026-10-31).

## History
- 2026-10-31 full: 7 findings (5 Major, 2 Cleanup) and 4 Minor; recorded
