pragma ComponentBehavior: Bound
import QtQuick

import qs.services.core
import qs.config
import qs.components.reusable
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// Dev mode (DevManager), shown only while it's on: "DEV · branch@sha",
// a spinning icon while the dev build builds, the error colour after a
// failed build. A click opens Settings › Development; hovering opens its
// menu (DevModeMenu: rebuild, the settings, turn off), or with that off a
// tooltip with the dev tree and the last build. Placed by config only, in
// no default bar.
BarIconWidget {
  id: root

  hidden: !DevManager.enabled

  // While building, a spinner in the lead slot stands in for the icon
  icon: "code"
  showIcon: !DevManager.building
  leadLength: DevManager.building ? (root.isVertical ? spinner.implicitHeight : spinner.implicitWidth) : 0
  text: DevManager.checkout !== "" ? I18n.tr("DEV · {0}", DevManager.checkout) : I18n.tr("DEV")

  accentField: DevManager.buildFailed ? "" : "backgroundColor"
  accentColor: DevManager.buildFailed ? Theme.error : Theme.resolveColor(properties.backgroundColor)

  clickable: true
  onClicked: DevManager.openDevelopment()

  SpinningIcon {
    id: spinner
    parent: root.lead
    anchors.centerIn: parent
    visible: DevManager.building
    text: "progress_activity"
    textColor: root.iconColor
    textSize: root.fontSize * root.iconScale
    spinning: DevManager.building && !root.hidden
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "DevModeMenu"
    active: EdgeMenusConfig.opensOwnPopout(root.properties) && !root.hidden
  }

  // With its popout off: the dev tree and the last build
  BarToolTip {
    widget: root
    shown: !root.hidden && !root.properties.popout.enabled
    text: [Paths.shortenHome(DevManager.tree), DevManager.buildText].filter(line => line !== "").join("\n")
  }
}
