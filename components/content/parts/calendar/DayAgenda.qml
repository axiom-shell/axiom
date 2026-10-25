pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.content.parts

// A day's events under its date, with + to add one (when a calendar can
// take it) and, with `closable`, a back arrow. The list scrolls when it
// doesn't fit; `maxListHeight` caps it where nothing else does (a popout).
// `readOnly` (the lock screen) only lists: no +, no clicks, no settings.
ColumnLayout {
  id: root

  property string dayKey: CalendarEvents.dayKey(new Date())
  property bool closable: false
  property real maxListHeight: Number.POSITIVE_INFINITY
  property bool readOnly: false

  signal eventClicked(var event)
  signal addClicked
  signal closed

  readonly property var dayEvents: CalendarManager.eventsOn(root.dayKey)

  spacing: Widget.spacing / 2

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    FlatIconButton {
      visible: root.closable
      size: Math.round(Appearance.fontSize * 1.8)
      iconText: "arrow_back"
      onClicked: root.closed()
    }
    StyledText {
      Layout.fillWidth: true
      Layout.leftMargin: root.closable ? 0 : Widget.spacing / 2
      text: I18n.formatDate(CalendarEvents.dateOf(root.dayKey), I18n.dateFormat("longDate"))
      font.bold: true
      elide: Text.ElideRight
    }
    FlatIconButton {
      visible: !root.readOnly && CalendarManager.writableCalendars.length > 0
      size: Math.round(Appearance.fontSize * 1.8)
      iconText: "add"
      iconColor: Theme.accent
      tooltipText: I18n.tr("New event")
      onClicked: root.addClicked()
    }
  }

  Flickable {
    visible: root.dayEvents.length > 0
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.preferredHeight: Math.min(list.implicitHeight, root.maxListHeight)
    Layout.maximumHeight: root.maxListHeight
    contentHeight: list.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    ColumnLayout {
      id: list
      width: parent.width
      spacing: 2

      // By count: a day's list is rebuilt only when its length changes
      Repeater {
        model: root.dayEvents.length
        EventRow {
          required property int index
          event: root.dayEvents[index] ?? null
          dayKey: root.dayKey
          clickable: !root.readOnly
          onClicked: root.eventClicked(event)
        }
      }
    }
  }

  // Nothing that day (or no calendars: the way to add one), centred
  ColumnLayout {
    visible: root.dayEvents.length === 0
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Widget.spacing

    // Filling the width too, so the column spans the pane and centres
    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true
    }
    EmptyState {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignHCenter
      icon: CalendarManager.hasCalendars ? "event_available" : "calendar_month"
      text: CalendarManager.hasCalendars ? I18n.tr("Nothing on this day") : I18n.tr("No calendars yet: add an account in Settings")
    }
    StyledTextButton {
      visible: !root.readOnly && !CalendarManager.hasCalendars
      Layout.alignment: Qt.AlignHCenter
      text: I18n.tr("Calendar settings")
      iconText: "chevron_right"
      iconAfter: true
      onClicked: SettingsManager.openSetting("Calendar", true)
    }
    // Filling the width too, so the column spans the pane and centres
    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true
    }
  }
}
