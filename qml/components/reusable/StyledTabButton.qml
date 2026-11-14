pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.components.methods

// One tab of a StyledTabBar: its label, a hover layer and the keyboard focus
// ring, the bar drawing the current tab's underline, which slides between
// its tabs
TabButton {
  id: root

  // -- Configurable Appearance --
  property color activeColor: Style.toneOn(root._scope, "text")
  property color inactiveColor: Style.toneOn(root._scope, "muted")

  // -- Implementation --
  readonly property var _outer: InkHost.find(root.parent)
  readonly property var _scope: root._outer ? root._outer.inkScope : null

  Layout.fillWidth: true
  Layout.fillHeight: true

  contentItem: StyledLabel {
    text: root.text
    role: "label"
    overflow: "line"
    textColor: root.checked ? root.activeColor : root.inactiveColor
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    ColorGlide on textColor {
      duration: Appearance.animNormal
    }
  }

  background: Item {
    StateLayer {
      hovered: root.hovered
      pressed: root.pressed
    }

    FocusRing {
      shown: root.visualFocus
    }
  }
}
