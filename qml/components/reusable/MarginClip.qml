pragma ComponentBehavior: Bound
import QtQuick

// Clips what's put in it (`clipped`) to its bounds grown by its margins,
// for content that draws past its own box on purpose: a bar widget's parts
// reaching back under a powerline neighbour or out to a tab's edge
// (BarWidgetHost, the Workspaces cells). Its children lie in an item of its
// own size and place, so they fill and anchor as they would in it.
Item {
  id: root

  property bool clipped: true
  property real leftMargin: 0
  property real topMargin: 0
  property real rightMargin: 0
  property real bottomMargin: 0
  default property alias content: inner.data

  Item {
    clip: root.clipped
    x: -root.leftMargin
    y: -root.topMargin
    width: root.width + root.leftMargin + root.rightMargin
    height: root.height + root.topMargin + root.bottomMargin

    Item {
      id: inner
      x: root.leftMargin
      y: root.topMargin
      width: root.width
      height: root.height
    }
  }
}
