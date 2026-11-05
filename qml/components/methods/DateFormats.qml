pragma Singleton
import QtQuick

// How Settings › System › Date & time turns into formats (I18n's): the
// hour cycle, the date order and the first day of the week, each either
// set or read from a region's formats (a Qt locale's patterns, passed in as
// text so this stays pure). Names (days, months) always come from the
// language; only the order and the clock follow these. No file access,
// processes or services.
QtObject {
  id: root

  // Whether times read 24-hour: `hourFormat` "24" or "12", else
  // ("auto") what the region's short time pattern does (no AM/PM field)
  function use24Hour(hourFormat, regionTimePattern) {
    if (hourFormat === "24")
      return true;
    if (hourFormat === "12")
      return false;
    return !/a|A|ap|AP/.test(String(regionTimePattern ?? ""));
  }

  // The order a short date pattern reads in: "dmy", "mdy" or "ymd"
  // ("dd.MM.yy" → "dmy", "M/d/yy" → "mdy", "yyyy/MM/dd" → "ymd")
  function orderOf(pattern) {
    const p = String(pattern ?? "");
    const at = c => {
      const i = p.indexOf(c);
      return i < 0 ? Infinity : i;
    };
    const d = at("d"), m = at("M"), y = at("y");
    if (y < d && y < m)
      return "ymd";
    return m < d ? "mdy" : "dmy";
  }

  // The style `dateStyle` means: "language" (the language's own formats,
  // as before: null), an order ("dmy", "mdy", "ymd") or "iso". "region"
  // is the region's order when a region is set, else the language's
  function styleOf(dateStyle, regionSet, regionDatePattern) {
    if (dateStyle === "region")
      return regionSet ? root.orderOf(regionDatePattern) : null;
    if (dateStyle === "language" || !root._styles[dateStyle])
      return null;
    return dateStyle;
  }

  // A named date format (I18n.dateFormat's names) in a style, or null
  // when the style leaves it to the language (null style, or a name it
  // doesn't change: the clock and time formats, monthYear)
  function named(style, name) {
    const table = style ? root._styles[style] : null;
    return table?.[name] ?? null;
  }

  // The first day of the week as 0 (Sunday) to 6 (Saturday):
  // `firstDayOfWeek` "monday" | "sunday" | "saturday", else ("region")
  // the region's (Qt's Locale.firstDayOfWeek: 1 Monday … 7 Sunday)
  function firstDay(firstDayOfWeek, regionFirstDay) {
    switch (firstDayOfWeek) {
    case "monday":
      return 1;
    case "sunday":
      return 0;
    case "saturday":
      return 6;
    }
    return Number(regionFirstDay ?? 1) % 7;
  }

  // The time pattern for a clock: 24 or 12 hour, with seconds or not, from
  // the language's four (clock24, clock24s, clock12, clock12s)
  function clockName(use24Hour, seconds) {
    return (use24Hour ? "clock24" : "clock12") + (seconds ? "s" : "");
  }

  // The time pattern for an event or file time (time24 / time12)
  function timeName(use24Hour) {
    return use24Hour ? "time24" : "time12";
  }

  // The regions offered (Qt locale codes): the countries Qt has formats
  // for that most people ask about, sorted by code
  readonly property var regions: ["ar_EG", "ar_SA", "bg_BG", "cs_CZ", "da_DK", "de_AT", "de_CH", "de_DE", "el_GR", "en_AU", "en_CA", "en_GB", "en_IE", "en_IN", "en_NZ", "en_SG", "en_US", "en_ZA", "es_AR", "es_ES", "es_MX", "et_EE", "fi_FI", "fr_BE", "fr_CA", "fr_CH", "fr_FR", "he_IL", "hi_IN", "hr_HR", "hu_HU", "id_ID", "it_IT", "ja_JP", "ko_KR", "lt_LT", "lv_LV", "ms_MY", "nb_NO", "nl_BE", "nl_NL", "pl_PL", "pt_BR", "pt_PT", "ro_RO", "ru_RU", "sk_SK", "sl_SI", "sr_RS", "sv_SE", "th_TH", "tr_TR", "uk_UA", "vi_VN", "zh_CN", "zh_HK", "zh_TW"]

  // Each style's named formats (the ones I18n's defaults hold dates in)
  readonly property var _styles: ({
      "dmy": {
        "longDate": "dddd, d MMMM",
        "mediumDate": "d MMM yyyy",
        "shortDate": "ddd d MMM",
        "fullDate": "dddd, d MMMM yyyy",
        "dateTime": "d MMM yyyy HH:mm"
      },
      "mdy": {
        "longDate": "dddd, MMMM d",
        "mediumDate": "MMM d, yyyy",
        "shortDate": "ddd, MMM d",
        "fullDate": "dddd, MMMM d, yyyy",
        "dateTime": "MMM d, yyyy HH:mm"
      },
      "ymd": {
        "longDate": "dddd, MMMM d",
        "mediumDate": "yyyy MMM d",
        "shortDate": "ddd MMM d",
        "fullDate": "dddd, yyyy MMMM d",
        "dateTime": "yyyy MMM d HH:mm"
      },
      "iso": {
        "longDate": "dddd yyyy-MM-dd",
        "mediumDate": "yyyy-MM-dd",
        "shortDate": "ddd MM-dd",
        "fullDate": "dddd yyyy-MM-dd",
        "dateTime": "yyyy-MM-dd HH:mm"
      }
    })
}
