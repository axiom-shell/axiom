pragma Singleton
import QtQuick

// Where a notification goes, for NotificationManager. A level is "alert"
// (toasts, kept in the list, counted on the badge), "silent" (kept in the
// Quiet section only: no toast, no count), "toast" (toasts, never kept)
// or "off" (dropped). An app's rule sets it, else its urgency does: a
// low-urgency one takes NotificationsConfig.lowUrgency. Urgencies are
// NotificationUrgency's numbers: 0 low, 1 normal, 2 critical.
QtObject {
  id: root

  // The level of a notification: its rule's (`ruleLevel`, "" with no
  // rule), else `lowUrgency` for a low one, else alert
  function levelOf(ruleLevel, urgency, lowUrgency) {
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
}
