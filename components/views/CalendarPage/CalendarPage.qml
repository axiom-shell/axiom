pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts.calendar
import qs.components.views.base

// The Calendar page: the month large, each day's events in it where they
// fit, and beside it the selected day's events (opening in the editor)
// over the calendars, which switch on and off here. The page the
// launcher's /calendar, the `calendar` IPC and reminders open.
BaseView {
  id: root

  property string selectedKey: CalendarEvents.dayKey(new Date())
  readonly property real sideColumnWidth: root.grid.unit * 1.05
  readonly property real monthWidth: Math.max(root.grid.unit * 1.6, Math.min(root.grid.unit * 3, root.grid.roomWidth - root.sideColumnWidth - OverlayConfig.cardSpacing * 3))

  Component.onCompleted: {
    CalendarManager.acquire(root);
    root._takeRequest();
  }
  Component.onDestruction: CalendarManager.release(root)

  function _takeRequest() {
    const request = CalendarManager.takeRequest();
    if (!request)
      return;
    root.selectedKey = request.key;
    month.showDay(request.key);
    if (request.kind === "new")
      Qt.callLater(pane.newEvent);
  }
  Connections {
    target: CalendarManager
    function onRequestChanged() {
      if (CalendarManager.request)
        root._takeRequest();
    }
  }

  // Shows or hides one calendar, saved at once
  function setShown(calendar, shown) {
    const accounts = Utils.clone(CalendarConfig.savedAccounts);
    const index = CalendarConfig.accounts.findIndex(account => account.id === calendar.account);
    const entry = accounts[index]?.calendars?.find(c => c.href === calendar.href);
    if (!entry)
      return;
    entry.enabled = shown;
    SettingsManager.commitValues({
      "Calendar.items": accounts
    });
  }

  Item {
    implicitWidth: root.monthWidth
    implicitHeight: root.pageHeight

    Card {
      id: monthCard
      slotRect: [0, 0, 12, 8]

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: monthCard.pad
        spacing: Widget.spacing

        RowLayout {
          Layout.fillWidth: true
          spacing: Widget.spacing / 2

          StyledIcon {
            text: "calendar_month"
            textColor: Theme.accent
            textSize: Appearance.fontSizeBy(4)
          }
          StyledText {
            text: I18n.formatDate(new Date(month.year, month.month, 1), I18n.dateFormat("monthYear"))
            textSize: Appearance.fontSizeBy(4)
            font.bold: true
          }
          Item {
            Layout.fillWidth: true
          }
          StyledText {
            text: CalendarManager.syncing ? I18n.tr("Syncing…") : CalendarManager.lastSync > 0 ? I18n.tr("Synced {0}", I18n.formatDate(new Date(CalendarManager.lastSync), CalendarConfig.timeFormat)) : ""
            textColor: Theme.foregroundAlt
            textSize: Appearance.fontSizeBy(-2)
          }
          FlatIconButton {
            visible: CalendarManager.hasCalendars
            iconText: "sync"
            tooltipText: I18n.tr("Sync now")
            enabled: !CalendarManager.syncing
            onClicked: CalendarManager.sync()
          }
          StyledTextButton {
            text: I18n.tr("Today")
            onClicked: {
              month.showToday();
              root.selectedKey = month.todayKey;
            }
          }
          FlatIconButton {
            iconText: "chevron_left"
            onClicked: month.step(-1)
          }
          FlatIconButton {
            iconText: "chevron_right"
            onClicked: month.step(1)
          }
        }

        MonthGrid {
          id: month
          Layout.fillWidth: true
          Layout.fillHeight: true
          showHeader: false
          titles: true
          weekdayHeight: Appearance.fontSize * 1.8
          selectedKey: root.selectedKey
          onDaySelected: key => root.selectedKey = key
        }
      }
    }
  }

  Item {
    implicitWidth: root.sideColumnWidth
    implicitHeight: root.pageHeight

    Card {
      id: sideCard
      slotRect: [0, 0, 4, 8]

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: sideCard.pad
        spacing: Widget.spacing

        DayPane {
          id: pane
          Layout.fillWidth: true
          Layout.fillHeight: true
          dayKey: root.selectedKey
        }

        // The calendars, switched on and off here (Settings has the rest)
        ColumnLayout {
          visible: !pane.editing && CalendarManager.calendars.length > 0
          Layout.fillWidth: true
          Layout.maximumHeight: root.pageHeight * 0.4
          spacing: 2

          StyledSeparator {
            Layout.fillWidth: true
          }
          RowLayout {
            Layout.fillWidth: true
            StyledText {
              Layout.fillWidth: true
              text: I18n.tr("Calendars")
              font.bold: true
            }
            FlatIconButton {
              iconText: "settings"
              tooltipText: I18n.tr("Calendar settings")
              onClicked: SettingsManager.openSetting("Calendar", true)
            }
          }
          Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: calendarList.implicitHeight
            contentHeight: calendarList.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            ColumnLayout {
              id: calendarList
              width: parent.width
              spacing: 0

              Repeater {
                model: CalendarManager.calendars.filter(calendar => calendar.events)
                RowLayout {
                  id: calendarRow
                  required property var modelData
                  Layout.fillWidth: true
                  spacing: Widget.spacing

                  Rectangle {
                    Layout.preferredWidth: Appearance.fontSize * 0.7
                    Layout.preferredHeight: width
                    radius: width / 2
                    color: calendarRow.modelData.color
                    opacity: calendarRow.modelData.enabled ? 1 : 0.4
                  }
                  StyledText {
                    Layout.fillWidth: true
                    text: calendarRow.modelData.name
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    opacity: calendarRow.modelData.enabled ? 1 : 0.6
                  }
                  StyledSwitch {
                    checked: calendarRow.modelData.enabled
                    onToggled: root.setShown(calendarRow.modelData, checked)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
