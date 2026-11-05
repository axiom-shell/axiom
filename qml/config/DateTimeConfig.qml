pragma Singleton
import QtQuick
import qs.services.core

// Reader for the DateTime section: how times and dates read (I18n applies
// it: `use24Hour`, `dateFormat`, `firstDayOfWeek`).
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.DateTime

  // "auto" (the region's clock) | "12" | "24"
  readonly property string hourFormat: _c.hourFormat
  // "region" | "language" | "dmy" | "mdy" | "ymd" | "iso"
  readonly property string dateStyle: _c.dateStyle
  // "region" | "monday" | "sunday" | "saturday"
  readonly property string firstDayOfWeek: _c.firstDayOfWeek
  // A Qt locale code ("de_DE"), "" for the language's
  readonly property string region: _c.region
}
