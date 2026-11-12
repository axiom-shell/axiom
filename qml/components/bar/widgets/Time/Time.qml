pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

import qs.config
import qs.services.system
import qs.components.methods
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// Clock with a date, formatted for the shell's language (General.language:
// Japanese uses 午前/午後 and 時分秒 / 年月日); a custom `timeFormat` /
// `dateFormat` (Qt format strings) overrides that. On a vertical bar each
// is stacked into short lines. A `timezone` shows another zone's time
// (TimeZoneManager), the system's until its offset is read. A head
// (`lead`: an icon, or the date moved before the time; Auto: the date where
// the bar draws an icon part apart) is its icon part on a split bar
// (BarWidget's head). The clock is its own content; the lines after the
// first on a vertical bar and the divider are muted colors.
BarWidget {
  id: root

  readonly property bool japanese: I18n.language === "ja"
  // hourFormat: "default" (Settings › Date & time) | "12" | "24"
  readonly property bool use24Hour: I18n.hours24(properties.hourFormat)
  readonly property bool showSeconds: properties.showSeconds
  readonly property bool showDate: properties.showDate

  // The date as the head (only while it shows; Auto: where the bar's look
  // draws an icon part apart), else after the time
  readonly property bool dateLeads: (properties.lead === "date" || (properties.lead === "auto" && barConfig.look.traits.iconPart)) && showDate
  readonly property bool dateAfter: showDate && !dateLeads

  headIcon: root.properties.lead === "icon" ? root.properties.leadIcon : ""
  headText: root.dateLeads && !root.isVertical ? root.dateText : ""
  headItem: root.dateLeads && root.isVertical ? dateHead : null
  ownContent: root.isVertical ? verticalClock : horizontalClock

  // The date's stacked lines as the head on a vertical bar
  Loader {
    id: dateHead
    active: root.dateLeads && root.isVertical
    sourceComponent: Component {
      LineStack {
        lines: root.dateLines
        color: root.paint.headText
        mutedColor: root.paint.muted("headText")
      }
    }
  }

  SystemClock {
    id: clock
    precision: root.showSeconds || root.properties.timeFormat.includes("s") ? SystemClock.Seconds : SystemClock.Minutes
  }

  readonly property string timezone: properties.timezone
  onTimezoneChanged: TimeZoneManager.acquire(root, root.timezone)
  Component.onCompleted: TimeZoneManager.acquire(root, root.timezone)
  Component.onDestruction: TimeZoneManager.release(root)
  // The time shown, in the widget's zone
  readonly property date now: TimeZones.shift(clock.date, TimeZoneManager.offsetOf(root.timezone))

  // One-line time and date, for a horizontal bar
  readonly property string timeText: {
    const date = root.now;
    if (properties.timeFormat)
      return I18n.formatDate(date, properties.timeFormat);
    return I18n.formatDate(date, I18n.clockFormat(properties.hourFormat, showSeconds));
  }
  readonly property string dateText: I18n.formatDate(root.now, properties.dateFormat || I18n.dateFormat("mediumDate"))

  // Stacked lines for a vertical bar: [{ text, scale, bold, muted, caps }]
  readonly property var timeLines: {
    const date = root.now;
    if (properties.timeFormat)
      return _split(timeText);
    if (japanese) {
      const lines = [];
      if (!use24Hour)
        lines.push(_line(I18n.meridiem(date), 0.7));
      // Number over its unit; the units are dictionary entries
      lines.push(_line(I18n.formatHour(date, use24Hour, false) + "\n" + I18n.tr("hour")));
      lines.push(_line(I18n.formatDate(date, "mm") + "\n" + I18n.tr("minute")));
      if (showSeconds)
        lines.push(_line(I18n.formatDate(date, "ss") + "\n" + I18n.tr("second")));
      return lines;
    }
    // Hours and minutes alike, the rest smaller and muted
    const lines = [_line(I18n.formatHour(date, use24Hour, true), 1, true), _line(I18n.formatDate(date, "mm"), 1, true)];
    if (showSeconds)
      lines.push(_line(I18n.formatDate(date, "ss"), 0.75, false, true));
    if (!use24Hour)
      lines.push(_line(I18n.formatDate(date, "ap"), 0.6, false, true, true));
    return lines;
  }
  readonly property var dateLines: {
    const date = root.now;
    if (properties.dateFormat)
      return _split(dateText);
    if (japanese)
      return [_line(I18n.formatDate(date, "M") + "\n" + I18n.tr("month")), _line(I18n.formatDate(date, "d") + "\n" + I18n.tr("day")), _line(I18n.locale.dayName(date.getDay(), Locale.NarrowFormat))];
    const day = _line(I18n.formatDate(date, "dd"), 0.75, true, true);
    const weekday = _line(I18n.formatDate(date, "ddd"), 0.6, false, true, true);
    switch (properties.verticalDate) {
    case "monthDay":
      return [_line(I18n.formatDate(date, "MMM"), 0.6, false, true, true), day, weekday];
    case "numeric":
      return [day, _line(I18n.formatDate(date, "MM"), 0.75, true, true)];
    default:
      return [day, weekday];
    }
  }

  function _line(text, scale = 1, bold = false, muted = false, caps = false) {
    return {
      "text": text,
      "scale": scale,
      "bold": bold,
      "muted": muted,
      "caps": caps
    };
  }

  // A custom format's output, one field per line: split on spaces and
  // : / , and on . and - between digits, so 2026-10-30 and 30.10.2026 split
  // but a zone's sign (-03, GMT-3) and a.m. / p.m. stay whole
  function _split(text) {
    return text.replace(/(\d)[.\-](?=\d)/g, "$1 ").split(/[\s:\/,]+/).filter(part => part !== "").map(part => _line(part));
  }

  component ClockText: Text {
    color: root.paint.text
    font.family: Appearance.fontFamily
    font.pixelSize: root.barConfig.fontSize
    // Same-width digits, so the clock doesn't shift as it ticks
    font.features: {
      "tnum": 1
    }
  }

  component LineStack: Column {
    id: stack
    required property var lines
    property color color: root.paint.text
    property color mutedColor: root.paint.muted("text")
    spacing: root.japanese ? 2 : 0

    // Modelled by count, not by the line objects: those are rebuilt on
    // every clock tick, which would recreate the delegates each time
    Repeater {
      model: stack.lines.length

      delegate: ClockText {
        required property int index
        readonly property var line: stack.lines[index] ?? root._line("")
        color: line.muted ? stack.mutedColor : stack.color
        x: Math.round((stack.width - width) / 2)
        horizontalAlignment: Text.AlignHCenter
        lineHeight: 0.9
        text: line.text
        font.pixelSize: root.barConfig.fontSize * line.scale
        font.bold: line.bold
        font.capitalization: line.caps ? Font.AllUppercase : Font.MixedCase
        font.letterSpacing: line.caps ? 0.5 : 0
      }
    }
  }

  Component {
    id: horizontalClock
    Row {
      spacing: root.barConfig.innerGap * 2

      ClockText {
        text: root.dateText
        visible: root.dateAfter
      }

      Rectangle {
        width: 1
        height: root.barConfig.fontSize
        color: root.paint.muted("text")
        visible: root.dateAfter
        anchors.verticalCenter: parent.verticalCenter
      }

      ClockText {
        text: root.timeText
      }
    }
  }

  // A gap, not a rule, between the time and the date
  Component {
    id: verticalClock
    Column {
      spacing: root.barConfig.innerGap * 2

      LineStack {
        lines: root.timeLines
        anchors.horizontalCenter: parent.horizontalCenter
      }

      LineStack {
        lines: root.dateLines
        visible: root.dateAfter
        anchors.horizontalCenter: parent.horizontalCenter
      }
    }
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "Calendar"
    openDelay: 150
    active: MenusConfig.opensOwnPopout(root.properties)
  }
}
