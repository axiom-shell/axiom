pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Calendar section (see CalendarManager, which adds what the
// servers say of each calendar). Account passwords are not config: see
// SecretsManager.
QtObject {
  id: root
  readonly property var _c: ConfigManager.config.Calendar
  // Calendar.items as saved, for editing
  readonly property var savedAccounts: _c.items
  // Calendar.items, each with a `name` (the username or the server's host
  // when left empty; "This computer" for a local one); each account's
  // `calendars` as configured: { href, name (an override, or ""), color
  // (a theme color name, or ""), enabled }
  readonly property var accounts: _c.items.map((account, index) => Object.assign({}, account, {
      "name": account.name || account.username || root.hostOf(account.url) || (account.kind === "local" ? I18n.tr("This computer") : I18n.tr("Account {0}", index + 1))
    }))
  readonly property string defaultCalendar: _c.defaultCalendar
  // A new event's length (minutes)
  readonly property int defaultDuration: Math.round(_c.defaultDuration / 60000)
  // A new event's reminder: minutes before the start, -1 for none
  readonly property int defaultReminder: _c.defaultReminder < 0 ? -1 : Math.round(_c.defaultReminder / 60000)
  readonly property bool reminders: _c.reminders
  // How often calendars sync (ms)
  readonly property int syncInterval: _c.syncInterval
  readonly property int pastMonths: _c.pastMonths
  readonly property int futureMonths: _c.futureMonths
  readonly property int maxDots: _c.maxDots
  // The Clock & calendar module's events on the lock screen too
  readonly property bool showOnLockscreen: _c.showOnLockscreen
  readonly property bool use24Hour: _c.use24Hour
  // The language's time format, for event times
  readonly property string timeFormat: I18n.dateFormat(root.use24Hour ? "time24" : "time12")
  // Kinds whose events axiom can change: CalDAV accounts and local
  // calendars (.ics subscriptions are read-only)
  function writableKind(kind) {
    return kind === "caldav" || kind === "local";
  }
  function hostOf(url) {
    const match = String(url ?? "").match(/^[a-z]+:\/\/([^/:]+)/i);
    return match ? match[1] : "";
  }
}
