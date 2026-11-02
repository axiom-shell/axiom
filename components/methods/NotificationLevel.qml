pragma Singleton
import QtQuick

// Where a notification goes, for NotificationManager. A level is "alert"
// (toasts, kept in the list, counted on the badge), "silent" (kept in the
// Quiet section only: no toast, no count), "toast" (toasts, never kept)
// or "off" (dropped). An app's rule sets it, else its urgency does: a
// low-urgency one takes NotificationsConfig.lowUrgency, and a critical
// one is never silent (a Silent rule still lets it alert). Urgencies are
// NotificationUrgency's numbers: 0 low, 1 normal, 2 critical.
QtObject {
  id: root

  // The level of a notification: its rule's (`ruleLevel`, "" with no
  // rule; a critical one alerts through Silent), else `lowUrgency` for a
  // low one, else alert
  function levelOf(ruleLevel, urgency, lowUrgency) {
    if (ruleLevel === "silent" && urgency === 2)
      return "alert";
    if (ruleLevel)
      return ruleLevel;
    return urgency === 0 ? lowUrgency : "alert";
  }

  // Whether it toasts: an alert or toast-only one, while do not disturb is
  // off, or a critical one through it with `allowCritical`
  function toasts(level, dnd, allowCritical, urgency) {
    if (level !== "alert" && level !== "toast")
      return false;
    return !dnd || (allowCritical && urgency === 2);
  }

  // Whether it gets an entry: an alert or silent one that isn't transient
  function files(level, transient) {
    return !transient && (level === "alert" || level === "silent");
  }

  // The entries kept, newest first: the alerts by `limits.maxEntries` and
  // `maxAge`, the silent ones by `quietMaxEntries` and `quietMaxAge`
  // (ms; an age 0 keeps them however old)
  function kept(entries, now, limits) {
    const sorted = (entries ?? []).slice().sort((a, b) => b.time - a.time);
    const keep = (list, max, age) => list.filter(e => age <= 0 || e.time >= now - age).slice(0, max);
    const alerts = keep(sorted.filter(e => !e.silent), limits.maxEntries, limits.maxAge);
    const quiet = keep(sorted.filter(e => !!e.silent), limits.quietMaxEntries, limits.quietMaxAge);
    return sorted.filter(e => alerts.includes(e) || quiet.includes(e));
  }

  // The shell's sources, by desktop entry: the English name of each one's
  // list card (translated where shown), and the names a rule can give to
  // set one source's level (the settings' App suggestions). Declared for
  // the translation check: I18n.tr("Calendar"), I18n.tr("Connections"),
  // I18n.tr("Do not disturb"), I18n.tr("Drives"), I18n.tr("Login screen"),
  // I18n.tr("Monitors"), I18n.tr("Pomodoro"), I18n.tr("Screenshots"),
  // I18n.tr("Settings"), I18n.tr("Stopwatch"), I18n.tr("Axiom update"), I18n.tr("Updates")
  readonly property var sources: ({
      "axiom-calendar": "Calendar",
      "axiom-connectivity": "Connections",
      "axiom-dnd": "Do not disturb",
      "axiom-drives": "Drives",
      "axiom-greeter-update": "Login screen",
      "axiom-monitors": "Monitors",
      "axiom-pomodoro": "Pomodoro",
      "axiom-screenshot": "Screenshots",
      "axiom-settings": "Settings",
      "axiom-stopwatch": "Stopwatch",
      "axiom-update": "Axiom update",
      "axiom-updates": "Updates"
    })

  // The list card an entry goes in: its app's, or for the shell's own
  // (app name "axiom") its source's desktop entry (axiom-drives,
  // axiom-updates, …), so each source gets a card of its own
  function groupKey(entry) {
    const app = entry?.appName || entry?.desktopEntry || "";
    return app === "axiom" && entry?.desktopEntry ? entry.desktopEntry : app;
  }
}
