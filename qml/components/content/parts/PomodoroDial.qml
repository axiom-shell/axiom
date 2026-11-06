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

  readonly property color phaseColor: PomodoroManager.isBreak ? Theme.accentAlt : Theme.accent
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

  Row {
    Layout.alignment: Qt.AlignHCenter
    spacing: Widget.spacing / 2

    Repeater {
      model: PomodoroConfig.longBreakEvery
      Rectangle {
        required property int index
        width: Appearance.fontSize * 0.6
        height: width
        radius: width / 2
        color: index < root.towardsLong ? Theme.accent : Theme.backgroundHighlight
      }
    }
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
