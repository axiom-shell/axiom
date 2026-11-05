pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.apps
import qs.components.content.base
import qs.components.content.parts

// The pomodoro timer (PomodoroManager, PomodoroDial): the Pomodoro widget's
// popout, or an overlay card, the ring filling it (beside its buttons when
// the card is wide and short). Compact, the time left.
// properties (card): { showTask }
Panel {
  id: root

  spacing: Widget.spacing
  implicitWidth: Math.max(Appearance.fontSize * 18, body.implicitWidth + margins * 2)
  fullMinWidth: Appearance.fontSize * 9
  fullMinHeight: Appearance.fontSize * 9

  Component.onCompleted: PomodoroManager.acquire(root)
  Component.onDestruction: PomodoroManager.release(root)

  compactContent: CompactFigure {
    icon: PomodoroManager.isBreak ? "coffee" : "timer"
    iconColor: PomodoroManager.isBreak ? Theme.accentAlt : Theme.accent
    value: PomodoroManager.remainingText
    label: PomodoroManager.phaseLabel
  }

  PomodoroDial {
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    fill: root.embedded
    showTask: !root.embedded || (root.properties.showTask ?? true)
  }
}
