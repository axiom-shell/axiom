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
// (TimeZoneManager), the system's until its offset is read.
BarWidget {
  id: root

  readonly property bool japanese: I18n.language === "ja"
  readonly property bool use24Hour: properties.use24Hour
  readonly property bool showSeconds: properties.showSeconds
  readonly property bool showDate: properties.showDate
  readonly property color foregroundColor: colors.text

  readonly property int priority: 5

  hasBackground: true
  accentColor: Theme.resolveColor(properties.backgroundColor)

  implicitWidth: isVertical ? root.barConfig.widgetSize : (layoutLoader.item ? layoutLoader.item.implicitWidth + root.barConfig.widgetPadding * 2 : 0)
  implicitHeight: isVertical ? (layoutLoader.item ? layoutLoader.item.implicitHeight + root.barConfig.widgetPadding * 2 : 0) : root.barConfig.widgetSize

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
    return I18n.formatDate(date, I18n.dateFormat((use24Hour ? "clock24" : "clock12") + (showSeconds ? "s" : "")));
  }
  readonly property string dateText: I18n.formatDate(root.now, properties.dateFormat || I18n.dateFormat("mediumDate"))

  // Stacked lines for a vertical bar: [{ text, scale, bold, opacity }]
  readonly property var timeLines: {
    const date = root.now;
    if (properties.timeFormat)
      return _split(timeText);
    if (japanese) {
      const lines = [];
      if (!use24Hour)
        lines.push(_line(I18n.meridiem(date), 0.7, false, 0.9));
      // Number over its unit; the units are dictionary entries
      lines.push(_line(I18n.formatDate(date, use24Hour ? "H" : "h") + "\n" + I18n.tr("hour")));
      lines.push(_line(I18n.formatDate(date, "mm") + "\n" + I18n.tr("minute")));
      if (showSeconds)
        lines.push(_line(I18n.formatDate(date, "ss") + "\n" + I18n.tr("second")));
      return lines;
    }
    // Hours and minutes alike, the rest smaller and muted
    const lines = [_line(I18n.formatDate(date, use24Hour ? "HH" : "hh.ap").replace(/\.(am|pm)$/i, ""), 1, true), _line(I18n.formatDate(date, "mm"), 1, true)];
    if (showSeconds)
      lines.push(_line(I18n.formatDate(date, "ss"), 0.75, false, 0.75));
    if (!use24Hour)
      lines.push(_line(I18n.formatDate(date, "ap"), 0.6, false, 0.75, true));
    return lines;
  }
  readonly property var dateLines: {
    const date = root.now;
    if (properties.dateFormat)
      return _split(dateText);
    if (japanese)
      return [_line(I18n.formatDate(date, "M") + "\n" + I18n.tr("month")), _line(I18n.formatDate(date, "d") + "\n" + I18n.tr("day")), _line(I18n.locale.dayName(date.getDay(), Locale.NarrowFormat))];
    const day = _line(I18n.formatDate(date, "dd"), 0.75, true, 0.75);
    const weekday = _line(I18n.formatDate(date, "ddd"), 0.6, false, 0.75, true);
    switch (properties.verticalDate) {
    case "monthDay":
      return [_line(I18n.formatDate(date, "MMM"), 0.6, false, 0.75, true), day, weekday];
    case "numeric":
      return [day, _line(I18n.formatDate(date, "MM"), 0.75, true, 0.75)];
    default:
      return [day, weekday];
    }
  }

  function _line(text, scale = 1, bold = false, opacity = 1, caps = false) {
    return {
      "text": text,
      "scale": scale,
      "bold": bold,
      "opacity": opacity,
      "caps": caps
    };
  }

  // A custom format's output, one word (or colon-separated field) per line
  function _split(text) {
    return text.split(/[\s:]+/).filter(part => part !== "").map(part => _line(part));
  }

  component ClockText: Text {
    color: root.foregroundColor
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
    spacing: root.japanese ? 2 : 0

    // Modelled by count, not by the line objects: those are rebuilt on
    // every clock tick, which would recreate the delegates each time
    Repeater {
      model: stack.lines.length

      delegate: ClockText {
        required property int index
        readonly property var line: stack.lines[index] ?? root._line("")
        x: Math.round((stack.width - width) / 2)
        horizontalAlignment: Text.AlignHCenter
        lineHeight: 0.9
        text: line.text
        font.pixelSize: root.barConfig.fontSize * line.scale
        font.bold: line.bold
        font.capitalization: line.caps ? Font.AllUppercase : Font.MixedCase
        font.letterSpacing: line.caps ? 0.5 : 0
        opacity: line.opacity
      }
    }
  }

  Loader {
    id: layoutLoader
    anchors.centerIn: parent
    sourceComponent: root.isVertical ? verticalComponent : horizontalComponent

    Component {
      id: horizontalComponent
      Row {
        spacing: root.barConfig.widgetSpacing * 2

        ClockText {
          text: root.dateText
          visible: root.showDate
        }

        Rectangle {
          width: 1
          height: root.barConfig.fontSize
          color: root.foregroundColor
          opacity: 0.5
          visible: root.showDate
          anchors.verticalCenter: parent.verticalCenter
        }

        ClockText {
          text: root.timeText
        }
      }
    }

    Component {
      id: verticalComponent
      // A gap, not a rule, between the time and the date
      Column {
        spacing: root.barConfig.widgetSpacing * 2

        LineStack {
          lines: root.timeLines
          anchors.horizontalCenter: parent.horizontalCenter
        }

        LineStack {
          lines: root.dateLines
          visible: root.showDate
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }
    }
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "Calendar"
    openDelay: 150
    active: EdgeMenusConfig.opensOwnPopout(root.properties)
  }
}
