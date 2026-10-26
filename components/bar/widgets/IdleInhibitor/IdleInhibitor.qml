pragma ComponentBehavior: Bound
import QtQuick

import qs.services.session
import qs.config
import qs.components.bar.widgets.base

// Caffeine toggle: while on, the compositor (and axiom's idle steps) won't
// treat the session as idle. The state and the inhibitor itself live outside the bar
// (IdleManager, shell/IdleInhibit), so every bar's widget, the IPC
// target and the quick action stay in sync.
BarIconWidget {
  id: root

  icon: IdleManager.caffeine ? "coffee" : "bedtime"
  text: I18n.tr(IdleManager.caffeine ? "Awake" : "Idle")
  showText: properties.showLabel

  accentColor: Theme.resolveColor(IdleManager.caffeine ? properties.activeColor : properties.inactiveColor)
  clickable: true
  onClicked: IdleManager.toggle()
}
