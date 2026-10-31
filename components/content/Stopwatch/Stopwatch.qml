pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// The one-off timer and the stopwatch (StopwatchManager), one at a time
// under a Timer / Stopwatch switch: the Stopwatch widget's popout, or an
// overlay card. Timer: a CountdownTimer (type a duration or pick a
// preset; then a ring, pause, +1 min and reset, centred in the card and
// beside each other in a wide, short one). Stopwatch: the
// time in tenths, start-pause, lap and reset, and the laps. Compact, the
// time of whichever is going.
// properties (card): { mode: "auto" | "timer" | "stopwatch" }
Panel {
  id: root

  // Which shows: the switch's pick, else as configured, else whichever is
  // going (the timer first)
  property string picked: ""
  readonly property string mode: {
    if (root.picked !== "")
      return root.picked;
    const wanted = root.properties.mode ?? "auto";
    if (wanted !== "auto")
      return wanted;
    return !StopwatchManager.timerIdle || StopwatchManager.stopwatchIdle ? "timer" : "stopwatch";
  }
  readonly property bool timerMode: root.mode === "timer"

  spacing: Widget.spacing
  wantsKeyboardFocus: true
  implicitWidth: Math.max(Appearance.fontSize * 20, body.implicitWidth + margins * 2)
  maxImplicitHeight: Appearance.fontSize * 30
  // In a popout the laps grow away from the dial and its buttons, which
  // stay by the bar (Panel.growth)
  flips: true
  fullMinWidth: Appearance.fontSize * 11
  fullMinHeight: Appearance.fontSize * 10

  // Tenths only while the stopwatch shows
  function register() {
    StopwatchManager.acquire(root, root.timerMode ? 1000 : 100);
  }
  onTimerModeChanged: register()
  Component.onCompleted: register()
  Component.onDestruction: StopwatchManager.release(root)

  compactContent: CompactFigure {
    icon: !StopwatchManager.timerIdle ? "hourglass_top" : "timer_play"
    value: !StopwatchManager.timerIdle ? StopwatchManager.timerText : StopwatchManager.elapsedText
    label: !StopwatchManager.timerIdle ? (StopwatchManager.timer.label || I18n.tr("Timer")) : I18n.tr("Stopwatch")
  }

  SegmentRow {
    Layout.fillWidth: true

    SegmentButton {
      text: I18n.tr("Timer")
      active: root.timerMode
      onClicked: root.picked = "timer"
    }
    SegmentButton {
      text: I18n.tr("Stopwatch")
      active: !root.timerMode
      onClicked: root.picked = "stopwatch"
    }
  }

  // -- Timer --

  CountdownTimer {
    visible: root.timerMode
    timer: StopwatchManager.timer
    presets: StopwatchConfig.presets
    text: StopwatchManager.timerText
    progress: StopwatchManager.timerProgress
    label: StopwatchManager.timer.label
    fill: root.embedded
    onStarted: text => StopwatchManager.startTimerText(text)
    onToggled: StopwatchManager.toggleTimer()
    onReset: StopwatchManager.resetTimer()
    onExtended: ms => StopwatchManager.addTimer(ms)
  }

  // -- Stopwatch --

  StyledText {
    visible: !root.timerMode
    Layout.alignment: Qt.AlignHCenter
    text: StopwatchClock.format(StopwatchManager.elapsed, true, false)
    textSize: Math.round(Appearance.fontSize * 2.4)
    font.bold: true
    font.features: {
      "tnum": 1
    }
    textColor: StopwatchManager.stopwatchRunning ? Theme.foreground : Theme.foregroundAlt
  }

  RowLayout {
    visible: !root.timerMode
    Layout.alignment: Qt.AlignHCenter
    spacing: Widget.spacing

    FlatIconButton {
      size: Math.round(Appearance.fontSize * 2)
      iconText: "restart_alt"
      enabled: !StopwatchManager.stopwatchIdle
      tooltipText: I18n.tr("Reset")
      onClicked: StopwatchManager.resetStopwatch()
    }
    FlatIconButton {
      size: Math.round(Appearance.fontSize * 2.6)
      iconText: StopwatchManager.stopwatchRunning ? "pause" : "play_arrow"
      iconColor: Theme.accentAlt
      tooltipText: StopwatchManager.stopwatchRunning ? I18n.tr("Pause") : I18n.tr("Start")
      onClicked: StopwatchManager.toggleStopwatch()
    }
    FlatIconButton {
      size: Math.round(Appearance.fontSize * 2)
      iconText: "flag"
      enabled: StopwatchManager.stopwatchRunning
      tooltipText: I18n.tr("Lap")
      onClicked: StopwatchManager.lap()
    }
  }

  Flickable {
    id: lapList
    visible: !root.timerMode && StopwatchManager.laps.length > 0
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    Layout.preferredHeight: root.embedded ? -1 : Math.min(laps.implicitHeight, Appearance.fontSize * 12)
    contentHeight: laps.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    ColumnLayout {
      id: laps
      width: lapList.width
      spacing: 2

      Repeater {
        model: StopwatchManager.laps.length
        RowLayout {
          id: lapRow
          required property int index
          readonly property var lap: StopwatchManager.laps[index] ?? {
            "number": 0,
            "split": 0,
            "total": 0
          }
          Layout.fillWidth: true
          spacing: Widget.spacing

          StyledText {
            Layout.fillWidth: true
            text: I18n.tr("Lap {0}", lapRow.lap.number)
            textColor: Theme.foregroundAlt
            textSize: Appearance.fontSizeBy(-1)
          }
          StyledText {
            text: StopwatchClock.format(lapRow.lap.split, true, false)
            textSize: Appearance.fontSizeBy(-1)
          }
          StyledText {
            Layout.preferredWidth: Appearance.fontSize * 5
            horizontalAlignment: Text.AlignRight
            text: StopwatchClock.format(lapRow.lap.total, true, false)
            textColor: Theme.foregroundAlt
            textSize: Appearance.fontSizeBy(-1)
          }
        }
      }
    }
  }

  Item {
    visible: root.embedded && !root.timerMode && StopwatchManager.laps.length === 0
    Layout.fillHeight: true
  }
}
