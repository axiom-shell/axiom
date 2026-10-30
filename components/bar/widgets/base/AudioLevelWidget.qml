pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.core
import qs.services.system
import qs.components.hosts.popout

// Base for the Volume and Microphone widgets: a default device's level, as
// the value of its display style (full at 100%, above it too).
// Scroll changes its volume (up to the configured maximum), click mutes,
// middle click runs a command; hovering opens the mixer on its side.
ValueStyleWidget {
  id: root

  // The default sink or source
  property var node: null
  // The mixer's side: "output" | "input"
  property string mode: "output"
  readonly property real level: root.node?.audio?.volume ?? 0
  readonly property bool muted: root.node?.audio?.muted ?? false
  readonly property real maxVolume: properties.maxVolume / 100

  text: `${Math.round(root.level * 100)}%`
  minimumText: "100%"
  labelShown: properties.showPercentage
  ratio: root.node ? Math.min(1, root.level) : -1

  clickable: true
  acceptedButtons: Qt.LeftButton | Qt.MiddleButton
  scrollable: true
  onClicked: button => {
    if (button === Qt.MiddleButton)
      CommandManager.runDetached(root.properties.middleCommand);
    else
      AudioManager.toggleNodeMute(root.node);
  }
  onScrolled: steps => {
    if (steps === 0)
      return;
    const step = root.properties.scrollStep / 100;
    AudioManager.stepNodeVolume(root.node, steps > 0 ? step : -step, root.maxVolume);
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "AudioMixer"
    active: EdgeMenusConfig.opensOwnPopout(root.properties) && !root.hidden
    extraData: ({
        "mode": root.mode,
        "maxVolume": root.maxVolume
      })
  }
}
