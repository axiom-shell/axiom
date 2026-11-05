pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A two-way toggle: a capsule with both options' labels in it, an accent
// thumb under the chosen one gliding across as it flips. A click anywhere
// flips it, as a switch does. The owner keeps the value: set `value`, and
// update it from `picked`.
Item {
  id: root

  // The two option values, and the label each shows
  property var options: []
  property var labels: ({})
  property var value

  signal picked(var value)

  readonly property int _index: Math.max(0, root.options.indexOf(root.value))
  readonly property real _inset: Widget.px(2)
  // Each half as wide as the wider label, so the thumb never resizes
  readonly property real _half: Math.max(first.implicitWidth, second.implicitWidth) + Widget.spacing * 3

  implicitWidth: root._half * 2 + root._inset * 2
  implicitHeight: Widget.height - Widget.px(4)

  activeFocusOnTab: true
  Keys.onSpacePressed: root._flip()
  Keys.onLeftPressed: root.picked(root.options[0])
  Keys.onRightPressed: root.picked(root.options[1])

  function _flip() {
    if (root.options.length === 2)
      root.picked(root.options[1 - root._index]);
  }

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: Theme.backgroundHighlight
    border.color: root.activeFocus ? Theme.accent : Theme.border
    border.width: Appearance.borderWidth
  }

  Rectangle {
    id: thumb
    x: root._inset + root._index * root._half
    y: root._inset
    width: root._half
    height: root.height - root._inset * 2
    radius: height / 2
    color: Theme.accent

    Glide on x {
      duration: Appearance.animNormal
    }
  }

  Row {
    x: root._inset
    anchors.verticalCenter: parent.verticalCenter

    StyledText {
      id: first
      width: root._half
      horizontalAlignment: Text.AlignHCenter
      text: root.labels[root.options[0]] ?? ""
      textColor: root._index === 0 ? Theme.background : Theme.foregroundAlt

      ColorGlide on textColor {
        duration: Appearance.animNormal
      }
    }

    StyledText {
      id: second
      width: root._half
      horizontalAlignment: Text.AlignHCenter
      text: root.labels[root.options[1]] ?? ""
      textColor: root._index === 1 ? Theme.background : Theme.foregroundAlt

      ColorGlide on textColor {
        duration: Appearance.animNormal
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root._flip()
  }
}
