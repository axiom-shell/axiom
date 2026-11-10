pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.apps
import qs.services.ui
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// The one-off timer and the stopwatch (StopwatchManager): the timer's time
// left while it's set, else the stopwatch's time while it's going. Left
// click pauses or resumes the one shown (with neither, starts the
// stopwatch), right click resets it, middle click marks a lap; hovering
// opens both, to set a timer. Its display style draws the timer's
// progress, or the stopwatch's way round the current minute.
ValueStyleWidget {
  id: root

  Component.onCompleted: StopwatchManager.acquire(root, 1000)
  Component.onDestruction: StopwatchManager.release(root)

  readonly property bool showsTimer: !StopwatchManager.timerIdle
  readonly property bool showsStopwatch: !root.showsTimer && !StopwatchManager.stopwatchIdle
  readonly property bool running: root.showsTimer ? StopwatchManager.timerRunning : StopwatchManager.stopwatchRunning

  hidden: properties.hideWhenIdle && !root.showsTimer && !root.showsStopwatch

  icon: root.showsTimer ? "hourglass_top" : "timer_play"
  text: root.showsTimer ? StopwatchManager.timerText : StopwatchManager.elapsedText
  labelShown: root.showsTimer || root.showsStopwatch
  // Idle, stacked shows no time either, as the label doesn't
  styleText: root.labelShown ? root.text : ""
  ratio: root.showsTimer ? StopwatchManager.timerProgress : root.showsStopwatch ? (StopwatchManager.elapsed % 60000) / 60000 : -1
  subtext: root.showsTimer ? I18n.tr("Timer") : root.showsStopwatch ? I18n.tr("Lap {0}", StopwatchManager.laps.length + 1) : ""
  accentField: root.showsTimer ? "timerColor" : root.showsStopwatch ? "stopwatchColor" : "idleColor"
  // Paused: faded
  dim: (root.showsTimer || root.showsStopwatch) && !root.running ? 0.6 : 1

  clickable: true
  acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
  onClicked: button => {
    if (button === Qt.MiddleButton)
      ActionsManager.run("stopwatchLap");
    else if (button === Qt.RightButton)
      ActionsManager.run(root.showsTimer ? "timerReset" : "stopwatchReset");
    else
      ActionsManager.run(root.showsTimer ? "timerToggle" : "stopwatch");
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "Stopwatch"
    active: MenusConfig.opensOwnPopout(root.properties) && !root.hidden
  }
}
