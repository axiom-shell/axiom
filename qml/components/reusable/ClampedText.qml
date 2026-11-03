pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// Muted help text cut to `maxLines`, with a More link that shows the rest
// (and Less to fold it again) only when it's longer
ColumnLayout {
  id: root

  property string text: ""
  property int maxLines: 3
  property int textSize: Appearance.fontSizeBy(-2)
  property real textOpacity: 0.65
  property bool expanded: false

  Layout.fillWidth: true
  spacing: 0
  visible: root.text !== ""

  StyledText {
    id: body
    Layout.fillWidth: true
    text: root.text
    opacity: root.textOpacity
    textSize: root.textSize
    wrapMode: Text.WordWrap
    maximumLineCount: root.expanded ? 100000 : root.maxLines
    elide: Text.ElideRight
  }

  StyledText {
    id: toggle
    visible: body.truncated || root.expanded
    text: root.expanded ? I18n.tr("Less") : I18n.tr("More")
    // In the accent, so it stands out from the muted text above
    textColor: Theme.accent
    textSize: root.textSize
    font.weight: Font.Medium
    font.underline: toggleArea.containsMouse

    MouseArea {
      id: toggleArea
      anchors.fill: parent
      anchors.margins: -Widget.px(2)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.expanded = !root.expanded
    }
  }
}
