pragma ComponentBehavior: Bound
import QtQuick

import qs.services.system
import qs.services.ui
import qs.components.bar.widgets.base

// Active xkb layout of the main keyboard, from InputSourceManager. Left
// click cycles to the next layout, right click to the previous one.
BarIconWidget {
  id: root

  readonly property var layouts: InputSourceManager.layouts
  readonly property int layoutIndex: InputSourceManager.layoutIndex
  readonly property string keymapName: InputSourceManager.keymapName

  hidden: properties.hideSingle && layouts.length <= 1

  icon: "keyboard"
  text: properties.format === "full" ? keymapName : (layouts[layoutIndex] ?? "").toUpperCase()

  clickable: true
  acceptedButtons: Qt.LeftButton | Qt.RightButton
  onClicked: button => {
    ShellManager.onScreen("keyboardLayout");
    InputSourceManager.cycle(button === Qt.RightButton ? "prev" : "next");
  }
}
