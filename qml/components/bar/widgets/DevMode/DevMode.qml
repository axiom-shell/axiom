pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.services.core
import qs.services.ui
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

  readonly property bool failed: DevManager.lastBuild?.ok === false

  hidden: !DevManager.enabled

  // While building, a spinner in the lead slot stands in for the icon
  icon: "code"
  showIcon: !DevManager.building
  leadLength: DevManager.building ? (root.isVertical ? spinner.implicitHeight : spinner.implicitWidth) : 0
  text: DevManager.checkout !== "" ? I18n.tr("DEV · {0}", DevManager.checkout) : I18n.tr("DEV")

  accentColor: root.failed ? Theme.error : Theme.resolveColor(properties.backgroundColor)

  clickable: true
  onClicked: SettingsManager.openCategory("Development")

  StyledIcon {
    id: spinner
    parent: root.lead
    anchors.centerIn: parent
    visible: DevManager.building
    text: "progress_activity"
    textColor: root.iconColor
    textSize: root.fontSize * root.iconScale

    RotationAnimation on rotation {
      running: DevManager.building && Appearance.animations && !root.hidden
      loops: Animation.Infinite
      from: 0
      to: 360
      duration: Appearance.animSlow * 4
    }
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "DevModeMenu"
    active: EdgeMenusConfig.opensOwnPopout(root.properties) && !root.hidden
  }

  // With its popout off: the dev tree and the last build
  LazyLoader {
    active: root.hovered && !root.hidden && !root.properties.popout.enabled
    StyledToolTip {
      target: root
      text: [Paths.shortenHome(DevManager.tree), DevManager.buildText].filter(line => line !== "").join("\n")
      edges: root.innerEdges
    }
  }
}
