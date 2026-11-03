pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods
import qs.components.reusable

// A date and, unless `allDay`, a time: the date a button that folds a
// MonthGrid open under it, the time typed ("9", "9:30", "930", "9pm") and
// shown in the language's format. `value` is pushed in (epoch ms); a
// change emits `edited` with the new value, and the owner sets `value`.
ColumnLayout {
  id: root

  property real value: Date.now()
  property bool allDay: false
  property bool readOnly: false
  property string label: ""

  signal edited(real value)

  spacing: Widget.spacing / 2

  readonly property string _shown: I18n.formatDate(new Date(root.value), CalendarConfig.timeFormat)
  on_ShownChanged: root._pushTime()
  Component.onCompleted: root._pushTime()

  // The time as typed, while it isn't being typed in
  function _pushTime() {
    if (!timeEntry.input.activeFocus)
      timeEntry.text = root._shown;
  }

  // Takes a typed time, or puts the shown one back
  function _commitTime() {
    const time = CalendarEvents.parseTime(timeEntry.text);
    if (time) {
      const d = new Date(root.value);
      const next = new Date(d.getFullYear(), d.getMonth(), d.getDate(), time.hour, time.minute).getTime();
      if (next !== root.value)
        root.edited(next);
    }
    timeEntry.text = root._shown;
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    StyledText {
      visible: root.label !== ""
      Layout.preferredWidth: Appearance.fontSize * 4.5
      text: root.label
      textColor: Theme.foregroundAlt
      textSize: Appearance.fontSizeBy(-1)
      elide: Text.ElideRight
    }
    StyledTextButton {
      Layout.fillWidth: true
      Layout.preferredHeight: Widget.height
      text: I18n.formatDate(new Date(root.value), I18n.dateFormat("shortDate"))
      iconText: "calendar_today"
      backgroundColor: Theme.backgroundAlt
      borderColor: picker.open ? Theme.accent : Theme.border
      borderWidth: Appearance.borderWidth
      enabled: !root.readOnly
      onClicked: {
        if (!picker.open)
          grid.showDay(CalendarEvents.dayKey(root.value));
        picker.open = !picker.open;
      }
    }
    StyledTextEntry {
      id: timeEntry
      visible: !root.allDay
      Layout.preferredWidth: Appearance.fontSize * 6
      Layout.preferredHeight: Widget.height
      readOnly: root.readOnly
      onAccepted: root._commitTime()
    }
    Connections {
      target: timeEntry.input
      function onActiveFocusChanged() {
        if (!timeEntry.input.activeFocus)
          root._commitTime();
      }
    }
  }

  FoldingColumn {
    id: picker
    Layout.fillWidth: true
    open: false

    MonthGrid {
      id: grid
      Layout.fillWidth: true
      Layout.preferredHeight: implicitHeight
      showEvents: false
      selectedKey: CalendarEvents.dayKey(root.value)
      onDaySelected: key => {
        picker.open = false;
        root.edited(CalendarEvents.onDay(root.value, key));
      }
    }
  }
}
