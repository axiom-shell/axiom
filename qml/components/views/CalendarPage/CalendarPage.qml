pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.config
import qs.services.ui
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts.calendar
import qs.components.views.base
import qs.components.forms

// The Calendar page: the month large, each day's events in it where they
// fit, and beside it the selected day's events (opening in the editor)
// over the calendars, which switch on and off here. The page the
// launcher's /calendar, the `calendar` IPC and reminders open. It pops out
// into a window, so the day, month and event editor are kept in
// CalendarManager.page, never here.
BaseView {
  id: root

  readonly property CalendarPageState pageState: CalendarManager.page
  readonly property real sideColumnWidth: root.grid.unit * 1.05
  // The page is pageWidth wide like every tool page
  readonly property real monthWidth: Math.max(root.grid.unit * 1.6, root.pageWidth - root.sideColumnWidth - OverlayConfig.cardSpacing)

  Component.onCompleted: {
    CalendarManager.acquire(root);
    root._takeRequest();
  }
  Component.onDestruction: CalendarManager.release(root)

  function _takeRequest() {
    if (CalendarManager.request?.page !== "CalendarPage")
      return;
    const request = CalendarManager.takeRequest();
    root.pageState.select(request.key);
    root.pageState.showDay(request.key);
    if (request.kind === "new")
      Qt.callLater(pane.newEvent);
  }
  Connections {
    target: CalendarManager
    function onRequestChanged() {
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

        // The month name changes width: Sync, Today and the arrows sit at the row's end, so stepping months never moves them
        RowLayout {
          Layout.fillWidth: true
          spacing: Widget.spacing / 2

          CardHeader {
            icon: "calendar_month"
            iconSize: "lg"
            title: I18n.formatDate(new Date(root.pageState.year, root.pageState.month, 1), I18n.dateFormat("monthYear"))
            showActions: false

            StyledLabel {
              text: CalendarManager.syncing ? I18n.tr("Syncing…") : CalendarManager.lastSync > 0 ? I18n.tr("Synced {0}", I18n.formatDate(new Date(CalendarManager.lastSync), CalendarConfig.timeFormat)) : ""
              role: "caption"
              tone: "muted"
            }
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
            onClicked: root.pageState.goToday()
          }
          FlatIconButton {
            iconText: "chevron_left"
            onClicked: root.pageState.step(-1)
          }
          FlatIconButton {
            iconText: "chevron_right"
            onClicked: root.pageState.step(1)
          }
        }

        MonthGrid {
          Layout.fillWidth: true
          Layout.fillHeight: true
          showHeader: false
          titles: true
          weekdayHeight: Appearance.fontSize * 1.8
          year: root.pageState.year
          month: root.pageState.month
          selectedKey: root.pageState.selectedKey
          onDaySelected: key => root.pageState.select(key)
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
          dayKey: root.pageState.selectedKey
          session: root.pageState.draft
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
          ListSection {
            title: I18n.tr("Calendars")
            trailing: FlatIconButton {
              iconText: "settings"
              tooltipText: I18n.tr("Calendar settings")
              onClicked: SettingsManager.openSetting("Calendar", true)
            }

            Flickable {
              Layout.fillWidth: true
              Layout.preferredHeight: Math.min(calendarList.implicitHeight, root.pageHeight * 0.4 - Widget.height * 2)
              contentHeight: calendarList.implicitHeight
              boundsBehavior: Flickable.StopAtBounds
              clip: true
              ScrollIndicator.vertical: StyledScrollIndicator {}

              FormColumn {
                id: calendarList
                width: parent.width

                Repeater {
                  id: calendarRepeater
                  readonly property var calendars: CalendarManager.calendars.filter(calendar => calendar.events)
                  model: calendars.length

                  SwitchRow {
                    id: calendarRow
                    required property int index
                    readonly property var calendar: calendarRepeater.calendars[index] ?? ({})

                    label: calendarRow.calendar.name
                    plainLabel: true
                    dimmed: !calendarRow.calendar.enabled
                    checked: calendarRow.calendar.enabled
                    onToggled: on => root.setShown(calendarRow.calendar, on)

                    leading: Rectangle {
                      implicitWidth: Appearance.fontSize * 0.7
                      implicitHeight: implicitWidth
                      radius: width / 2
                      color: Style.resolve(calendarRow.calendar.color)
                      opacity: calendarRow.calendar.enabled ? 1 : Style.opacityDisabled
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
}
