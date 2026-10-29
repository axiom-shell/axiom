pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A custom widget's Separator element: a hairline across its box, or down
// it when it's tall (an empty one is a spacer: options.line false).
CustomElementBase {
  id: root

  readonly property bool vertical: root.height > root.width

  Rectangle {
    visible: root.opt("line", true)
    anchors.centerIn: parent
    width: root.vertical ? 1 : root.width
    height: root.vertical ? root.height : 1
    color: Theme.border
  }
}
