pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.components.methods
import qs.components.reusable

// A countdown to start and run, for the one-off timer (Stopwatch) and
// caffeine (Caffeine), so both look the same. Idle: a duration to type
// ("10m tea") and the `presets` (StopwatchClock.parse's text), plus the last
// duration again; set: a TimeRing with the time left, and reset, pause or
// resume and more time. The owner keeps the state (StopwatchClock's timer)
// and acts on the signals.
ColumnLayout {
  id: root

  // StopwatchClock's timer state
  required property var timer
  required property var presets
  // The time left, how far it's gone (0–1)
  property string text: ""
  property real progress: 0
  // The ring's label while it runs
  property string label: ""
  property real dialSize: Appearance.fontSize * 9
  // Fills its height (an overlay card), the idle part on top
  property bool fill: false
  property color color: Theme.accent
  // The more-time button's ms, and its tooltip
  property real moreTime: 60000
  property string moreTimeText: I18n.tr("One more minute")
  property string resetText: I18n.tr("Reset")

  readonly property bool idle: StopwatchClock.timerIdle(root.timer)

  // Text StopwatchClock.parse reads as a duration
  signal started(string text)
  // Pause ↔ resume; idle, the last duration again
  signal toggled
  signal reset
  signal extended(real ms)

  Layout.fillWidth: true
  Layout.fillHeight: root.fill && root.idle
  spacing: Widget.spacing

  // Set: the ring with the time left
  TimeRing {
    visible: !root.idle
    size: root.dialSize
    progress: root.progress
    text: root.text
    color: root.color
    label: root.timer.running ? root.label : I18n.tr("Paused")
    running: root.timer.running
  }

  RowLayout {
    visible: !root.idle
    Layout.alignment: Qt.AlignHCenter
    spacing: Widget.spacing

    FlatIconButton {
      size: Math.round(Appearance.fontSize * 2)
      iconText: "stop"
      tooltipText: root.resetText
      onClicked: root.reset()
    }
    FlatIconButton {
      size: Math.round(Appearance.fontSize * 2.6)
      iconText: root.timer.running ? "pause" : "play_arrow"
      iconColor: root.color
      tooltipText: root.timer.running ? I18n.tr("Pause") : I18n.tr("Resume")
      onClicked: root.toggled()
    }
    FlatIconButton {
      size: Math.round(Appearance.fontSize * 2)
      iconText: "more_time"
      tooltipText: root.moreTimeText
      onClicked: root.extended(root.moreTime)
    }
  }

  // Not set: a duration to type, or a preset
  StyledTextEntry {
    id: durationField
    visible: root.idle
    Layout.fillWidth: true
    Layout.preferredHeight: Widget.height
    placeholderText: I18n.tr("10m, 1h30m, 90s, 10m tea…")
    onAccepted: {
      if (StopwatchClock.parse(durationField.text).ms <= 0)
        return;
      root.started(durationField.text);
      durationField.text = "";
    }
  }

  Flow {
    visible: root.idle
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    Repeater {
      model: root.presets.length
      StyledTextButton {
        required property int index
        readonly property string preset: root.presets[index] ?? ""
        implicitHeight: Widget.height - Widget.px(4)
        text: preset
        onClicked: root.started(preset)
      }
    }
    StyledTextButton {
      visible: root.timer.duration > 0
      implicitHeight: Widget.height - Widget.px(4)
      iconText: "replay"
      text: StopwatchClock.format(root.timer.duration, false, true)
      onClicked: root.toggled()
    }
  }

  Item {
    visible: root.fill && root.idle
    Layout.fillHeight: true
  }
}
