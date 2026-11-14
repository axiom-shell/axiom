pragma ComponentBehavior: Bound
import QtQuick
import QtQml
import QtQuick.Layouts
import qs.config

// A two- or three-way toggle: a SegmentTrack with each option's label in an
// equal segment, the thumb under the chosen one gliding across as it
// changes. With two options a click anywhere flips it, as a switch does;
// with three a click picks the segment under the pointer. The owner keeps
// the value: set `value`, and update it from `picked`.
Item {
  id: root

  // The option values (two or three), and the label each shows
  property var options: []
  property var labels: ({})
  property var value

  signal picked(var value)

  readonly property int _index: Math.max(0, root.options.indexOf(root.value))
  readonly property real _inset: track.inset
  readonly property real _segment: (root.width - root._inset * 2) / Math.max(1, root.options.length)
  // Each segment as wide as the widest label (measured Medium, the chosen
  // one's weight), so the thumb never resizes and no label elides
  readonly property real _widest: {
    let widest = 0;
    for (let i = 0; i < measures.count; i++)
      widest = Math.max(widest, (measures.objectAt(i) as TextMetrics)?.advanceWidth ?? 0);
    return Math.ceil(widest) + Widget.spacing * 3;
  }

  implicitWidth: root._widest * Math.max(1, root.options.length) + root._inset * 2
  implicitHeight: Widget.height - Widget.px(4)
  Layout.minimumWidth: root.implicitWidth

  activeFocusOnTab: true
  Keys.onSpacePressed: root._flip()
  Keys.onLeftPressed: root._step(-1)
  Keys.onRightPressed: root._step(1)

  // Two options: picks the other one
  function _flip() {
    if (root.options.length === 2)
      root.picked(root.options[1 - root._index]);
  }

  function _step(by) {
    const index = Math.max(0, Math.min(root.options.length - 1, root._index + by));
    if (index !== root._index)
      root.picked(root.options[index]);
  }

  // One metrics per option, unseen: the labels at their widest weight
  Instantiator {
    id: measures
    model: root.options

    TextMetrics {
      required property var modelData
      font.family: Appearance.fontFamily
      font.pixelSize: Style.typeLabel
      font.weight: Style.weightMedium
      text: root.labels[modelData] ?? ""
    }
  }

  SegmentTrack {
    id: track
    anchors.fill: parent
    count: root.options.length
    index: root._index
    // Today's capsule (the shape of the segment row is the toggle-shape FLAG)
    radius: height / 2

    FocusRing {
      shown: root.activeFocus
    }
  }

  Row {
    x: root._inset
    anchors.verticalCenter: parent.verticalCenter

    Repeater {
      model: root.options

      StyledLabel {
        required property var modelData
        required property int index
        width: root._segment
        horizontalAlignment: Text.AlignHCenter
        role: root._index === index ? "label" : "body"
        overflow: "none"
        text: root.labels[modelData] ?? ""
        textColor: root._index === index ? Style.inkOf(Style.segmentThumbTone).text : Style.inkOf(Style.segmentTrackTone).muted

        ColorGlide on textColor {
          duration: Appearance.animNormal
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: mouse => {
      if (root.options.length === 2)
        root._flip();
      else
        root.picked(root.options[Math.max(0, Math.min(root.options.length - 1, Math.floor((mouse.x - root._inset) / root._segment)))]);
    }
  }
}
