pragma ComponentBehavior: Bound
import QtQuick

import qs.components.reusable
import qs.config
import qs.services.core

// One power menu action. Destructive actions highlight in the error
// colour; armed (waiting for the confirming press) the tile fills with it
// and counts down until it disarms. It comes in a little after the tile
// before it when the menu opens.
ActionTile {
  id: root

  required property string action
  required property int index
  property bool armed: false
  // How long it stays armed
  property int armedTimeout: 3000
  // Set when the menu opens, to run the entrance
  property bool revealed: false

  readonly property var info: ShellManager.sessionActionInfo(root.action)

  // 0 → 1 as it comes in
  property real introProgress: 1

  implicitWidth: PowerMenuConfig.tileSize
  implicitHeight: PowerMenuConfig.tileSize
  icon: root.info?.icon ?? ""
  label: root.armed ? I18n.tr("Confirm?") : (root.info?.label ?? "")
  active: root.armed
  activeColor: Theme.error
  tone: ShellManager.destructiveActions.includes(root.action) ? Theme.error : Theme.accent
  countdown: root.armedTimeout

  opacity: root.introProgress
  transform: Translate {
    y: (1 - root.introProgress) * 12
  }

  onRevealedChanged: {
    intro.stop();
    if (root.revealed) {
      root.introProgress = 0;
      intro.start();
    }
  }

  SequentialAnimation {
    id: intro
    PauseAnimation {
      duration: root.index * Appearance.animFast / 4
    }
    NumberAnimation {
      target: root
      property: "introProgress"
      to: 1
      duration: Appearance.animNormal
      easing.type: Appearance.easing
    }
  }
}
