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
// overlay card. Timer: type a duration ("10m tea") or pick a preset, then
// pause, +1 min and reset; a ring shows how far it's gone. Stopwatch: the
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

  readonly property real dialSize: root.embedded ? Math.max(Appearance.fontSize * 4, Math.min(root.innerWidth, root.innerHeight - Appearance.fontSize * 8)) : Appearance.fontSize * 9

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

  // Set: the ring with the time left
  TimeRing {
    visible: root.timerMode && !StopwatchManager.timerIdle
    size: root.dialSize
    progress: StopwatchManager.timerProgress
    text: StopwatchManager.timerText
    label: StopwatchManager.timerRunning ? StopwatchManager.timer.label : I18n.tr("Paused")
    running: StopwatchManager.timerRunning
  }

  // Not set: a duration to type, or a preset
  ColumnLayout {
    visible: root.timerMode && StopwatchManager.timerIdle
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    spacing: Widget.spacing

    StyledTextEntry {
      id: durationField
      Layout.fillWidth: true
      Layout.preferredHeight: Widget.height
      placeholderText: I18n.tr("10m, 1h30m, 90s, 10m tea…")
      onAccepted: {
        if (StopwatchManager.startTimerText(durationField.text))
          durationField.text = "";
      }
    }

    Flow {
      Layout.fillWidth: true
      spacing: Widget.spacing / 2

      Repeater {
        model: StopwatchConfig.presets.length
        StyledTextButton {
          required property int index
          readonly property string preset: StopwatchConfig.presets[index] ?? ""
          implicitHeight: Widget.height - Widget.px(4)
          text: preset
          onClicked: StopwatchManager.startTimerText(preset)
        }
      }
      StyledTextButton {
        visible: StopwatchManager.timer.duration > 0
        implicitHeight: Widget.height - Widget.px(4)
        iconText: "replay"
        text: StopwatchClock.format(StopwatchManager.timer.duration, false, true)
        onClicked: StopwatchManager.toggleTimer()
      }
    }

    Item {
      visible: root.embedded
      Layout.fillHeight: true
    }
  }

  RowLayout {
    visible: root.timerMode && !StopwatchManager.timerIdle
    Layout.alignment: Qt.AlignHCenter
    spacing: Widget.spacing

    FlatIconButton {
      size: Math.round(Appearance.fontSize * 2)
      iconText: "stop"
      tooltipText: I18n.tr("Reset")
      onClicked: StopwatchManager.resetTimer()
    }
    FlatIconButton {
      size: Math.round(Appearance.fontSize * 2.6)
      iconText: StopwatchManager.timerRunning ? "pause" : "play_arrow"
      iconColor: Theme.accent
      tooltipText: StopwatchManager.timerRunning ? I18n.tr("Pause") : I18n.tr("Resume")
      onClicked: StopwatchManager.toggleTimer()
    }
    FlatIconButton {
      size: Math.round(Appearance.fontSize * 2)
      iconText: "more_time"
      tooltipText: I18n.tr("One more minute")
      onClicked: StopwatchManager.addTimer(60000)
    }
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
