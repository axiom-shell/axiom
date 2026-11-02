# feature:dock
reviewed: 47db042 2026-11-01  (full)

The dock matches its doc and shares its placement with the edge popouts. Open: menu and drag state kept by icon index outlive the icons (a dock that stops hiding or showing names), a dock laid out ignoring another edge's reserving dock, and 7 lines of pass-through.

## Open findings
- Major: [The dock's menu and drag state outlive the icons they point at](../../docs/dev/issues.md#the-docks-menu-and-drag-state-outlive-the-icons-they-point-at)
- Major: [A dock beside another edge's reserving dock is laid out as if that dock weren't there](../../docs/dev/issues.md#a-dock-beside-another-edges-reserving-dock-is-laid-out-as-if-that-dock-werent-there)
- Cleanup: [The dock's trigger placement and window focus go the long way round](../../docs/dev/issues.md#the-docks-trigger-placement-and-window-focus-go-the-long-way-round)
- Minor: dock.md names keys that don't exist: `docks` (the key is `Dock.items`), the dock's `monitors` (the key is `screen`), its own `Dock` category (`Dock & OSD`); shell/Dock.qml's header says `monitors`, DockManager's header "written to Dock.docks".
- Known, not re-filed: [The dock's footprint assumes fillets at both ends](../../docs/dev/issues.md#the-docks-footprint-assumes-fillets-at-both-ends); [sway's named workspaces all share workspace id -1](../../docs/dev/issues.md#sways-named-workspaces-all-share-workspace-id--1) (`DockLayout.inScope`); [A second bar on an edge is invisible to the screen-edge answers, and New bar makes one](../../docs/dev/issues.md#a-second-bar-on-an-edge-is-invisible-to-the-screen-edge-answers-and-new-bar-makes-one); "Eleven StyledIconButtons undo its stretching to be FlatIconButtons" (DockListCard; fixed, row 20 core-ui-theming-06).

## Contract
Holds: default dock off; pinned from `Apps.pinned` unless `pinnedOwn`, the switch copying the shared list; one DockWindow per enabled dock per screen (`screensOf` + `showsOn`, focused follows focus); `itemsFor` by `appKey`; DockLayout's five helpers, tested; pinning saved at once to the shown list from the menu, drags and drag-off; Top-layer `axiom-dock` masked to the box and grown icons, trigger off under fullscreen; away under the overlay unless reserving and while its resident claim yields; held and attached placement through EdgePlacement on its own edge; always/hover/intellihide (geometry or cover, active and special workspace, reserved-based rect); zones per screen edge, moved on edge/id change, cleared on destruction; EdgePopouts and border corners reach past them; `refreshSoon` only with an enabled dock; IPC `dock` open/close/toggle (empty = all) and the bind action; the preview as documented. A carried icon stays under the pointer while magnification shrinks back (DragArea's delta is in the moving item's coordinates).

## Coverage
Read deeply: DockWindow, DockManager, DockItem, DockMenu, DockMenuRow, DockLayout, DockConfig, shell/Dock, DockListCard, the Dock and DockEntry schema. Outlined: EdgeTrigger, EdgePlacement (inner span), PopoutClaim and PopoutManager (claim/release), DragArea, EdgePopout's margins, SettingsManager.commitValues. Skipped: tests/tst_DockLayout.qml (test names only).

## History
- 2026-11-01 full: 4 findings (2 Major, 1 Cleanup, 1 Minor); recorded
