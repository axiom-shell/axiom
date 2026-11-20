pragma Singleton
import QtQuick

// Stand-in for the shell's CalendarManager in the layout harness: no calendars,
// no events.
QtObject {
  property var events: []
  property var errors: []
  property var calendars: []
  property var writableCalendars: []
  property var colors: ({})
  property var request: null
  property string newEventCalendar: ""
  property bool hasCalendars: false
  property bool syncing: false
  property QtObject page: QtObject {
    property int year: 2026
    property int month: 9
  }

  function acquire(owner) {
  }

  function release(owner) {
  }

  function ensureMonth(year, month) {
  }

  function eventsOn(key, calendars) {
    return [];
  }

  function dotsFor(key, calendars) {
    return [];
  }

  function upcoming(now, until, allDay, calendars) {
    return [];
  }

  function timeText(event, key) {
    return "";
  }

  function takeRequest() {
    return null;
  }

  function openPage(request) {
  }

  function sync() {
  }
}
