pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts
import qs.components.content.parts.calendar

// The month with a dot per calendar on days with events, and the selected
// day's events under it (beside it in a wide card), which open in the
// editor; + adds one. The Time widget's popout (it takes the keyboard while
// editing) and an overlay module. A card too short for both shows the
// month, and a picked day in its place.
Panel {
  id: root

  property string selectedKey: CalendarEvents.dayKey(new Date())

  spacing: Widget.spacing
  fullMinWidth: Appearance.fontSize * 14
  fullMinHeight: Appearance.fontSize * 14

  // A card: side by side when wide, stacked when tall enough, else the
  // month or the day in turn
  readonly property bool sideBySide: root.embedded && root.innerWidth >= Appearance.fontSize * 30 && root.innerWidth > root.innerHeight * 1.2
  readonly property bool stacked: !root.sideBySide && (!root.embedded || root.innerHeight >= Appearance.fontSize * 26)
  property bool _dayOpen: false
  readonly property bool showGrid: root.sideBySide || root.stacked || !root._dayOpen
  readonly property bool showDay: root.sideBySide || root.stacked || root._dayOpen
  readonly property real gridHeight: !root.embedded ? Appearance.fontSize * 17 : root.sideBySide ? root.innerHeight : root.stacked ? Math.min(root.innerHeight * 0.55, root.innerWidth * 0.95) : root.innerHeight

  wantsKeyboardFocus: pane.editing
  onFocusLost: pane.stopEditing()

  // Wider while the editor's buttons need it (a long translation)
  implicitWidth: Math.max(Appearance.fontSize * 20, pane.actionsWidth)
  // In a popout, room for the editor from the start
  maxImplicitHeight: root.embedded ? 0 : root.implicitHeight + pane.growth
  Component.onCompleted: {
    CalendarManager.acquire(root);
    root._takeRequest();
  }
  Component.onDestruction: CalendarManager.release(root)

  // The page's request, when this card is where it landed
  function _takeRequest() {
    if (!root.embedded || !CalendarManager.request)
      return;
    const request = CalendarManager.takeRequest();
    root.selectDay(request.key);
    if (request.kind === "new")
      Qt.callLater(pane.newEvent);
  }
  Connections {
    target: CalendarManager
    function onRequestChanged() {
      root._takeRequest();
    }
  }

  function selectDay(key) {
    root.selectedKey = key;
    grid.showDay(key);
    root._dayOpen = true;
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }
  readonly property string todayKey: CalendarEvents.dayKey(clock.date)
  readonly property var todayEvents: CalendarManager.eventsOn(root.todayKey)
  readonly property var nextEvent: CalendarEvents.nextEvent(CalendarManager.upcoming(clock.date.getTime(), clock.date.getTime() + 86400000, false), clock.date.getTime(), 86400000, false)

  compactContent: CompactFigure {
    icon: "calendar_month"
    value: String(root.todayEvents.length)
    label: root.nextEvent ? I18n.tr("Next: {0}", root.nextEvent.title) : I18n.tr("today")
  }

  GridLayout {
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    columns: root.sideBySide ? 2 : 1
    columnSpacing: root.pad
    rowSpacing: Widget.spacing

    MonthGrid {
      id: grid
      visible: root.showGrid
      Layout.fillWidth: !root.sideBySide
      Layout.preferredWidth: root.sideBySide ? Math.min(root.innerWidth * 0.5, root.innerHeight * 1.15) : -1
      Layout.preferredHeight: root.gridHeight
      Layout.alignment: Qt.AlignTop
      selectedKey: root.selectedKey
      onDaySelected: key => {
        root.selectedKey = key;
        root._dayOpen = true;
      }
    }

    DayPane {
      id: pane
      visible: root.showDay
      Layout.fillWidth: true
      Layout.fillHeight: root.embedded
      Layout.preferredHeight: root.embedded ? -1 : implicitHeight
      Layout.minimumHeight: root.embedded ? 0 : Appearance.fontSize * 6
      dayKey: root.selectedKey
      closable: root.embedded && !root.sideBySide && !root.stacked
      maxListHeight: root.embedded ? Number.POSITIVE_INFINITY : Appearance.fontSize * 14
      onClosed: root._dayOpen = false
    }
  }

  // The sync state, and the Calendar page
  RowLayout {
    visible: !root.embedded
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    StyledText {
      Layout.fillWidth: true
      text: CalendarManager.syncing ? I18n.tr("Syncing…") : CalendarManager.errors.length > 0 ? I18n.tr("{0} calendars couldn't sync", CalendarManager.errors.length) : ""
      textColor: CalendarManager.errors.length > 0 && !CalendarManager.syncing ? Theme.error : Theme.foregroundAlt
      textSize: Appearance.fontSizeBy(-2)
      elide: Text.ElideRight
    }
    FlatIconButton {
      iconText: "sync"
      tooltipText: I18n.tr("Sync now")
      visible: CalendarManager.hasCalendars
      enabled: !CalendarManager.syncing
      onClicked: CalendarManager.sync()
    }
    FlatIconButton {
      iconText: "open_in_full"
      tooltipText: I18n.tr("Open the calendar")
      onClicked: CalendarManager.openPage({
        "kind": "day",
        "key": root.selectedKey
      })
    }
  }
}
