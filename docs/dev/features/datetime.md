# Date and time

> **Files:** `backend/internal/timedate/`, `backend/internal/daemon/machine.go`, `qml/services/system/DateTimeManager.qml`, `qml/components/views/Settings/DateTimeStatusCard.qml`, `qml/config/DateTimeConfig.qml`, `qml/config/I18n.qml`, `qml/components/methods/DateFormats.qml`
> **Config:** `DateTime.*` (reader `DateTimeConfig`); the machine's time zone, network time and clock are timedated's, not config
> **Related:** [Clocks and time zones](clock-timezones.md), [i18n](../core/i18n.md), [System info](system-info.md), [Polkit](polkit.md), [Testing](../testing.md) › Machine settings

Settings › System › Date & time: the machine's clock (its first card, `DateTimeStatusCard`) and how every time and date in the shell reads (the section's fields). Tests: `tst_DateFormats`, `backend/internal/timedate`'s Go tests.

### The machine's clock (`datetime.*`)
- `timedate.Clock` talks to systemd-timedated on the system bus: `datetime.get` reads `Timezone`, `LocalRTC`, `CanNTP`, `NTP` and `NTPSynchronized` (`available` false without timedated: no systemd, no bus); `datetime.setTimezone`, `setNtp` and `setTime` (ms since the epoch) answer the state after the change.
- The setters are the shell's only (`fromShell`) and go out with `FlagAllowInteractiveAuthorization`, so polkit asks the user through axiom's agent and waits up to two minutes for them. A refused or cancelled prompt is `refused`, shown under the card (`SystemInfoManager.errorText`). A zone is checked for an IANA name's shape before it's sent (never a path).
- `datetimePart.run` follows timedated's `PropertiesChanged` and pushes `datetime.state` to the shell's connections (not a hello topic), so a change made with `timedatectl` or another desktop shows at once; with no bus it tries again a minute later.
- The card: the time now (`SystemClock`) in the formats below, the zone (a typed search over `TimeZoneManager.zones`, axiom's `tz.zones`), Set the time automatically (`SetNTP`, off when no sync service is installed), and while that's off the date and time typed as `yyyy-MM-dd` and `HH:mm`. A hardware clock on local time is pointed out (a Windows dual boot).
- Whether the shell's own clocks (Qt's `Date`, through the C library's `localtime`) follow a new zone without a restart isn't tested here (try it on a real time zone change).

### How times and dates read (`DateTime.*`)
- **Region** (`DateTime.region`, `x-options: regions`): a Qt locale code whose formats apply in place of the language's (English text, German dates). Day and month names always follow the language (`I18n.locale`); the region (`I18n.regionLocale`, the language's locale when unset) gives the usual clock, the date order and the first day of the week.
- **Clock** (`hourFormat`): `auto` reads the region's short time pattern (12-hour when it has an AM/PM field), else `12` / `24`: `I18n.use24Hour`. A clock with its own choice passes it to `I18n.hours24(hourFormat)` / `clockFormat(hourFormat, seconds)` / `timeFormat(hourFormat)` (`default` follows this).
- **Dates** (`dateStyle`): `language` keeps the language's own named formats; `dmy`, `mdy`, `ymd` and `iso` replace the date ones (`longDate`, `mediumDate`, `shortDate`, `fullDate`, `dateTime`; `DateFormats.named`); `region` is the region's order (`DateFormats.orderOf` its short date pattern) once a region is set, the language's until then. `I18n.dateFormat` applies it, so every caller follows.
- **First day of the week** (`firstDayOfWeek`): `region` is the region's (Qt's 1 Monday … 7 Sunday, taken mod 7), else Monday, Sunday or Saturday: `I18n.firstDayOfWeek`, which the month grids read.
