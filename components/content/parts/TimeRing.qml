pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A countdown ring, for the pomodoro timer (PomodoroDial) and the one-off
// timer (Stopwatch): how far it's gone around a `size` square, the time in
// the middle (faded while not `running`) and a short `label` under it.
Item {
  id: root

  property real size: Appearance.fontSize * 8
  // 0–1
  property real progress: 0
  property string text: ""
  property string label: ""
  property color color: Theme.accent
  property bool running: false

  Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
  Layout.preferredWidth: root.size
  Layout.preferredHeight: root.size

  PercentageCircle {
    anchors.fill: parent
    percentage: root.progress * 100
    iconText: ""
    fillColor: root.color
  }

  ColumnLayout {
    anchors.centerIn: parent
    spacing: 0

    StyledText {
      Layout.alignment: Qt.AlignHCenter
      text: root.text
      textSize: Math.max(Appearance.fontSize, Math.round(root.size * 0.2))
      font.bold: true
      textColor: root.running ? Theme.foreground : Theme.foregroundAlt
    }
    StyledText {
      Layout.alignment: Qt.AlignHCenter
      Layout.maximumWidth: root.size * 0.7
      text: root.label
      visible: text !== ""
      elide: Text.ElideRight
      textSize: Math.max(Appearance.fontSizeBy(-2), Math.round(root.size * 0.07))
      textColor: root.color
    }
  }
}
