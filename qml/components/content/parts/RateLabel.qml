pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.components.reusable

// A transfer rate with its direction: an arrow and "1.5 MB/s"
Row {
  id: root

  // Bytes per second
  property real rate: 0
  // "down" or "up"
  property string direction: "down"
  property color textColor: Theme.foreground
  property int textSize: Appearance.fontSizeBy(-1)

  spacing: 2

  StyledIcon {
    anchors.verticalCenter: parent.verticalCenter
    text: root.direction === "up" ? "arrow_upward" : "arrow_downward"
    textColor: root.textColor
    textSize: root.textSize
  }
  StyledText {
    anchors.verticalCenter: parent.verticalCenter
    text: Utils.formatRate(root.rate)
    textColor: root.textColor
    textSize: root.textSize
  }
}
