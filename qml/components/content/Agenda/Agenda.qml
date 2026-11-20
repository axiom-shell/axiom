pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts
import qs.components.content.parts.calendar

// What's coming up: the shown calendars' events from today through `days`,
// grouped by day; a click opens one in the editor, + adds one today.
// Compact, the next event.
// properties: { days, count, calendars, showAllDay, showHeader }
Panel {
  id: root

  // The event open in the editor (built only while one is)
  property EventDraft session: EventDraft {}

  spacing: Widget.spacing
  fullMinWidth: Appearance.fontSize * 12
  fullMinHeight: Appearance.fontSize * 8

  Component.onCompleted: CalendarManager.acquire(root)
  Component.onDestruction: CalendarManager.release(root)

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }
  readonly property real now: clock.date.getTime()
  readonly property string todayKey: CalendarEvents.dayKey(clock.date)
  // [{ key, events }] from today on, each day's events in order (a day's
  // all-day and running events included)
  readonly property var groups: {
    const out = [];
    let left = root.properties.count;
    for (let i = 0; i < root.properties.days && left > 0; i++) {
      const key = CalendarEvents.addDays(root.todayKey, i);
      const events = CalendarManager.eventsOn(key, root.properties.calendars).filter(event => (root.properties.showAllDay || !event.allDay) && (i > 0 || event.end > root.now)).slice(0, left);
      if (events.length > 0)
        out.push({
          "key": key,
          "events": events
        });
      left -= events.length;
    }
    return out;
  }
  // Only while a first sync runs and nothing failed: a sync that never writes
  // events.json leaves lastSync 0 for good
  readonly property bool loading: CalendarManager.hasCalendars && CalendarManager.lastSync === 0 && CalendarManager.syncing && CalendarManager.errors.length === 0 && root.groups.length === 0 && !root.session.active
  readonly property var next: CalendarEvents.nextEvent(CalendarManager.upcoming(root.now, root.now + root.properties.days * CalendarEvents.dayMs, false, root.properties.calendars), root.now, root.properties.days * CalendarEvents.dayMs, false)

  compactContent: CompactFigure {
    icon: "event_note"
    value: root.next ? (root.next.start <= root.now ? I18n.tr("Now") : I18n.formatDate(new Date(root.next.start), CalendarConfig.timeFormat)) : "—"
    label: root.next ? root.next.title : I18n.tr("Nothing coming up")
  }

  // A day's heading: Today, Tomorrow, else its date
  function dayTitle(key) {
    if (key === root.todayKey)
      return I18n.tr("Today");
    if (key === CalendarEvents.addDays(root.todayKey, 1))
      return I18n.tr("Tomorrow");
    return I18n.formatDate(CalendarEvents.dateOf(key), I18n.dateFormat("longDate"));
  }

  ModuleHeader {
    visible: !root.session.active && root.properties.showHeader
    icon: "event_note"
    title: I18n.tr("Agenda")
    FlatIconButton {
      visible: CalendarManager.writableCalendars.length > 0
      size: Math.round(Appearance.fontSize * 1.8)
      iconText: "add"
      iconColor: Style.accent
      tooltipText: I18n.tr("New event")
      onClicked: root.session.open(CalendarEvents.newDraft(root.todayKey, Date.now(), CalendarManager.newEventCalendar, CalendarConfig.defaultDuration, CalendarConfig.defaultReminder))
    }
  }

  // Grows to list every day (from compact, to the full layout); empty,
  // back to its place; editing, as it is
  wantedHeight: root.session.active ? root.height : root.groups.length === 0 ? 0 : days.height > 0 ? root.height + days.contentHeight - days.height : 1

  // A ListView, so only the days in view are built
  ListView {
    id: days
    ScrollIndicator.vertical: StyledScrollIndicator {}

    visible: !root.session.active && root.groups.length > 0
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Widget.spacing
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    model: CountModel {
      count: root.groups.length
    }

    delegate: ColumnLayout {
      id: group
      required property int index
      readonly property var day: root.groups[index] ?? {
        "key": "",
        "events": []
      }
      width: ListView.view.width
      spacing: 2

      StyledText {
        Layout.leftMargin: Widget.spacing / 2
        text: root.dayTitle(group.day.key)
        role: "caption"
        font.weight: Style.weightStrong
        tone: group.day.key === root.todayKey ? "accent" : "muted"
      }
      Repeater {
        model: group.day.events.length
        EventRow {
          required property int index
          event: group.day.events[index] ?? null
          dayKey: group.day.key
          twoLines: root.innerWidth < Appearance.fontSize * 22
          onClicked: root.session.open(CalendarEvents.draftOf(event))
        }
      }
    }
  }

  Skeleton {
    visible: root.loading
    Layout.fillWidth: true
    lines: 3
  }

  // A plain Item takes the free height (a layout's maximum would cap it,
  // and the column would spread the rest around the header)
  Item {
    visible: !root.session.active && root.groups.length === 0 && !root.loading
    Layout.fillWidth: true
    Layout.fillHeight: true

    EmptyState {
      anchors.centerIn: parent
      maxWidth: parent.width
      availableHeight: parent.height
      icon: CalendarManager.hasCalendars ? "event_available" : "calendar_month"
      text: CalendarManager.hasCalendars ? I18n.tr("Nothing coming up") : I18n.tr("No calendars yet: add an account in Settings")
    }
  }

  Loader {
    active: root.session.active
    visible: active
    Layout.fillWidth: true
    Layout.fillHeight: true
    sourceComponent: EventEditor {
      session: root.session
    }
  }
}
