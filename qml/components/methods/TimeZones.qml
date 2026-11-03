pragma Singleton
import QtQuick

// Pure helpers for clocks in another time zone. The JS engine has no Intl
// and ignores toLocaleString's `timeZone`, so TimeZoneManager reads each
// zone's UTC offset (axiom's tz.offsets) and a clock shifts its Date by it: the
// shifted Date's local fields read as that zone's wall clock, ready for
// I18n.formatDate. No file access, processes or services.
QtObject {
  id: root

  // `date` as the wall clock of a zone `offset` minutes east of UTC; `date`
  // itself without an offset (null: the system's zone). Built from the
  // zone's fields rather than by adding the local offset, which differs on
  // the far side of a local daylight saving change (only a wall time the
  // system's zone skips can't be had: it reads an hour on)
  function shift(date, offset) {
    if (offset === null || offset === undefined)
      return date;
    const zone = new Date(date.getTime() + offset * 60000);
    return new Date(zone.getUTCFullYear(), zone.getUTCMonth(), zone.getUTCDate(), zone.getUTCHours(), zone.getUTCMinutes(), zone.getUTCSeconds(), zone.getUTCMilliseconds());
  }

  // The ms from `date` until a moment past the next half hour (UTC): when
  // offsets change (daylight saving starts and ends on the hour, or the
  // half hour in a few zones), so they're read again then
  function msToNextCheck(date) {
    const halfHour = 30 * 60000;
    const now = date.getTime();
    return Math.ceil((now + 1) / halfHour) * halfHour - now + 2000;
  }
}
