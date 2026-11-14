pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.components.methods

// One tab of a StyledTabBar: its label (and, while `marked`, an UnsavedDot
// after it, inside the label's width so the underline covers both), a hover
// layer and the keyboard focus ring, the bar drawing the current tab's
// underline, which slides between its tabs
TabButton {
  id: root

  // -- Configurable Appearance --
  property color activeColor: Style.toneOn(root._scope, "text")
  property color inactiveColor: Style.toneOn(root._scope, "muted")

  // Unsaved edits under this tab
  property bool marked: false

  // -- Implementation --
  // The room the dot takes after the label
  readonly property real _dotRoom: root.marked ? Widget.px(8) + Style.space1 : 0
  readonly property var _outer: InkHost.find(root.parent)
  readonly property var _scope: root._outer ? root._outer.inkScope : null

  Layout.fillWidth: true
  Layout.fillHeight: true

  contentItem: Item {
    id: content
    implicitWidth: tabText.implicitWidth + root._dotRoom
    implicitHeight: tabText.implicitHeight

    StyledLabel {
      id: tabText
      anchors.verticalCenter: parent.verticalCenter
      // Centred with the dot, elided at the tab's width
      x: Math.round((content.width - tabText.width - root._dotRoom) / 2)
      width: Math.min(tabText.implicitWidth, content.width - root._dotRoom)
      text: root.text
      role: "label"
      overflow: "line"
      textColor: root.checked ? root.activeColor : root.inactiveColor

      ColorGlide on textColor {
        duration: Appearance.animNormal
      }
    }

    UnsavedDot {
      anchors.verticalCenter: parent.verticalCenter
      x: tabText.x + tabText.width + Style.space1
      shown: root.marked
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
