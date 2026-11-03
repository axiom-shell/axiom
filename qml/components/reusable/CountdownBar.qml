pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A thin bar along its parent's bottom that drains from the full width to
// nothing over `duration` ms each time `running` turns on: the time an
// ActionTile or ActionPill has left while active
Rectangle {
  id: root

  property bool running: false
  property int duration: 0

  anchors.bottom: parent.bottom
  anchors.left: parent.left
  height: Widget.px(3)
  color: Theme.background
  opacity: 0.6
  visible: root.running && root.duration > 0
  width: 0

  NumberAnimation {
    id: drain
    target: root
    property: "width"
    from: root.parent.width
    to: 0
    duration: root.duration
  }

  onRunningChanged: {
    drain.stop();
    if (root.running && root.duration > 0)
      drain.start();
  }
}
