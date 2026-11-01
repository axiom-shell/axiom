# feature:desktop
reviewed: f03a923 2026-11-01  (full)

A small, sound system; one regression: a turned-off primary layout blanks the primary monitor instead of falling back to the all-monitors layout. A dead editor member, a forwarding pair and three stale texts remain.

## Open findings
- Major: [A turned-off primary desktop layout blanks the primary monitor instead of falling back to all monitors](../../docs/dev/issues.md#a-turned-off-primary-desktop-layout-blanks-the-primary-monitor-instead-of-falling-back-to-all-monitors)
- Cleanup: [ScreenLayoutEditor.savedLayout is dead, and DesktopTarget forwards the editor's room](../../docs/dev/issues.md#screenlayouteditorsavedlayout-is-dead-and-desktoptarget-forwards-the-editors-room)

### desktop.md describes the old Desktop section
- **Where:** `docs/dev/features/desktop.md`
- **What:** Its Config line, field list and "Which layout a screen shows" name `Desktop.all`, `Desktop.primary`, `Desktop.monitors[]` and a `monitor` field; the schema has `Desktop.items[]`, each with a `screen` ScreenTarget and `grid.columns`/`rows`.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the feature:desktop system

### The desktop's insets are described as Hyprland's on every compositor
- **Where:** `docs/dev/features/desktop.md`, `services/ui/DesktopManager.qml:177`, `components/surfaces/desktop/DesktopWindow.qml:13`
- **What:** The doc and both comments call the reserved space and gaps Hyprland's; they are the compositor's on every backend. Fix: say "the compositor's".
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the feature:desktop system

### The Layouts editor tells users desktop modules don't take typing
- **Where:** `components/views/Layouts/DesktopTarget.qml:23` (`description`)
- **What:** "They take clicks but not typing" is false for `x-keyboard` modules, which make the desktop window take the keyboard on demand.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the feature:desktop system

## Contract
Holds: per-screen window once `surfacesReady`; Bottom layer `axiom-desktop`, `no_anim`; keyboard OnDemand only with a shown `x-keyboard` module; input mask = module rects; no backdrop, frost only with `moduleBorders`; insets max(axiom reserve, compositor reserved) + `gapsOut`; host kind desktop, bare padding kept, ClockCalendar read-only; check_structure's desktop `x-hosts`/`x-keyboard` rules; editor draft, preview section, picker order, create/remove/enable, fit line on `screenFor`. Fails: primary's enabled-only fall-through; the doc's Config/Layouts lines.

## Coverage
Read deeply: DesktopManager, DesktopConfig, shell/Desktop, DesktopWindow, DesktopTarget, ScreenLayoutView, ScreenLayoutEditor, the Desktop/DesktopLayout/Layout/ScreenGrid schema · Outlined: ScreenLayoutTarget, DockManager.reservedOf, OverlayConfig.moduleInfo, check_structure's desktop rules, backends' reserved/gapsOut · Skipped: ModuleGrid, GridEditor, ConfigDraft (other systems).

## History
- 2026-11-01 full: 5 findings (1 Major, 1 Cleanup, 3 Minor); recorded
