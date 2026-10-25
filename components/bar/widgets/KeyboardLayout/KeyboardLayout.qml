pragma ComponentBehavior: Bound
import QtQuick

import qs.services.system
import qs.components.bar.widgets.base

// Active xkb layout of the main keyboard, from KeyboardLayoutManager. Left
// click cycles to the next layout, right click to the previous one.
BarIconWidget {
  id: root

  readonly property var layouts: KeyboardLayoutManager.layouts
  readonly property int layoutIndex: KeyboardLayoutManager.layoutIndex
  readonly property string keymapName: KeyboardLayoutManager.keymapName

  hidden: properties.hideSingle && layouts.length <= 1

  icon: "keyboard"
  text: properties.format === "full" ? keymapName : (layouts[layoutIndex] ?? "").toUpperCase()

  clickable: true
  acceptedButtons: Qt.LeftButton | Qt.RightButton
  onClicked: button => KeyboardLayoutManager.cycle(button === Qt.RightButton ? "prev" : "next")
}
