# Clocks and time zones

> **Files:** `services/TimeZoneManager.qml`, `components/methods/TimeZones.qml`, `backend/internal/tz/`, `backend/internal/daemon/tools.go`, `backend/internal/cli/tz.go`, `components/content/Clock/Clock.qml`, `components/content/WorldClocks/WorldClocks.qml`, `components/bar/widgets/Time/Time.qml`
> **Config:** module/widget `timezone` properties (no section of its own)
> **Related:** [Services pattern](../core/services-pattern.md), [Schema annotations](../core/schema-annotations.md), [Desktop](desktop.md), [Utility modules](../overlay/utility-modules.md)

How clocks show another time zone (the JS engine has no Intl), plus the Clock module's styles.

### Why a service is needed
- The QML JS engine has no `Intl`, and ignores `toLocaleString`'s `timeZone`.
- So other zones' UTC offsets come from `TimeZoneManager`.

### TimeZoneManager
- Used by clocks set to another zone: a Clock module's or a Time widget's `timezone`.
- **`acquire(owner, zone)` / `release(owner)`:**
  - a `ConsumerRegistry`;
  - `zone` may be a list, as WorldClocks asks for.
- **Reading a zone:**
  - The zones asked for are read with one `tz.offsets` call to axiom (`backend/internal/tz`): each zone's file in the zoneinfo directory (`$TZDIR`, else `/usr/share/zoneinfo`), its offset now in minutes east of UTC. A zone name that isn't a plain relative path is never read.
  - A read cut off by axiom's connection dropping is retried after the next hello (`greeted`), with the zone list, rather than at the next half hour.
  - One read serves all of that zone's clocks.
  - It reads again past every half hour UTC, when daylight saving can change.
  - Nothing is read when no clock asks.
  - Without axiom's daemon (the greeter) the same reads run through `axiom tz offsets` / `axiom tz zones --json` (`Paths.axiomBin`, `backend/internal/cli/tz.go`), whose answers have the calls' shape. A shell run by hand with no `axiom` on its PATH reads nothing, and clocks show the system's time.
- **`offsetOf(zone)`** is null, meaning the system's time:
  - until the zone has been read;
  - for a zone not in `zones`. `zones` is the system's list (`tz.zones`: `tzdata.zi`'s zones and links, else the zoneinfo files found), fetched until it has been read (again after a reconnect); it is also the `timezones` option list.
- **Display:** a clock shows `methods/TimeZones.shift(date, offset)`, whose local fields read as that zone's wall clock.

### Clock module (`content/Clock`)
- Works on every host (overlay, desktop, lock screen, greeter, edge menus).
- **`style`:**
  - **`digital`:** one line, with the seconds and AM/PM small beside it.
  - **`stacked`:** hours over minutes, the minutes in the accent color.
  - **`analog`:** marks and hands as rotated Items. The hands turn clockwise through 0 with a `RotationAnimation`.
- All styles are sized to the slot from the font's digit height (`capRatio`), so the lines sit tight on their baselines.
- The date and a `label` go under it.
- `timezone` is handled through TimeZoneManager.
- The bar `Time` widget takes a `timezone` the same way.

### Picking a zone
- Long option lists use `x-control: "search"`; the time zones are one.
- In `SchemaField` that is a typed `StyledComboEntry`, which takes only listed values.
- See [Schema annotations](../core/schema-annotations.md).
