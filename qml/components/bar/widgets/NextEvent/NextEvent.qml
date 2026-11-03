pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// The next event within `lookahead` (or the one under way): "in 10
// min · Standup", "now · Standup", "15:00 · Dentist". Hidden with none.
// Hovering opens the calendar; a click opens the Calendar page on its day.
// Its display style fills with an event under way, or puts when over the
// title (stacked).
ValueStyleWidget {
  id: root

  Component.onCompleted: CalendarManager.acquire(root)
  Component.onDestruction: CalendarManager.release(root)

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }
  readonly property real now: clock.date.getTime()
  readonly property real lookahead: root.properties.lookahead
  readonly property var event: CalendarEvents.nextEvent(CalendarManager.upcoming(root.now, root.now + root.lookahead, root.properties.showAllDay), root.now, root.lookahead, root.properties.showAllDay)
  readonly property int minutesAway: root.event ? Math.ceil((root.event.start - root.now) / 60000) : 0
  // The event's day (today for one under way): "" for today, else
  // Tomorrow or its date, since the lookahead can reach past today
  readonly property string todayKey: CalendarEvents.dayKey(root.now)
  readonly property string eventDay: root.event ? CalendarEvents.dayKey(Math.max(root.event.start, root.now)) : ""
  readonly property string dayText: root.eventDay === root.todayKey ? "" : root.eventDay === CalendarEvents.addDays(root.todayKey, 1) ? I18n.tr("Tomorrow") : I18n.formatDate(CalendarEvents.dateOf(root.eventDay), I18n.dateFormat("shortDate"))

  readonly property string when: {
    if (!root.event)
      return "";
    if (root.event.allDay)
      return root.dayText || I18n.tr("Today");
    if (root.minutesAway <= 0)
      return I18n.tr("now");
    if (root.minutesAway < 60)
      return I18n.tr("in {0} min", root.minutesAway);
    const time = I18n.formatDate(new Date(root.event.start), CalendarConfig.timeFormat);
    return root.dayText ? I18n.tr("{0} · {1}", root.dayText, time) : time;
  }

  hidden: root.event === null
  icon: "event"
  text: root.event ? I18n.tr("{0} · {1}", root.when, root.title) : ""
  readonly property string title: root.event ? Utils.truncate(root.event.title || I18n.tr("(No title)"), root.properties.maxLength, "…") : ""
  // How far through an event under way (not an all-day one) it is
  ratio: root.event && !root.event.allDay && root.event.start <= root.now && root.event.end > root.event.start ? Math.min(1, (root.now - root.event.start) / (root.event.end - root.event.start)) : -1
  styleText: root.style === "stacked" ? root.when : root.text
  subtext: root.title
  // Soon (a quarter hour or less): the warning color
  accentColor: root.event && !root.event.allDay && root.minutesAway <= 15 ? Theme.warning : Theme.resolveColor(properties.backgroundColor)

  clickable: true
  onClicked: CalendarManager.openPage({
    "kind": "day",
    "key": CalendarEvents.dayKey(root.event ? root.event.start : root.now)
  })

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "Calendar"
    openDelay: 150
    active: EdgeMenusConfig.opensOwnPopout(root.properties)
  }
}
