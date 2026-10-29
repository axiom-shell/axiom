pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable
import qs.components.content.parts.custom

// A custom widget's Separator element: the Separator bar widget's
// SeparatorMark (a line, dot, slash or chevron, or nothing: a spacer)
// across its box, or down it when it's tall.
CustomElementBase {
  id: root

  SeparatorMark {
    anchors.centerIn: parent
    style: root.options.style
    color: root.options.color ? Theme.resolveColor(root.options.color) : Theme.border
    thickness: Widget.px(root.options.thickness)
    length: (root.vertical ? root.height : root.width) * root.options.length / 100
    vertical: !root.vertical
  }
}
