pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components.methods
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts.calendar
import qs.services.apps

// A clock with the date, plus a month calendar where it fits (beside the
// clock in wide slots, or where it only fits that way); a wide strip puts
// the date beside the time. Arrows page through months. With `showEvents`
// (on the lock screen only with Calendar.showOnLockscreen, and read-only
// there, as on the desktop; never on the login screen) days with events
// get their calendars' dots, and where there's room the day's events list
// under the calendar (under the clock when it sits beside it): today's, or
// the day clicked
// until it's clicked again. Without room a clicked day covers the card.
// Events open in the editor, over the whole card.
// properties: { use24Hour, showSeconds, showEvents }
Card {
  id: root

  readonly property bool onLockscreen: root.host?.kind === "lockscreen"
  // Events can't be edited where nothing can be typed (the desktop) or
  // nothing may be written (the lock screen)
  readonly property bool eventsReadOnly: root.onLockscreen || root.host?.kind === "desktop"
  readonly property bool showEvents: (root.properties.showEvents ?? true) && (!root.onLockscreen || CalendarConfig.showOnLockscreen) && root.host?.kind !== "greeter" && !Paths.greeter
  // The day clicked in the calendar, "" for today
  property string openDay: ""
  readonly property string todayKey: CalendarEvents.dayKey(root.now)
  readonly property string shownDay: root.openDay || root.todayKey
  onShowEventsChanged: {
    if (root.showEvents)
      CalendarManager.acquire(root);
    else
      CalendarManager.release(root);
  }
  Component.onCompleted: {
    if (root.showEvents)
      CalendarManager.acquire(root);
  }
  Component.onDestruction: CalendarManager.release(root)

  // Calendar sizing: day cells close to square, never taller than they
  // are wide, and the whole grid capped so large slots keep a big clock
  readonly property real headerHeight: Appearance.fontSize * 1.8
  readonly property real weekdayHeight: Appearance.fontSize * 1.6
  // The smallest calendar (six weeks of the smallest cells), and whether
  // it fits under the clock or beside it
  readonly property real calendarMinHeight: root.headerHeight + root.weekdayHeight + Appearance.fontSize * 1.4 * 6
  readonly property real calendarMinWidth: Appearance.fontSize * 12
  readonly property bool fitsUnder: root.innerHeight >= root.clockMinHeight + Widget.spacing + root.calendarMinHeight && root.innerWidth >= root.calendarMinWidth
  readonly property bool fitsBeside: root.innerHeight >= root.calendarMinHeight && root.innerWidth >= root.calendarMinWidth + root.pad + Appearance.fontSize * 8
  readonly property bool showCalendar: !root.compact && (root.fitsUnder || root.fitsBeside)
  readonly property bool sideBySide: root.showCalendar && root.fitsBeside && (root.shape === "horizontal" || !root.fitsUnder)
  // A wide strip: the date beside the time
  readonly property bool clockRow: !root.showCalendar && root.innerWidth > root.innerHeight * 2.5
  // The day's events in the card: under the calendar, or under the clock
  // beside it, when the smallest list still fits
  readonly property real agendaMinHeight: Appearance.fontSize * 5
  readonly property bool inlineAgenda: root.showEvents && root.showCalendar && CalendarManager.hasCalendars && root.innerHeight >= (root.sideBySide ? root.clockMinHeight : root.clockMinHeight + root.calendarMinHeight + Widget.spacing) + Widget.spacing + root.agendaMinHeight
  // The clock gives what it doesn't need to the events
  readonly property real clockMaxHeight: root.inlineAgenda ? Math.max(root.clockMinHeight, Appearance.fontSize * 8) : Number.POSITIVE_INFINITY
  readonly property real calendarWidth: Math.min(root.sideBySide ? (root.innerWidth - root.pad) / 2 : root.innerWidth, Appearance.fontSize * 32)
  readonly property real clockMinHeight: Appearance.fontSize * 5
  readonly property real cellHeight: Math.max(Appearance.fontSize * 1.4, Math.min(root.calendarWidth / 7 * 0.85, ((root.sideBySide ? root.innerHeight : root.innerHeight - root.clockMinHeight - Widget.spacing - (root.inlineAgenda ? root.agendaMinHeight + Widget.spacing : 0)) - root.headerHeight - root.weekdayHeight) / 6))
  readonly property real calendarHeight: root.headerHeight + root.weekdayHeight + root.cellHeight * 6
  readonly property date now: clock.date
  // The language's time format (e.g. 午後 3:05 in Japanese), seconds added after the minutes
  readonly property string timeFormat: I18n.dateFormat(root.properties.use24Hour ? "time24" : "time12").replace("mm", root.properties.showSeconds ? "mm:ss" : "mm")

  SystemClock {
    id: clock
    precision: root.properties.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
  }

  // The day's events, in the card's layout
  component InlineAgenda: DayAgenda {
    dayKey: root.shownDay
    closable: root.openDay !== ""
    readOnly: root.eventsReadOnly
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: root.agendaMinHeight
    onEventClicked: event => pane.edit(event)
    onAddClicked: pane.newEvent()
    onClosed: root.openDay = ""
  }

  GridLayout {
    visible: !pane.visible
    anchors.fill: parent
    anchors.margins: root.pad
    columns: root.sideBySide ? 2 : 1
    columnSpacing: root.pad
    rowSpacing: Widget.spacing

    // Clock (and the events under it beside the calendar)
    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredWidth: root.sideBySide ? root.innerWidth - root.calendarWidth - root.pad : root.innerWidth
      spacing: Widget.spacing

      // As big as its area allows
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: root.inlineAgenda ? root.clockMinHeight : 0
        Layout.maximumHeight: root.clockMaxHeight

        GridLayout {
          id: clockBox
          anchors.centerIn: parent
          width: parent.width
          columns: root.clockRow ? 2 : 1
          columnSpacing: root.pad
          rowSpacing: 0
          StyledText {
            Layout.fillWidth: true
            // No taller than the digits fitted to the width need, so the date
            // stays right under them (beside them in a row: the strip's height)
            Layout.preferredHeight: root.clockRow ? clockBox.parent.height : Math.min(clockBox.width * 0.42, Math.max(Appearance.fontSize * 2, clockBox.parent.height - dateText.height) * 0.8)
            horizontalAlignment: root.clockRow ? Text.AlignRight : Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            fontSizeMode: Text.Fit
            minimumPixelSize: Math.min(Appearance.fontSize, Widget.px(8))
            textSize: Appearance.fontSize * 9
            text: I18n.formatDate(root.now, root.timeFormat)
            font.bold: true
          }
          StyledText {
            id: dateText
            visible: clockBox.parent.height >= Appearance.fontSize * 3 || root.clockRow
            Layout.fillWidth: !root.clockRow
            Layout.maximumWidth: root.clockRow ? clockBox.width * 0.45 : -1
            horizontalAlignment: root.clockRow ? Text.AlignLeft : Text.AlignHCenter
            elide: Text.ElideRight
            text: I18n.formatDate(root.now, I18n.dateFormat(root.compact ? "shortDate" : "longDate"))
            textSize: root.compact ? Appearance.fontSizeBy(-2) : Appearance.fontSize
            opacity: 0.7
          }
        }
      }

      InlineAgenda {
        visible: root.inlineAgenda && root.sideBySide
      }
    }

    // Calendar
    MonthGrid {
      visible: root.showCalendar
      Layout.alignment: Qt.AlignCenter
      Layout.preferredWidth: root.calendarWidth
      Layout.maximumWidth: root.calendarWidth
      Layout.preferredHeight: root.calendarHeight
      Layout.maximumHeight: root.calendarHeight
      headerHeight: root.headerHeight
      weekdayHeight: root.weekdayHeight
      showEvents: root.showEvents
      selectedKey: root.openDay
      // Listed: a click shows the day, a second (or today) goes back to
      // today; else it toggles the day over the card
      onDaySelected: key => {
        if (!root.showEvents)
          return;
        if (root.inlineAgenda)
          root.openDay = key === root.openDay || key === root.todayKey ? "" : key;
        else
          root.openDay = root.openDay === key ? "" : key;
      }
    }

    InlineAgenda {
      visible: root.inlineAgenda && !root.sideBySide
    }
  }

  // Over the whole card: the editor, or the opened day when the card has
  // no room to list it
  DayPane {
    id: pane
    anchors.fill: parent
    anchors.margins: root.pad
    visible: pane.editing || (root.openDay !== "" && !root.inlineAgenda)
    dayKey: root.shownDay
    closable: true
    readOnly: root.eventsReadOnly
    onClosed: root.openDay = ""
  }
}
