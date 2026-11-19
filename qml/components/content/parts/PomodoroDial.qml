pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.services.ui
import qs.components.reusable

// The pomodoro timer (PomodoroManager), for the Pomodoro popout and module
// and the Focus module: DialControls with the time left and the phase,
// stop / start-pause / skip, then a dot per session until the long break
// and (with `showTask`) the todo the sessions are for. `fill`, `horizontal`
// and `dialSize` are DialControls'. Its owner acquires the manager.
ColumnLayout {
  id: root

  property bool showTask: true
  property alias fill: dial.fill
  property alias horizontal: dial.horizontal
  property alias dialSize: dial.dialSize

  readonly property color phaseColor: PomodoroManager.isBreak ? Style.accentAlt : Style.accent
  // Sessions done towards the next long break (all of them during it)
  readonly property int towardsLong: PomodoroManager.phase === "long" ? PomodoroConfig.longBreakEvery : PomodoroManager.completed % PomodoroConfig.longBreakEvery

  spacing: Widget.spacing

  DialControls {
    id: dial
    Layout.fillWidth: true
    Layout.fillHeight: root.fill
    // Filling: whatever is left, never what the ring asks (it's sized from it)
    Layout.preferredHeight: root.fill ? 0 : -1
    progress: PomodoroManager.progress
    text: PomodoroManager.remainingText
    label: PomodoroManager.idle || PomodoroManager.running ? PomodoroManager.phaseLabel : I18n.tr("Paused")
    color: root.phaseColor
    running: PomodoroManager.running
    leftIcon: "stop"
    leftTip: I18n.tr("Stop")
    leftEnabled: !PomodoroManager.idle
    mainIcon: PomodoroManager.running ? "pause" : "play_arrow"
    mainTip: PomodoroManager.running ? I18n.tr("Pause") : I18n.tr("Start")
    rightIcon: "skip_next"
    rightTip: I18n.tr("Skip to the next phase")
    onLeftClicked: ActionsManager.run("pomodoroStop")
    onMainClicked: ActionsManager.run("pomodoro")
    onRightClicked: ActionsManager.run("pomodoroSkip")
  }

  // A dot per session until the long break
  SegmentMeter {
    Layout.alignment: Qt.AlignHCenter
    count: PomodoroConfig.longBreakEvery
    share: count > 0 ? root.towardsLong / count : 0
    round: true
    gap: Widget.spacing / 2
    Layout.preferredHeight: Appearance.fontSize * 0.6
    Layout.preferredWidth: count * Layout.preferredHeight + gap * (count - 1)
  }

  Loader {
    active: root.showTask
    visible: active
    Layout.fillWidth: true
    sourceComponent: StyledComboEntry {
      icon: "checklist"
      options: [
        {
          "value": "",
          "label": I18n.tr("No task")
        }
      ].concat(TodoManager.shownItems.filter(item => !item.done).map(item => ({
            "value": item.uid,
            "label": item.summary
          })))
      value: PomodoroManager.todoText !== "" ? PomodoroManager.todoUid : ""
      onPicked: value => PomodoroManager.setTodo(value)
    }
  }
}
