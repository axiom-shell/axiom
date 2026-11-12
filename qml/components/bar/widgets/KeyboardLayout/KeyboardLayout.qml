pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.system
import qs.services.ui
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// The input source in use (InputSourceManager: an xkb layout's code or
// name, an input method's own label), with its kind's icon. Left click
// switches to the next source, right click to the previous one, the wheel
// steps through them; hovering lists them (the InputSources popout).
BarWidget {
  id: root

  readonly property string current: InputSourceManager.current

  hidden: properties.hideSingle && InputSourceManager.sources.length <= 1

  icon: InputSourceManager.iconFor(root.current)
  showIcon: properties.showIcon
  text: InputSourceManager.labelFor(root.current, properties.format)

  clickable: true
  scrollable: true
  acceptedButtons: Qt.LeftButton | Qt.RightButton
  onClicked: button => root._step(button === Qt.RightButton ? -1 : 1)

  // Whole notches, a touchpad's scroll adding up to one first; up is back
  property real _scroll: 0
  onScrolled: steps => {
    root._scroll += steps;
    while (Math.abs(root._scroll) >= 1) {
      const up = root._scroll > 0;
      root._scroll += up ? -1 : 1;
      root._step(up ? -1 : 1);
    }
  }

  function _step(direction) {
    ActionsManager.run(direction < 0 ? "inputSourcePrev" : "inputSourceNext", {
      "fromScreen": true
    });
  }

  // Switches made in fcitx5 itself are heard without a tray too
  Component.onCompleted: InputSourceManager.acquire(root)
  Component.onDestruction: InputSourceManager.release(root)

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "InputSources"
    active: MenusConfig.opensOwnPopout(root.properties) && !root.hidden
  }
}
