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
    // A line or slash spans the box's length; a chevron is a mark the
    // size of the gap it sits in (its short side), as a bar's is the bar's
    length: (root.options.style === "chevron" ? Math.min(root.width, root.height) : Math.max(root.width, root.height)) * root.options.length / 100
    vertical: !root.vertical
  }
}
