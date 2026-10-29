pragma ComponentBehavior: Bound
import QtQuick

import qs.services.session
import qs.config
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// Caffeine toggle: while on, the compositor (and axiom's idle steps) won't
// treat the session as idle. The state and the inhibitor itself live outside the bar
// (IdleManager, shell/IdleInhibit), so every bar's widget, the IPC
// target and the quick action stay in sync. On for a set time, it shows the
// time left (faded while paused); hovering opens the presets (Caffeine).
BarIconWidget {
  id: root

  Component.onCompleted: IdleManager.acquire(root, 1000)
  Component.onDestruction: IdleManager.release(root)

  icon: IdleManager.caffeine ? "coffee" : "bedtime"
  text: IdleManager.caffeineTimed ? IdleManager.caffeineText : I18n.tr(IdleManager.caffeine ? "Awake" : "Idle")
  showText: properties.showLabel || IdleManager.caffeineTimed
  // Ticking: sized by its digit count, not by each second's digits
  steadyDigits: IdleManager.caffeineTimed
  dim: IdleManager.caffeineTimed && !IdleManager.caffeineTimer.running ? 0.6 : 1

  accentColor: Theme.resolveColor(IdleManager.caffeine ? properties.activeColor : properties.inactiveColor)
  clickable: true
  onClicked: IdleManager.toggle()

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "Caffeine"
    active: EdgeMenusConfig.opensOwnPopout(root.properties) && !root.hidden
    extraData: ({
        "presets": root.properties.presets
      })
  }
}
