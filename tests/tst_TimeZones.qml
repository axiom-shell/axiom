import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "TimeZones"

  // Whatever zone the test runs in, the shifted Date's local fields are
  // the zone's wall clock
  function test_shift() {
    const date = new Date(Date.UTC(2026, 0, 31, 20, 15, 30));
    const tokyo = TimeZones.shift(date, 540);
    compare(tokyo.getHours(), 5);
    compare(tokyo.getMinutes(), 15);
    compare(tokyo.getSeconds(), 30);
    compare(tokyo.getDate(), 1, "past midnight there: the next day");
    compare(tokyo.getMonth(), 1);
    const newYork = TimeZones.shift(date, -300);
    compare(newYork.getHours(), 15);
    compare(newYork.getDate(), 31);
    const india = TimeZones.shift(date, 330);
    compare(india.getHours(), 1);
    compare(india.getMinutes(), 45);
  }

  // Every hour of a year, so whatever zone the test runs in, its daylight
  // saving changes are crossed: the fields are the zone's own (UTC's,
  // moved by the offset), apart from a wall time the local zone skips
  function test_shift_across_local_daylight_saving() {
    const start = Date.UTC(2026, 0, 1);
    for (let hour = 0; hour < 366 * 24; hour++) {
      const date = new Date(start + hour * 3600000);
      const want = new Date(date.getTime() + 540 * 60000);
      const got = TimeZones.shift(date, 540);
      const skipped = got.getHours() !== want.getUTCHours() && new Date(got.getFullYear(), got.getMonth(), got.getDate(), want.getUTCHours()).getHours() !== want.getUTCHours();
      if (skipped)
        continue;
      compare(got.getHours(), want.getUTCHours(), date.toISOString());
      compare(got.getDate(), want.getUTCDate(), date.toISOString());
    }
  }

  function test_shift_without_an_offset() {
    const date = new Date(2026, 5, 1, 12, 0);
    compare(TimeZones.shift(date, null), date);
    compare(TimeZones.shift(date, undefined), date);
  }

  function test_msToNextCheck() {
    compare(TimeZones.msToNextCheck(new Date(Date.UTC(2026, 0, 1, 10, 0, 0))), 30 * 60000 + 2000, "on the half hour: the next one");
    compare(TimeZones.msToNextCheck(new Date(Date.UTC(2026, 0, 1, 10, 29, 0))), 60000 + 2000);
    compare(TimeZones.msToNextCheck(new Date(Date.UTC(2026, 0, 1, 10, 45, 0))), 15 * 60000 + 2000);
  }
}
