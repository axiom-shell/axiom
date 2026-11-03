pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.components.methods

// The Calendar page's view state, kept past the page so it survives moving
// between the overlay and its window (and the overlay closing): the day
// selected, the month shown and the event being edited. A selected today
// follows the date past midnight, unless an event is open. Not a
// singleton: CalendarManager holds one as `page`.
QtObject {
  id: root

  readonly property string todayKey: CalendarEvents.dayKey(root._clock.date)
  // Plain values (set by goToday at start), so a new day moves them only
  // through onTodayKeyChanged
  property string selectedKey: ""
  property int year: 0
  property int month: 0
  // The page's event editor (DayPane's)
  readonly property EventDraft draft: EventDraft {}

  function select(key) {
    root.selectedKey = key;
  }

  // Shows the month holding `key` ("YYYY-MM-DD")
  function showDay(key) {
    const d = CalendarEvents.dateOf(key);
    root.year = d.getFullYear();
    root.month = d.getMonth();
  }

  function step(delta) {
    const d = new Date(root.year, root.month + delta, 1);
    root.year = d.getFullYear();
    root.month = d.getMonth();
  }

  function goToday() {
    root.showDay(root.todayKey);
    root.select(root.todayKey);
  }

  property SystemClock _clock: SystemClock {
    precision: SystemClock.Hours
  }

  // The day before the last change, to tell whether today was selected
  property string _lastToday: ""
  onTodayKeyChanged: {
    const before = root._lastToday;
    root._lastToday = root.todayKey;
    if (before === "" || root.draft.active || root.selectedKey !== before)
      return;
    const was = CalendarEvents.dateOf(before);
    if (was.getFullYear() === root.year && was.getMonth() === root.month)
      root.showDay(root.todayKey);
    root.select(root.todayKey);
  }
  Component.onCompleted: {
    root._lastToday = root.todayKey;
    root.goToday();
  }
}
