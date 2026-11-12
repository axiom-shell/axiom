pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.apps
import qs.services.ui
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// The pomodoro timer (PomodoroManager): the time left while a session or
// break is on, colored by which. Left click starts or pauses, right click
// skips to the next phase, middle click stops; hovering opens the timer.
// Its display style draws how far through the phase it is.
BarWidget {
  id: root

  Component.onCompleted: PomodoroManager.acquire(root)
  Component.onDestruction: PomodoroManager.release(root)

  hidden: properties.hideWhenIdle && PomodoroManager.idle

  icon: PomodoroManager.isBreak ? "coffee" : "timer"
  text: PomodoroManager.remainingText
  labelShown: !PomodoroManager.idle
  ratio: PomodoroManager.idle ? -1 : PomodoroManager.progress
  // Idle, stacked shows no time either, as the label doesn't
  styleText: PomodoroManager.idle ? "" : root.text
  subtext: PomodoroManager.idle ? "" : PomodoroManager.isBreak ? I18n.tr("Break") : I18n.tr("Focus")
  accentField: PomodoroManager.idle ? "idleColor" : PomodoroManager.isBreak ? "breakColor" : "workColor"
  // Paused part way: muted
  muted: !PomodoroManager.running && !PomodoroManager.idle

  clickable: true
  acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
  onClicked: button => {
    if (button === Qt.RightButton)
      ActionsManager.run("pomodoroSkip");
    else if (button === Qt.MiddleButton)
      ActionsManager.run("pomodoroStop");
    else
      ActionsManager.run("pomodoro");
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "Pomodoro"
    active: MenusConfig.opensOwnPopout(root.properties) && !root.hidden
  }
}
