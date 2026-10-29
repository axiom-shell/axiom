pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.session
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// Caffeine (IdleManager): the IdleInhibitor widget's popout. A switch for
// on until turned off, and a CountdownTimer (as the one-off timer's) to
// keep awake for a set time: a typed duration or one of the widget's
// `presets`, then the time left, pause, more time and reset (which turns
// it off). The widget keeps IdleManager acquired.
Panel {
  id: root

  // Filled from the anchor's extraData: the widget's presets
  property var presets: []

  spacing: Widget.spacing
  wantsKeyboardFocus: true
  implicitWidth: Math.max(Appearance.fontSize * 20, body.implicitWidth + margins * 2)

  ModuleHeader {
    icon: IdleManager.caffeine ? "coffee" : "bedtime"
    title: I18n.tr("Caffeine")

    StyledSwitch {
      checked: IdleManager.caffeine
      onToggled: IdleManager.setCaffeine(checked)
    }
  }

  CountdownTimer {
    timer: IdleManager.caffeineTimer
    presets: root.presets
    text: IdleManager.caffeineText
    progress: IdleManager.caffeineProgress
    label: I18n.tr("Awake")
    moreTime: 15 * 60000
    moreTimeText: I18n.tr("15 more minutes")
    resetText: I18n.tr("Turn off")
    onStarted: text => IdleManager.startCaffeineText(text)
    onToggled: IdleManager.toggleCaffeineTimer()
    onReset: IdleManager.setCaffeine(false)
    onExtended: ms => IdleManager.addCaffeineTime(ms)
  }
}
