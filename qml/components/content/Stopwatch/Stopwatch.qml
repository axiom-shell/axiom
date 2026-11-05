pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.apps
import qs.services.system
import qs.components.methods
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// The one-off timer and the stopwatch (StopwatchManager), one at a time
// under a Timer / Stopwatch switch: the Stopwatch widget's popout, or an
// overlay card. Timer: a CountdownTimer (type a duration or a time of
// day, or pick a preset or a recent one; then a ring, pause, more time and
// reset, centred in the card and beside each other in a wide, short one).
// Stopwatch: DialControls with the time in tenths and the minute swept
// round, reset, start-pause and lap, then the laps (copyable, the fastest
// and slowest tinted). Compact, the time of whichever is going.
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

  Loader {
    active: root.timerMode
    visible: active
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    Layout.preferredHeight: root.embedded ? 0 : -1

    sourceComponent: CountdownTimer {
      timer: StopwatchManager.timer
      presets: StopwatchConfig.presets
      recent: StopwatchManager.recent
      text: StopwatchManager.timerText
      remaining: StopwatchManager.timerRemaining
      progress: StopwatchManager.timerProgress
      label: StopwatchManager.timer.label
      fill: root.embedded
      onStarted: timer => StopwatchManager.startTimer(timer.ms, timer.label, timer.clock === true)
      onToggled: StopwatchManager.toggleTimer()
      onReset: StopwatchManager.resetTimer()
      onExtended: ms => StopwatchManager.addTimer(ms)
    }
  }

  // -- Stopwatch --

  Loader {
    active: !root.timerMode
    visible: active
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    // Filling: whatever is left (the laps get their share), never what
    // the ring asks (it's sized from it)
    Layout.preferredHeight: root.embedded ? 0 : -1

    sourceComponent: DialControls {
      fill: root.embedded
      // The current minute, swept round
      progress: StopwatchManager.elapsed % 60000 / 60000
      text: StopwatchClock.format(StopwatchManager.elapsed, true, false)
      label: StopwatchManager.stopwatchIdle ? "" : !StopwatchManager.stopwatchRunning ? I18n.tr("Paused") : StopwatchManager.laps.length > 0 ? I18n.tr("Lap {0}", StopwatchManager.laps.length + 1) : ""
      running: StopwatchManager.stopwatchRunning
      color: Theme.accentAlt
      tick: 100
      leftIcon: "restart_alt"
      leftTip: I18n.tr("Reset")
      leftEnabled: !StopwatchManager.stopwatchIdle
      mainIcon: StopwatchManager.stopwatchRunning ? "pause" : "play_arrow"
      mainTip: StopwatchManager.stopwatchRunning ? I18n.tr("Pause") : I18n.tr("Start")
      rightIcon: "flag"
      rightTip: I18n.tr("Lap")
      rightEnabled: StopwatchManager.stopwatchRunning
      rightKey: Qt.Key_L
      onLeftClicked: StopwatchManager.resetStopwatch()
      onMainClicked: StopwatchManager.toggleStopwatch()
      onRightClicked: StopwatchManager.lap()
    }
  }

  // The laps: a heading with copy, then the latest first, the fastest and
  // slowest tinted
  RowLayout {
    visible: !root.timerMode && StopwatchManager.laps.length > 0
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledText {
      Layout.fillWidth: true
      text: I18n.tr("Laps")
      font.bold: true
      textSize: Appearance.fontSizeBy(-1)
    }
    FlatIconButton {
      size: Math.round(Appearance.fontSize * 1.6)
      iconSize: Appearance.fontSizeBy(-1)
      iconText: "content_copy"
      tooltipText: I18n.tr("Copy laps")
      onClicked: ClipboardManager.copyText(StopwatchClock.lapsText(StopwatchManager.laps, n => I18n.tr("Lap {0}", n)))
    }
  }

  Flickable {
    id: lapList
    visible: !root.timerMode && StopwatchManager.laps.length > 0
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    Layout.preferredHeight: root.embedded ? 0 : Math.min(laps.implicitHeight, Appearance.fontSize * 12)
    Layout.maximumHeight: laps.implicitHeight
    contentHeight: laps.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    ColumnLayout {
      id: laps
      width: lapList.width
      spacing: 2

      Repeater {
        model: root.timerMode ? 0 : StopwatchManager.laps.length
        RowLayout {
          id: lapRow
          required property int index
          readonly property var lap: StopwatchManager.laps[index] ?? {
            "number": 0,
            "split": 0,
            "total": 0,
            "fastest": false,
            "slowest": false
          }
          readonly property color tint: lapRow.lap.fastest ? Theme.success : lapRow.lap.slowest ? Theme.error : Theme.foreground
          Layout.fillWidth: true
          spacing: Widget.spacing

          StyledText {
            Layout.fillWidth: true
            text: I18n.tr("Lap {0}", lapRow.lap.number)
            textColor: lapRow.lap.fastest || lapRow.lap.slowest ? lapRow.tint : Theme.foregroundAlt
            textSize: Appearance.fontSizeBy(-1)
          }
          StyledText {
            text: StopwatchClock.format(lapRow.lap.split, true, false)
            textColor: lapRow.tint
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
}
