# feature:desktop
reviewed: f03a923 2026-11-01  (full)

A small, sound system; one regression: a turned-off primary layout blanks the primary monitor instead of falling back to the all-monitors layout. A dead editor member, a forwarding pair and three stale texts remain.

## Open findings
- Major: [A turned-off primary desktop layout blanks the primary monitor instead of falling back to all monitors](../../docs/dev/issues.md#a-turned-off-primary-desktop-layout-blanks-the-primary-monitor-instead-of-falling-back-to-all-monitors)
- Cleanup: [ScreenLayoutEditor.savedLayout is dead, and DesktopTarget forwards the editor's room](../../docs/dev/issues.md#screenlayouteditorsavedlayout-is-dead-and-desktoptarget-forwards-the-editors-room)

Unrecorded (Minor):
- **desktop.md describes the old Desktop section:** `docs/dev/features/desktop.md:4,10,21` name `Desktop.all/primary/monitors[]` and `monitor`; the schema has `Desktop.items[]` with a `screen` ScreenTarget and `grid.columns/rows`.
- **The desktop's insets are described as Hyprland's on every compositor:** desktop.md:42, `DesktopManager.qml:177`, `DesktopWindow.qml:13`; say "the compositor's".
- **The Layouts editor tells users desktop modules don't take typing:** `DesktopTarget.qml:23` "They take clicks but not typing", false for `x-keyboard` modules.

## Contract
Holds: per-screen window once `surfacesReady`; Bottom layer `axiom-desktop`, `no_anim`; keyboard OnDemand only with a shown `x-keyboard` module; input mask = module rects; no backdrop, frost only with `moduleBorders`; insets max(axiom reserve, compositor reserved) + `gapsOut`; host kind desktop, bare padding kept, ClockCalendar read-only; check_structure's desktop `x-hosts`/`x-keyboard` rules; editor draft, preview section, picker order, create/remove/enable, fit line on `screenFor`. Fails: primary's enabled-only fall-through; the doc's Config/Layouts lines.

## Coverage
Read deeply: DesktopManager, DesktopConfig, shell/Desktop, DesktopWindow, DesktopTarget, ScreenLayoutView, ScreenLayoutEditor, the Desktop/DesktopLayout/Layout/ScreenGrid schema · Outlined: ScreenLayoutTarget, DockManager.reservedOf, OverlayConfig.moduleInfo, check_structure's desktop rules, backends' reserved/gapsOut · Skipped: ModuleGrid, GridEditor, ConfigDraft (other systems).

## History
- 2026-11-01 full: 5 findings (1 Major, 1 Cleanup, 3 Minor); recorded
