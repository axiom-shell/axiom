pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A level as `count` blocks (or dots) in a row, or a column filling up
// when `vertical`, lit up to `share` (0-1). The blocks share its length;
// `across` is how thick they are (a dot's is its length). The bar's custom
// widgets and a custom widget's Segments element draw it; a bar sets its
// own sizes.
Item {
  id: root

  property int count: 5
  property real share: 0
  property bool vertical: false
  property bool round: false
  property real across: Widget.px(16)
  property real gap: Widget.px(3)
  property real cornerRadius: Widget.px(2)
  property color litColor: Theme.accent
  property color offColor: Theme.backgroundHighlight

  readonly property int lit: Math.round(Math.max(0, Math.min(1, root.share)) * root.count)
  readonly property real cell: Math.max(0, ((root.vertical ? root.height : root.width) - root.gap * (root.count - 1)) / root.count)

  Grid {
    anchors.centerIn: parent
    columns: root.vertical ? 1 : root.count
    spacing: root.gap

    Repeater {
      model: root.count

      Rectangle {
        required property int index
        readonly property real thick: Math.min(root.vertical ? root.width : root.height, root.round ? root.cell : root.across)
        width: root.vertical ? thick : root.cell
        height: root.vertical ? root.cell : thick
        radius: root.round ? Math.min(width, height) / 2 : root.cornerRadius
        // A column fills from the bottom
        color: (root.vertical ? root.count - 1 - index : index) < root.lit ? root.litColor : root.offColor

        ColorGlide on color {}
      }
    }
  }
}
