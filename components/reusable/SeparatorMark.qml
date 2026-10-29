pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A divider, centred where it's placed: a line across the bar (or box), a
// dot, a slash or a chevron pointing along it. Drawn by the Separator
// widget, between every pair of widgets by WidgetGroup
// (Bars[].separatorStyle), and by a custom widget's Separator element.
Item {
  id: root

  // "line" | "dot" | "slash" | "chevron" (anything else draws nothing)
  property string style: "line"
  property color color: "white"
  property real thickness: 2
  // How far it reaches across the bar (px)
  property real length: Widget.px(16)
  property bool vertical: false

  implicitWidth: vertical ? length : thickness
  implicitHeight: vertical ? thickness : length

  // A line or slash: across the bar, a slash leaning along it
  Rectangle {
    visible: root.style === "line" || root.style === "slash"
    anchors.centerIn: parent
    width: root.vertical ? root.length : root.thickness
    height: root.vertical ? root.thickness : root.length
    radius: root.thickness / 2
    rotation: root.style === "slash" ? 20 : 0
    antialiasing: true
    color: root.color
  }

  Rectangle {
    visible: root.style === "dot"
    anchors.centerIn: parent
    width: root.thickness * 2
    height: width
    radius: width / 2
    color: root.color
  }

  StyledIcon {
    visible: root.style === "chevron"
    anchors.centerIn: parent
    text: root.vertical ? "expand_more" : "chevron_right"
    textColor: root.color
    textSize: root.length
  }
}
