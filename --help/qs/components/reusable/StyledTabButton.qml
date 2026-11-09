pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config

// One tab of a StyledTabBar: only its label, the bar drawing the current
// tab's highlight, which slides between its tabs
TabButton {
  id: root

  // -- Configurable Appearance --
  property color activeColor: Theme.accent
  property color inactiveColor: Theme.foregroundAlt

  // -- Implementation --
  Layout.fillWidth: true
  Layout.fillHeight: true

  contentItem: StyledText {
    text: root.text
    textSize: Appearance.fontSizeBy(-2)
    textColor: root.checked ? root.activeColor : root.inactiveColor
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight

    ColorGlide on color {
      duration: Appearance.animNormal
    }
  }

  background: Item {}
}
