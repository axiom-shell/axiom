import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "DateFormats"

  function test_use24Hour() {
    compare(DateFormats.use24Hour("24", "h:mm AP"), true, "set beats the region");
    compare(DateFormats.use24Hour("12", "HH:mm"), false);
    compare(DateFormats.use24Hour("auto", "h:mm AP"), false, "en_US");
    compare(DateFormats.use24Hour("auto", "h:mm ap"), false);
    compare(DateFormats.use24Hour("auto", "HH:mm"), true, "de_DE");
    compare(DateFormats.use24Hour("auto", "H:mm"), true, "ja_JP");
    compare(DateFormats.use24Hour("auto", undefined), true);
  }

  function test_orderOf() {
    compare(DateFormats.orderOf("dd.MM.yy"), "dmy");
    compare(DateFormats.orderOf("d/M/yy"), "dmy");
    compare(DateFormats.orderOf("M/d/yy"), "mdy");
    compare(DateFormats.orderOf("yyyy/MM/dd"), "ymd");
    compare(DateFormats.orderOf("y-MM-dd"), "ymd");
    compare(DateFormats.orderOf(""), "dmy");
  }

  function test_styleOf() {
    compare(DateFormats.styleOf("language", true, "M/d/yy"), null);
    compare(DateFormats.styleOf("region", false, "dd.MM.yy"), null, "no region: the language's");
    compare(DateFormats.styleOf("region", true, "dd.MM.yy"), "dmy");
    compare(DateFormats.styleOf("iso", false, ""), "iso");
    compare(DateFormats.styleOf("mdy", false, ""), "mdy");
    compare(DateFormats.styleOf("nonsense", false, ""), null);
  }

  function test_named() {
    compare(DateFormats.named("iso", "mediumDate"), "yyyy-MM-dd");
    compare(DateFormats.named("dmy", "mediumDate"), "d MMM yyyy");
    compare(DateFormats.named("mdy", "shortDate"), "ddd, MMM d");
    compare(DateFormats.named("iso", "clock24"), null, "times stay the language's");
    compare(DateFormats.named("iso", "monthYear"), null);
    compare(DateFormats.named(null, "mediumDate"), null);
  }

  function test_firstDay() {
    compare(DateFormats.firstDay("monday", 7), 1);
    compare(DateFormats.firstDay("sunday", 1), 0);
    compare(DateFormats.firstDay("saturday", 1), 6);
    compare(DateFormats.firstDay("region", 7), 0, "Qt's Sunday is 7");
    compare(DateFormats.firstDay("region", 1), 1);
    compare(DateFormats.firstDay("region", 6), 6);
  }

  function test_names() {
    compare(DateFormats.clockName(true, false), "clock24");
    compare(DateFormats.clockName(false, true), "clock12s");
    compare(DateFormats.timeName(true), "time24");
    compare(DateFormats.timeName(false), "time12");
  }
}
