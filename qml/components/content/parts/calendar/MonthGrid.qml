pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable

// A month of days (six weeks from the language's first weekday) with a dot
// for each calendar that has events on a day, or, with `titles` in cells
// tall enough, the events themselves. It owns the month shown (the arrows
// page it, the month's name goes back to today) and asks CalendarManager
// for months past its range. A click selects a day (`daySelected`); the
// owner sets `selectedKey`. Fills the height it's given.
Item {
  id: root

  property int year: clock.date.getFullYear()
  property int month: clock.date.getMonth()
  property string selectedKey: ""
  property bool showHeader: true
  // Events at all: off on the lock screen and the login screen
  property bool showEvents: true
  // Event titles in cells tall enough for one, instead of dots
  property bool titles: false
  property real headerHeight: Appearance.fontSize * 2
  property real weekdayHeight: Appearance.fontSize * 1.5
  readonly property real cellHeight: Math.max(1, (root.height - (root.showHeader ? root.headerHeight : 0) - root.weekdayHeight) / 6)

  signal daySelected(string key)

  implicitWidth: Appearance.fontSize * 16
  implicitHeight: (root.showHeader ? root.headerHeight : 0) + root.weekdayHeight + Appearance.fontSize * 2.1 * 6

  function step(delta) {
    const d = new Date(root.year, root.month + delta, 1);
    root._show(d.getFullYear(), d.getMonth());
  }

  // Shows the month holding `key` ("YYYY-MM-DD")
  function showDay(key) {
    const d = CalendarEvents.dateOf(key);
    root._show(d.getFullYear(), d.getMonth());
  }

  // A new month's days slide in from the side it lies on
  function _show(year, month) {
    const delta = (year - root.year) * 12 + month - root.month;
    root.year = year;
    root.month = month;
    if (delta === 0)
      return;
    daySlide.from = (delta > 0 ? 1 : -1) * Widget.spacing * 4;
    monthIn.restart();
  }

  // The day cells' slide and fade as a month comes in
  property real _dayShift: 0
  property real _dayOpacity: 1
  ParallelAnimation {
    id: monthIn
    NumberAnimation {
      id: daySlide
      target: root
      property: "_dayShift"
      to: 0
      duration: Appearance.animNormal
      easing.type: Appearance.easing
    }
    NumberAnimation {
      target: root
      property: "_dayOpacity"
      from: 0
      to: 1
      duration: Appearance.animNormal
      easing.type: Appearance.easing
    }
  }

  function showToday() {
    root.showDay(root.todayKey);
  }

  function _ensure() {
    if (root.showEvents)
      CalendarManager.ensureMonth(root.year, root.month);
  }
  onYearChanged: Qt.callLater(root._ensure)
  onMonthChanged: Qt.callLater(root._ensure)
  Component.onCompleted: root._ensure()

  SystemClock {
    id: clock
    precision: SystemClock.Hours
  }

  // Strings, so the grid only rebuilds when the day or month changes
  readonly property string today: clock.date.toDateString()
  readonly property string todayKey: CalendarEvents.dayKey(clock.date)
  readonly property int firstDay: I18n.locale.firstDayOfWeek % 7
  readonly property var days: Utils.monthGrid(root.year, root.month, root.firstDay, root.today)

  ColumnLayout {
    anchors.fill: parent
    spacing: 0

    RowLayout {
      visible: root.showHeader
      Layout.fillWidth: true
      Layout.preferredHeight: root.headerHeight
      spacing: Widget.spacing / 2

      StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: Widget.spacing / 2
        text: I18n.formatDate(new Date(root.year, root.month, 1), I18n.dateFormat("monthYear"))
        font.bold: true
        elide: Text.ElideRight
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.showToday()
        }
      }

      Repeater {
        model: [["chevron_left", -1], ["chevron_right", 1]]
        FlatIconButton {
          required property var modelData
          size: Math.round(root.headerHeight * 0.9)
          iconText: modelData[0]
          iconColor: Theme.accent
          iconSize: Appearance.fontSizeBy(2)
          onClicked: root.step(modelData[1])
        }
      }
    }

    GridLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      columns: 7
      rowSpacing: 0
      columnSpacing: 0
      uniformCellWidths: true

      Repeater {
        model: 7
        StyledText {
          required property int index
          Layout.fillWidth: true
          Layout.preferredHeight: root.weekdayHeight
          leftPadding: root.titles ? Widget.spacing : 0
          horizontalAlignment: root.titles ? Text.AlignLeft : Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: I18n.locale.dayName((root.firstDay + index) % 7, root.titles ? Locale.ShortFormat : Locale.NarrowFormat)
          textSize: Appearance.fontSizeBy(-2)
          opacity: 0.6
        }
      }

      // By count: paging a month updates the same 42 cells instead of
      // rebuilding them
      Repeater {
        model: 42

        // Each cell streamed in (StreamedLoader) as a page opens
        StreamedLoader {
          id: cellLoader
          required property int index
          Layout.fillWidth: true
          Layout.preferredHeight: root.cellHeight
          label: "calendar day"

          sourceComponent: Item {
            id: cell
            readonly property int index: cellLoader.index
            readonly property var modelData: root.days[cell.index]
            readonly property string key: cell.modelData.key
            readonly property bool selected: cell.key === root.selectedKey
            readonly property real numberSize: Appearance.fontSize * 1.5
            // Titles: the number's inset, clear of the cell's rounded border
            readonly property real inset: Math.max(4, Widget.radius / 2 + 2)
            // Titles: as many lines as fit under the day's number
            readonly property real lineHeight: Appearance.fontSize * 1.25
            readonly property int lines: root.titles ? Math.floor((cell.height - cell.inset * 2 - cell.numberSize - 2) / (cell.lineHeight + 1)) : 0
            readonly property bool showTitles: root.showEvents && cell.lines >= 1
            readonly property var dayEvents: cell.showTitles ? CalendarManager.eventsOn(cell.key) : []
            // All of them when they fit, else one line fewer and "+n more"
            readonly property int shownCount: cell.dayEvents.length <= cell.lines ? cell.dayEvents.length : Math.max(0, cell.lines - 1)
            // A joined key, so the dots rebuild only when they change
            readonly property string dotKey: root.showEvents && !cell.showTitles ? CalendarManager.dotsFor(cell.key).join(",") : ""

            opacity: root._dayOpacity
            transform: Translate {
              x: root._dayShift
            }

            // Hover and selection
            Rectangle {
              anchors.fill: parent
              anchors.margins: 1
              visible: root.titles
              radius: Widget.radius
              color: cell.selected ? Theme.backgroundHighlight : cellArea.containsMouse ? Qt.alpha(Theme.backgroundHighlight, 0.5) : "transparent"
              border.color: cell.selected ? Theme.accent : "transparent"
              border.width: cell.selected ? 1 : 0
            }
            Rectangle {
              visible: !root.titles
              anchors.centerIn: parent
              width: Math.min(parent.width, parent.height, Appearance.fontSize * 2.6) * 0.9
              height: width
              radius: width / 2
              color: cell.modelData.isToday ? Theme.accent : cell.selected ? Theme.backgroundHighlight : cellArea.containsMouse ? Qt.alpha(Theme.backgroundHighlight, 0.5) : "transparent"
              border.color: cell.selected && !cell.modelData.isToday ? Theme.accent : "transparent"
              border.width: cell.selected ? 1 : 0
            }

            // The day's number: centred, or top-left in a cell with titles
            Rectangle {
              id: number
              x: root.titles ? cell.inset : (cell.width - width) / 2
              y: root.titles ? cell.inset : (cell.height - height) / 2 - (cell.dotKey ? cell.height * 0.08 : 0)
              width: root.titles ? Math.max(cell.numberSize, numberText.implicitWidth + Widget.spacing * 2) : numberText.implicitWidth
              height: root.titles ? cell.numberSize : numberText.implicitHeight
              radius: height / 2
              color: root.titles && cell.modelData.isToday ? Theme.accent : "transparent"

              StyledText {
                id: numberText
                anchors.centerIn: parent
                text: cell.modelData.day
                textColor: cell.modelData.isToday ? Theme.background : Theme.foreground
                font.bold: cell.modelData.isToday
                opacity: cell.modelData.inMonth ? 1 : 0.35
                textSize: Appearance.fontSizeBy(-1)
              }
            }

            // Dots: one per calendar with events that day
            Row {
              visible: cell.dotKey !== ""
              anchors.horizontalCenter: parent.horizontalCenter
              y: Math.min(cell.height - 5, number.y + number.height + 1)
              spacing: 2
              opacity: cell.modelData.inMonth ? 1 : 0.5

              Repeater {
                model: cell.dotKey ? cell.dotKey.split(",") : []
                Rectangle {
                  required property string modelData
                  width: Math.max(Widget.px(3), Appearance.fontSize * 0.28)
                  height: width
                  radius: width / 2
                  color: cell.modelData.isToday && !root.titles ? Theme.background : modelData
                }
              }
            }

            // Titles: the events that fit, then "+n more"
            Column {
              visible: cell.showTitles
              // Clear of the cell's rounded border, like the number
              x: cell.inset
              y: number.y + cell.numberSize + 2
              width: cell.width - cell.inset * 2
              spacing: 1
              opacity: cell.modelData.inMonth ? 1 : 0.5

              Repeater {
                model: cell.shownCount
                Rectangle {
                  id: chip
                  required property int index
                  readonly property var event: cell.dayEvents[index] ?? null
                  readonly property color calendarColor: CalendarManager.colors[chip.event?.calendar] ?? Theme.accent
                  width: parent?.width ?? 0
                  height: cell.lineHeight
                  radius: Widget.radius / 2
                  color: chip.event?.allDay ? Qt.alpha(chip.calendarColor, 0.3) : "transparent"

                  Rectangle {
                    visible: !chip.event?.allDay
                    x: 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: Widget.px(3)
                    height: parent.height - Widget.px(4)
                    radius: 1.5
                    color: chip.calendarColor
                  }
                  StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Widget.px(chip.event?.allDay ? 4 : 8)
                    width: parent.width - x - 2
                    text: chip.event ? (chip.event.allDay || CalendarEvents.spanOn(chip.event, cell.key) !== "single" && CalendarEvents.spanOn(chip.event, cell.key) !== "starts" ? "" : I18n.formatDate(new Date(chip.event.start), CalendarConfig.timeFormat) + " ") + (chip.event.title || I18n.tr("(No title)")) : ""
                    elide: Text.ElideRight
                    textSize: Appearance.fontSizeBy(-3)
                  }
                }
              }
              StyledText {
                visible: cell.dayEvents.length > cell.shownCount
                x: 4
                text: I18n.tr("+{0} more", cell.dayEvents.length - cell.shownCount)
                textSize: Appearance.fontSizeBy(-3)
                textColor: Theme.foregroundAlt
              }
            }

            MouseArea {
              id: cellArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.daySelected(cell.key)
            }
          }
        }
      }
    }
  }
}
