pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A countdown ring, for the pomodoro timer (PomodoroDial) and the one-off
// timer, caffeine and the stopwatch (DialControls): how far it's gone
// around a `size` square, the time in the middle (faded while not
// `running`) and a short `label` under it. While running it sweeps on
// between progress steps a `tick` (ms) apart, and jumps back or far ones;
// `urgent` turns it the warning colour.
Item {
  id: root

  property real size: Appearance.fontSize * 8
  // 0–1
  property real progress: 0
  property string text: ""
  property string label: ""
  property color color: Theme.accent
  property bool running: false
  property bool urgent: false
  // How often progress moves (ms)
  property int tick: 1000

  // What the ring shows: progress, swept to
  property real _shown: 0
  property color _color: root.urgent ? Theme.warning : root.color
  ColorGlide on _color {}

  Component.onCompleted: root._shown = root.progress
  onProgressChanged: {
    const step = root.progress - root._shown;
    if (root.running && Appearance.animations && step > 0 && step <= 0.25) {
      sweep.from = root._shown;
      sweep.to = root.progress;
      sweep.restart();
    } else {
      sweep.stop();
      root._shown = root.progress;
    }
  }

  NumberAnimation {
    id: sweep
    target: root
    property: "_shown"
    duration: root.tick // behaviour timing: spans one progress step, so the ring never stops
  }

  Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
  Layout.preferredWidth: root.size
  Layout.preferredHeight: root.size

  PercentageCircle {
    anchors.fill: parent
    percentage: root._shown * 100
    iconText: ""
    fillColor: root._color
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
      Layout.maximumWidth: root.size * 0.8
      text: root.label
      visible: text !== ""
      elide: Text.ElideRight
      textSize: Math.max(Appearance.fontSizeBy(-2), Math.round(root.size * 0.07))
      textColor: root._color
    }
  }
}
