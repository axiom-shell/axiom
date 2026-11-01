# feature:brightness
reviewed: f8e13e3 2026-11-01  (full)

A small, sound system: the Go side is tight and tested and the per-monitor coalescing holds. Open: an own set that opens the OSD refreshes the monitor beside its write (DDC: two ddcutil runs on one bus), and idle dimming is lost across a reload.

## Open findings
- Major: [An own brightness set opens the OSD, which refreshes the monitor beside the write](../../docs/dev/issues.md#an-own-brightness-set-opens-the-osd-which-refreshes-the-monitor-beside-the-write)
- Major: [Idle dimming is forgotten across a shell reload](../../docs/dev/issues.md#idle-dimming-is-forgotten-across-a-shell-reload)
- Cleanup: [Two members of the brightness system nothing needs](../../docs/dev/issues.md#two-members-of-the-brightness-system-nothing-needs)
- Cleanup: [The brightness icon thresholds are written three times](../../docs/dev/issues.md#the-brightness-icon-thresholds-are-written-three-times)

### brightness.md leaves out dimBy and the module's refresh
- **Where:** `docs/dev/features/brightness.md`
- **What:** The IPC list omits `dimBy` (idle's "by" mode); "When it reads" omits the Brightness module's refresh when built (`Brightness.qml:45`).
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the feature:brightness system

## Contract
Holds: backlight on eDP/LVDS/DSI (firmware > platform > raw), DDC by DRM connector (VCP 0x10); daemon detect/get/set, ddcutil 10 s cap, logind dialled per backlight set; detection at startup and 2 s after screens change, never polled; writes shown at once, coalesced per monitor; backlight never 0; brightnessChanged only for non-silent own sets; namesKey notifies only on monitors coming/going; module monitor "*"/""/name, silent sliders, shared slider greyed while desynced; OSD allMonitors sets all and shows the mean; IPC up/down/set on the focused output; dim/dimBy/undim reached from the daemon's idle actions.

## Coverage
Read deeply: services/system/BrightnessManager.qml, backend/internal/brightness/brightness.go, backend/internal/daemon/brightness.go, components/content/Brightness/Brightness.qml, components/surfaces/osd/OSDBar.qml, components/surfaces/osd/OSDTriggers.qml · Outlined: PopoutWrapperBase.qml (show path), shell/OSD.qml, daemon/idle.go, rpc/rpc.go; brightness_test.go run, not read · Skipped: none.

## History
- 2026-11-01 full: 5 findings (2 Major, 2 Cleanup, 1 Minor); recorded
