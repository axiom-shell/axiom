pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A two- or three-way toggle: a capsule with each option's label in an
// equal segment, an accent thumb under the chosen one gliding across as it
// changes. With two options a click anywhere flips it, as a switch does;
// with three a click picks the segment under the pointer. The owner keeps
// the value: set `value`, and update it from `picked`.
Item {
  id: root

  // The option values (two or three), and the label each shows
  property var options: []
  property var labels: ({})
  property var value

  signal picked(var value)

  readonly property int _index: Math.max(0, root.options.indexOf(root.value))
  readonly property real _inset: Widget.px(2)
  // Each segment as wide as the widest label, so the thumb never resizes
  readonly property real _segment: Array.prototype.reduce.call(measures.children, (widest, label) => Math.max(widest, label.implicitWidth), 0) + Widget.spacing * 3

  implicitWidth: root._segment * Math.max(1, root.options.length) + root._inset * 2
  implicitHeight: Widget.height - Widget.px(4)

  activeFocusOnTab: true
  Keys.onSpacePressed: root._flip()
  Keys.onLeftPressed: root._step(-1)
  Keys.onRightPressed: root._step(1)

  // Two options: picks the other one
  function _flip() {
    if (root.options.length === 2)
      root.picked(root.options[1 - root._index]);
  }

  function _step(by) {
    const index = Math.max(0, Math.min(root.options.length - 1, root._index + by));
    if (index !== root._index)
      root.picked(root.options[index]);
  }

  // The labels at their own widths, unseen, measuring the segments
  Item {
    id: measures
    visible: false

    Repeater {
      model: root.options

      StyledText {
        required property var modelData
        text: root.labels[modelData] ?? ""
      }
    }
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
    x: root._inset + root._index * root._segment
    y: root._inset
    width: root._segment
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

    Repeater {
      model: root.options

      StyledText {
        required property var modelData
        required property int index
        width: root._segment
        horizontalAlignment: Text.AlignHCenter
        text: root.labels[modelData] ?? ""
        textColor: root._index === index ? Theme.background : Theme.foregroundAlt

        ColorGlide on textColor {
          duration: Appearance.animNormal
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: mouse => {
      if (root.options.length === 2)
        root._flip();
      else
        root.picked(root.options[Math.max(0, Math.min(root.options.length - 1, Math.floor((mouse.x - root._inset) / root._segment)))]);
    }
  }
}
