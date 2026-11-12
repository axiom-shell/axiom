pragma ComponentBehavior: Bound
import QtQuick

import qs.services.core
import qs.config
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// Dev mode (DevManager), shown only while it's on: "DEV · branch@sha",
// a spinner in the icon's place while the dev build builds, its failed
// colour after a failed build. A click opens Settings › Development; hovering opens its
// menu (DevModeMenu: rebuild, the settings, turn off), or with that off a
// tooltip with the dev tree and the last build. Placed by config only, in
// no default bar.
BarWidget {
  id: root

  hidden: !DevManager.enabled

  // While building, a spinner stands in for the icon
  icon: "code"
  busy: DevManager.building
  text: DevManager.checkout !== "" ? I18n.tr("DEV · {0}", DevManager.checkout) : I18n.tr("DEV")

  accentField: DevManager.buildFailed ? "failedColor" : "backgroundColor"

  clickable: true
  onClicked: DevManager.openDevelopment()

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "DevModeMenu"
    active: MenusConfig.opensOwnPopout(root.properties) && !root.hidden
  }

  // With its popout off: the dev tree and the last build
  BarToolTip {
    widget: root
    shown: !root.hidden && !root.properties.popout.enabled
    text: [Paths.shortenHome(DevManager.tree), DevManager.buildText].filter(line => line !== "").join("\n")
  }
}
