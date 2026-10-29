pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable
import qs.components.content.parts.custom

// A custom widget's Status element: a StatusChip in the state's colour
// with a word (the widget's alt, else its first class), or a dot without
// room.
CustomElementBase {
  id: root

  readonly property string word: root.bind.text ? root.text("text") : (root.fields?.alt || (root.fields?.classes ?? [])[0] || "")
  readonly property color chipColor: root.colorOf(Theme.foregroundAlt)
  readonly property bool dot: root.options.dot || root.word === "" || root.width < Widget.px(48)

  Rectangle {
    visible: root.dot
    anchors.centerIn: parent
    width: Math.min(root.width, root.height, Widget.px(14))
    height: width
    radius: width / 2
    color: root.chipColor

    ColorGlide on color {}
  }

  StatusChip {
    visible: !root.dot
    anchors.centerIn: parent
    text: root.word
    color: root.chipColor
  }
}
