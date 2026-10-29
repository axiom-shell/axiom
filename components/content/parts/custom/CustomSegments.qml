pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable

// A custom widget's Segments element: a row (or column, by its shape) of
// blocks lit up to the value between min and max.
// options: min, max, count, color, round (dots)
CustomElementBase {
  id: root

  readonly property bool vertical: root.height > root.width * 1.5
  readonly property int count: Math.max(2, Math.min(24, parseInt(root.opt("count", 5))))
  readonly property int lit: Math.round(Math.max(0, root.ratio()) * root.count)
  readonly property real gap: Widget.px(3)
  readonly property real cell: ((root.vertical ? root.height : root.width) - root.gap * (root.count - 1)) / root.count

  Grid {
    anchors.centerIn: parent
    columns: root.vertical ? 1 : root.count
    spacing: root.gap

    Repeater {
      model: root.count

      Rectangle {
        required property int index
        readonly property real across: Math.min(root.vertical ? root.width : root.height, root.opt("round", false) ? root.cell : Widget.px(16))
        width: root.vertical ? across : root.cell
        height: root.vertical ? root.cell : across
        radius: root.opt("round", false) ? Math.min(width, height) / 2 : Widget.px(2)
        // A column fills from the bottom
        color: (root.vertical ? root.count - 1 - index : index) < root.lit ? root.colorOf("color", Theme.accent) : Theme.backgroundHighlight

        ColorGlide on color {
          duration: Appearance.animFast
        }
      }
    }
  }
}
