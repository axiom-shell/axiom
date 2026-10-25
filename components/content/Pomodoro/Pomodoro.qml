pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.apps
import qs.components.content.base
import qs.components.content.parts

// The pomodoro timer (PomodoroManager, PomodoroDial): the Pomodoro widget's
// popout, or an overlay card, the ring beside the controls when the card
// is wide and short. Compact, the time left.
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

  readonly property bool wide: root.embedded && root.innerWidth > root.innerHeight * 1.6

  PomodoroDial {
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    horizontal: root.wide
    showTask: !root.embedded || (root.properties.showTask ?? true)
    dialSize: root.embedded ? Math.max(Appearance.fontSize * 4, Math.min(root.wide ? root.innerHeight : root.innerWidth, root.innerHeight - (root.wide ? 0 : Appearance.fontSize * 7))) : Appearance.fontSize * 9
  }
}
