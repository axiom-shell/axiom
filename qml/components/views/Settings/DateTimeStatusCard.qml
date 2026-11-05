pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services.system
import qs.components.reusable
import qs.components.forms

// Settings page, System › Date & time (the DateTime section's `x-card`):
// the machine's clock (DateTimeManager, timedated): the time now in the
// formats below, the time zone, network time and setting the time by
// hand while it's off. Each change asks polkit
FieldGroup {
  id: root

  // The time typed while network time is off, "" until edited
  property string typedDate: ""
  property string typedTime: ""

  readonly property string syncLabel: {
    if (!DateTimeManager.available)
      return I18n.tr("No timedated");
    if (DateTimeManager.ntp)
      return DateTimeManager.ntpSynchronized ? I18n.tr("Synchronized") : I18n.tr("Synchronizing…");
    return I18n.tr("Set by hand");
  }

  // The typed date and time as one moment, or null while they don't read
  // as yyyy-MM-dd and HH:mm
  readonly property var typedMoment: {
    const d = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(root.typedDate.trim());
    const t = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(root.typedTime.trim());
    if (!d || !t)
      return null;
    const at = new Date(Number(d[1]), Number(d[2]) - 1, Number(d[3]), Number(t[1]), Number(t[2]), Number(t[3] ?? 0));
    return isNaN(at.getTime()) || at.getMonth() !== Number(d[2]) - 1 ? null : at;
  }

  function startEditing() {
    root.typedDate = I18n.formatDate(clock.date, "yyyy-MM-dd");
    root.typedTime = I18n.formatDate(clock.date, "HH:mm");
    dateEntry.text = root.typedDate;
    timeEntry.text = root.typedTime;
  }

  Component.onCompleted: DateTimeManager.refresh()

  SystemClock {
    id: clock
    precision: SystemClock.Seconds
  }

  headerExtras: [
    StatusChip {
      text: root.syncLabel
      color: !DateTimeManager.available ? Theme.foregroundAlt : DateTimeManager.ntp ? (DateTimeManager.ntpSynchronized ? Theme.success : Theme.warning) : Theme.accent
    }
  ]

  // --- Now ---

  ColumnLayout {
    Layout.fillWidth: true
    spacing: 0

    StyledText {
      text: I18n.formatDate(clock.date, I18n.clockFormat("default", true))
      textSize: Appearance.fontSizeBy(14)
      font.weight: Font.Medium
      textFamily: "monospace"
    }

    StyledText {
      text: I18n.formatDate(clock.date, I18n.dateFormat("fullDate"))
      textColor: Theme.foregroundAlt
    }
  }

  StyledText {
    visible: !DateTimeManager.available
    Layout.fillWidth: true
    text: I18n.tr("The time zone and clock are set through systemd-timedated, which isn't answering here.")
    textColor: Theme.foregroundAlt
    textSize: Appearance.fontSizeBy(-1)
    wrapMode: Text.WordWrap
  }

  // --- Time zone ---

  ColumnLayout {
    visible: DateTimeManager.available
    Layout.fillWidth: true
    spacing: Widget.spacing

    FieldHeader {
      // I18n.tr("Time zone")
      label: "Time zone"
      // I18n.tr("Where the clocks are set for. Search by city or region.")
      description: "Where the clocks are set for. Search by city or region."
    }

    StyledComboEntry {
      id: zoneEntry
      Layout.fillWidth: true
      editable: true
      icon: "public"
      enabled: !DateTimeManager.busy
      value: DateTimeManager.timezone
      placeholderText: I18n.tr("UTC")
      options: TimeZoneManager.zones.map(zone => ({
            "value": zone,
            "label": zone.replace(/_/g, " ")
          }))
      onPicked: value => {
        if (value !== DateTimeManager.timezone)
          DateTimeManager.setTimezone(value);
      }
    }
  }

  // --- Network time ---

  RowLayout {
    visible: DateTimeManager.available
    Layout.fillWidth: true
    spacing: Widget.spacing

    FieldHeader {
      // I18n.tr("Set the time automatically")
      label: "Set the time automatically"
      // I18n.tr("Keeps the clock right from time servers on the internet (systemd-timesyncd or another NTP service).")
      // I18n.tr("No time sync service is installed (systemd-timesyncd, chrony or ntpd).")
      description: DateTimeManager.canNtp ? "Keeps the clock right from time servers on the internet (systemd-timesyncd or another NTP service)." : "No time sync service is installed (systemd-timesyncd, chrony or ntpd)."
    }

    StyledSwitch {
      id: ntpSwitch
      enabled: DateTimeManager.canNtp && !DateTimeManager.busy
      checked: DateTimeManager.ntp
      onToggled: {
        DateTimeManager.setNtp(ntpSwitch.checked);
        // Follows timedated's answer, not the click
        ntpSwitch.checked = Qt.binding(() => DateTimeManager.ntp);
        if (!ntpSwitch.checked)
          root.startEditing();
      }
    }
  }

  // --- By hand, while network time is off ---

  ColumnLayout {
    visible: DateTimeManager.available && !DateTimeManager.ntp
    Layout.fillWidth: true
    spacing: Widget.spacing

    FieldHeader {
      // I18n.tr("Date and time")
      label: "Date and time"
      // I18n.tr("The date as year-month-day and the time on a 24-hour clock.")
      description: "The date as year-month-day and the time on a 24-hour clock."
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledTextEntry {
        id: dateEntry
        Layout.fillWidth: true
        placeholderText: "2026-11-05" // not translated: the format to type
        onTextEdited: root.typedDate = dateEntry.text
        onAccepted: setButton.clicked()
      }

      StyledTextEntry {
        id: timeEntry
        Layout.preferredWidth: Widget.px(90)
        placeholderText: "13:30" // not translated: the format to type
        onTextEdited: root.typedTime = timeEntry.text
        onAccepted: setButton.clicked()
      }

      StyledTextButton {
        id: setButton
        text: I18n.tr("Set")
        enabled: root.typedMoment !== null && !DateTimeManager.busy
        onClicked: DateTimeManager.setTime(root.typedMoment)
      }
    }
  }

  StyledText {
    visible: DateTimeManager.localRtc
    Layout.fillWidth: true
    text: I18n.tr("The hardware clock keeps local time (as Windows does), so a dual boot shows the same time in both.")
    textColor: Theme.foregroundAlt
    textSize: Appearance.fontSizeBy(-1)
    wrapMode: Text.WordWrap
  }

  StyledText {
    visible: DateTimeManager.error !== ""
    Layout.fillWidth: true
    text: DateTimeManager.error
    textColor: Theme.error
    textSize: Appearance.fontSizeBy(-1)
    wrapMode: Text.WordWrap
  }
}
