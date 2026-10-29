pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable

// A custom widget's Status element: a pill in the state's colour with a
// word (the widget's alt, else its first class), or a dot without room.
// options: dot (always a dot)
CustomElementBase {
  id: root

  readonly property string word: root.bind.text ? root.text("text") : (root.fields?.alt || (root.fields?.classes ?? [])[0] || "")
  readonly property color stateColor: root.fields?.color ? Theme.resolveColor(root.fields.color) : Theme.foregroundAlt
  readonly property bool dot: root.opt("dot", false) || root.word === "" || root.width < Widget.px(48)

  Rectangle {
    visible: root.dot
    anchors.centerIn: parent
    width: Math.min(root.width, root.height, Widget.px(14))
    height: width
    radius: width / 2
    color: root.stateColor
  }

  StatusChip {
    visible: !root.dot
    anchors.centerIn: parent
    text: root.word
    color: root.stateColor
  }
}
