pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.apps
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts
import qs.components.content.parts.calendar

// The pomodoro timer, the todo list and today's events (DayPane) in one
// card: the timer and list side by side with the day when the card is
// wide, stacked otherwise. Each part can be turned off. Compact, the time
// left and the open count.
// properties: { showTimer, showTodos, showAgenda }
Panel {
  id: root

  readonly property bool wide: root.innerWidth >= Appearance.fontSize * 34
  readonly property bool showTimer: root.properties.showTimer ?? true
  readonly property bool showTodos: root.properties.showTodos ?? true
  readonly property bool showAgenda: root.properties.showAgenda ?? true

  spacing: Widget.spacing
  wantsKeyboardFocus: true
  implicitWidth: Appearance.fontSize * 40
  implicitHeight: Appearance.fontSize * 30
  fullMinWidth: Appearance.fontSize * 16
  fullMinHeight: Appearance.fontSize * 14

  // The calendar only while today's events show
  function registerCalendar() {
    if (root.showAgenda)
      CalendarManager.acquire(root);
    else
      CalendarManager.release(root);
  }
  onShowAgendaChanged: registerCalendar()
  Component.onCompleted: {
    PomodoroManager.acquire(root);
    root.registerCalendar();
  }
  Component.onDestruction: {
    PomodoroManager.release(root);
    CalendarManager.release(root);
  }

  compactContent: CompactFigure {
    icon: PomodoroManager.isBreak ? "coffee" : "center_focus_strong"
    value: PomodoroManager.idle ? String(TodoManager.openCount) : PomodoroManager.remainingText
    label: PomodoroManager.idle ? I18n.tr("to do") : PomodoroManager.phaseLabel
  }

  GridLayout {
    Layout.fillWidth: true
    Layout.fillHeight: true
    columns: root.wide && root.showAgenda ? 2 : 1
    columnSpacing: Widget.spacing * 2
    rowSpacing: Widget.spacing

    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredWidth: 1
      spacing: Widget.spacing

      PomodoroDial {
        visible: root.showTimer
        Layout.fillWidth: true
        horizontal: true
        showTask: false
        dialSize: Appearance.fontSize * 6
      }

      StyledSeparator {
        visible: root.showTimer && root.showTodos
        Layout.fillWidth: true
      }

      TodoList {
        visible: root.showTodos
        Layout.fillWidth: true
        Layout.fillHeight: true
        fill: true
      }
    }

    DayPane {
      visible: root.showAgenda
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredWidth: 1
      Layout.minimumHeight: Appearance.fontSize * 8
    }
  }
}
