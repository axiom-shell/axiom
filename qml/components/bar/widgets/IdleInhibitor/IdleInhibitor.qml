pragma ComponentBehavior: Bound
import QtQuick

import qs.services.session
import qs.services.ui
import qs.config
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// Caffeine toggle: while on, axiom's idle steps (and an idle daemon that
// honours logind's idle inhibitors) won't treat the session as idle. The
// state lives outside the bar (IdleManager, applied by the daemon), so
// every bar's widget, the IPC target and the quick action stay in sync. On
// for a set time, it shows the time left (faded while paused), drawn by
// its display style too; hovering opens the presets (Caffeine).
ValueStyleWidget {
  id: root

  Component.onCompleted: IdleManager.acquire(root, 1000)
  Component.onDestruction: IdleManager.release(root)

  icon: IdleManager.caffeine ? "coffee" : "bedtime"
  text: IdleManager.caffeineTimed ? IdleManager.caffeineText : I18n.tr(IdleManager.caffeine ? "Awake" : "Idle")
  labelShown: properties.showLabel || IdleManager.caffeineTimed
  ratio: IdleManager.caffeineTimed ? 1 - IdleManager.caffeineProgress : -1
  dim: IdleManager.caffeineTimed && !IdleManager.caffeineTimer.running ? 0.6 : 1

  accentField: IdleManager.caffeine ? "activeColor" : "inactiveColor"
  clickable: true
  onClicked: ActionsManager.run("idleInhibit", {
    "fromScreen": true
  })

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "Caffeine"
    active: EdgeMenusConfig.opensOwnPopout(root.properties) && !root.hidden
    extraData: ({
        "presets": root.properties.presets
      })
  }
}
