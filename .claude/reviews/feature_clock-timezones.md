# feature:clock-timezones
reviewed: e98fea2 2026-11-01  (full)

The zone service, its Go side and the three clocks match the doc; the offsets path holds on reconnects and rapid changes. Open: a 12-hour Clock (and the Japanese vertical Time widget) shows 24-hour hours, and 16 lines of shrinks.

## Open findings
- Blocker: [A 12-hour Clock shows the hour in 24-hour time](../../docs/dev/issues.md#a-12-hour-clock-shows-the-hour-in-24-hour-time)
- Cleanup: [Small shrinks in TimeZoneManager and WorldClocks](../../docs/dev/issues.md#small-shrinks-in-timezonemanager-and-worldclocks)
- Minor: clock-timezones.md › TimeZoneManager names only Clock and Time as users; WorldClocks is a third, and the doc has no section on it although its header lists the file.
- Known, not re-filed: [A custom clock format without spaces spills past a vertical bar](../../docs/dev/issues.md#a-custom-clock-format-without-spaces-spills-past-a-vertical-bar); [The Clock's date and label keep their room while the time shrinks to nothing](../../docs/dev/issues.md#the-clocks-date-and-label-keep-their-room-while-the-time-shrinks-to-nothing); [Parts shown in one mode are built hidden in every mode, in ten modules and parts](../../docs/dev/issues.md#parts-shown-in-one-mode-are-built-hidden-in-every-mode-in-ten-modules-and-parts) (WorldClocks); [Small shrinks in the core services](../../docs/dev/issues.md#small-shrinks-in-the-core-services) (`artResult`).

## Contract
Holds: no Intl, offsets from TimeZoneManager; `acquire(owner, zone|list)` through a ConsumerRegistry, `""`/`[]` releases; one `tz.offsets` call for all zones wanted, `$TZDIR` else `/usr/share/zoneinfo`, only plain relative names read; repeatable over a reconnect; re-read past each half hour UTC (+2 s); nothing read with no clock asking; greeter answers (`lookupMethods`); `offsetOf` null until read or for a zone not in `zones`; `zones` from tzdata.zi's zones and links, else the files found, also the `timezones` option list; display through `TimeZones.shift` (tested); Clock's three styles sized from `capRatio`, date and label under; analog hands clockwise through 0; Time takes `timezone` the same way; zone fields are `x-control: search`. Kept on purpose: the `_reading`/`_again` hold (the repo's idiom), the three clocks' acquire lines (a shared piece has no home that may read services).

## Coverage
Read deeply: TimeZoneManager, TimeZones, tz.go, tools.go `lookupMethods`, Clock, Time, WorldClocks, the three schema.yaml files. Outlined: BackendManager (`call`, `_failQueued`, `_dropped`), I18n (`formatDate`, `meridiem`, `dateFormat`), SettingsManager's `timezones` options. Skipped: the rest of tools.go (other systems' tools).

## History
- 2026-11-01 full: 3 findings (1 Blocker, 1 Cleanup, 1 Minor); recorded
