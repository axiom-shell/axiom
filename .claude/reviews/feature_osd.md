# feature:osd
reviewed: f03a923 2026-11-01  (full)

A small, mostly sound system. Open: the system volume bar opens the OSD on a default output switch, every OSD's opening reads brightness (ddcutil on DDC) even without a brightness bar, and the stream bar's hand-synced tracking (78 lines) plus a dead mute toggle and a re-derived volume icon (12 lines) can go.

## Open findings
- Major: [The system volume bar opens the OSD when the default output switches](../../docs/dev/issues.md#the-system-volume-bar-opens-the-osd-when-the-default-output-switches)
- Major: [Every OSD's opening reads the monitor's brightness, brightness bar or not](../../docs/dev/issues.md#every-osds-opening-reads-the-monitors-brightness-brightness-bar-or-not)
- Cleanup: [The OSD's stream bar tracks its streams by hand](../../docs/dev/issues.md#the-osds-stream-bar-tracks-its-streams-by-hand)
- Cleanup: [PipewireVolumeBar keeps a mute toggle nothing calls and its own volume icon](../../docs/dev/issues.md#pipewirevolumebar-keeps-a-mute-toggle-nothing-calls-and-its-own-volume-icon)

### osd.md names the config keys from before the ScreenTarget move
- **Where:** `docs/dev/features/osd.md`, `config/OSDConfig.qml:13` (comment)
- **What:** The doc lists the section key `osds` (schema: `items`), entry fields `monitors` / `monitor` (schema: `screen`), and `General.screensFor(monitors, monitor)` (code: `General.screensFor(entry._found.screen)`); OSDConfig's comment omits a bar's `allMonitors`.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the feature:osd system

## Contract
Holds: the reader (JSON-string rebuild guard, shownIds, osdById, labelOf, excludedApps over every OSD, scrollStep 0 when off); bar types, brightness left out without a controller, allMonitors mean; the three layouts; one EdgePopout per enabled OSD per screen keyed by id, held/gap, axiom-osd namespace, `osd:<id>:<screen>` claim of kind osd, keepLoaded, timeout as dismiss delay; opening on the target screen or all in "all" mode via ShellManager.showsOn; Show via ShellManager.showOsd; microphone and app bars skip device/stream switches; OSDListCard editor and audioApps suggestions.

## Coverage
Read deeply: shell/OSD.qml, config/OSDConfig.qml, components/surfaces/osd/*.qml, components/views/Settings/OSDListCard.qml, the OSD and OSDEntry schema YAML · Outlined: AudioManager.qml, BrightnessManager.refresh, brightness.go Get, ShellManager targeting, General.screensFor, StyledVolumeBar · Skipped: EdgePopout, EntryListCard (other systems' cores).

## History
- 2026-11-01 full: 5 findings (2 Major, 2 Cleanup, 1 Minor); recorded via --out
