pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.config
import qs.components.methods
import qs.components.reusable

// A small screen showing where something sits (`spot`, 0-1 from the top
// left), with `presets` to click: dots that each apply their values, and
// a drag anywhere on it that places it on the nearest edge (`floats`:
// also how far across, held off the edge unless dropped at it). Placed
// anywhere (`floats`), the dots are the same nine for every surface: the
// centre, each edge's middle and the corners, each placing it as a drag
// there would. Used for docks and OSDs (EntryListCard), the launcher and
// window switcher (PlaceIntro), and notifications (NotificationsPreview,
// its own dots).
Rectangle {
  id: root

  // [{ label, values, x, y }]: a dot at (x, y) (0-1 from the top left) that
  // applies `values` (by default where a drag to it would place it); the
  // label is its tooltip, an I18n key its giver declares
  property var presets: root.floats ? root.placeSpots : []
  // I18n.tr("Center") I18n.tr("Top") I18n.tr("Bottom") I18n.tr("Left")
  // I18n.tr("Right") I18n.tr("Top left") I18n.tr("Top right")
  // I18n.tr("Bottom left") I18n.tr("Bottom right")
  readonly property var placeSpots: [
    {
      "label": "Center",
      "x": 0.5,
      "y": 0.5
    },
    {
      "label": "Top",
      "x": 0.5,
      "y": 0
    },
    {
      "label": "Bottom",
      "x": 0.5,
      "y": 1
    },
    {
      "label": "Left",
      "x": 0,
      "y": 0.5
    },
    {
      "label": "Right",
      "x": 1,
      "y": 0.5
    },
    {
      "label": "Top left",
      "x": 0,
      "y": 0
    },
    {
      "label": "Top right",
      "x": 1,
      "y": 0
    },
    {
      "label": "Bottom left",
      "x": 0,
      "y": 1
    },
    {
      "label": "Bottom right",
      "x": 1,
      "y": 1
    }
  ]
  property point spot: Qt.point(0.5, 0.5)
  // Its edge now (a name), which a drag through the middle keeps
  property string edge: "bottom"
  // Placed anywhere (`detached` with a `distance` across, as the launcher):
  // a drag sets those too; else only `edge` and `position`
  property bool floats: false
  // How near an edge (0-1 of the screen) a floating drag attaches it
  readonly property real snap: 0.04
  readonly property real dot: 14
  property string _lastDrag: ""

  // A preset was clicked, or a drag moved it: the values to apply
  signal picked(var values)

  // The values for a spot dragged to (0-1 from the top left)
  function _dragValues(x, y) {
    const place = ScreenEdge.spotPlace(x, y, root.edge);
    const values = {
      "edge": place.edge,
      "position": Math.round(place.along * 100)
    };
    if (root.floats) {
      values.detached = place.across >= root.snap;
      if (values.detached)
        values.distance = Math.round(place.across * 100);
    }
    return values;
  }

  implicitWidth: Widget.px(192)
  implicitHeight: Widget.px(108)
  color: Theme.background
  border.color: Theme.border
  border.width: Appearance.borderWidth
  radius: Widget.radius / 2

  // A press or drag anywhere places it there; the dots, over it, apply
  // their presets
  MouseArea {
    anchors.fill: parent
    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    onPressed: mouse => placeAt(mouse)
    onPositionChanged: mouse => placeAt(mouse)
    onReleased: root._lastDrag = ""

    // Applied only when the values change (whole percents)
    function placeAt(mouse) {
      const values = root._dragValues((mouse.x - root.dot / 2) / (root.width - root.dot), (mouse.y - root.dot / 2) / (root.height - root.dot));
      const key = JSON.stringify(values);
      if (key === root._lastDrag)
        return;
      root._lastDrag = key;
      root.picked(values);
    }
  }

  Repeater {
    model: root.presets

    delegate: Rectangle {
      id: preset
      required property var modelData
      readonly property bool hovered: presetArea.containsMouse

      width: root.dot
      height: root.dot
      radius: width / 2
      x: modelData.x * (root.width - width)
      y: modelData.y * (root.height - height)
      color: hovered ? Theme.accentAlt : Theme.backgroundHighlight
      border.color: Theme.border
      border.width: 1

      MouseArea {
        id: presetArea
        anchors.fill: parent
        anchors.margins: -Widget.px(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked(preset.modelData.values ?? root._dragValues(preset.modelData.x, preset.modelData.y))
      }

      LazyLoader {
        active: preset.hovered
        StyledToolTip {
          target: preset
          text: I18n.tr(preset.modelData.label)
        }
      }
    }
  }

  // Where it is now
  Rectangle {
    width: root.dot - Widget.px(4)
    height: root.dot - Widget.px(4)
    radius: width / 2
    x: root.spot.x * (root.width - root.dot) + 2
    y: root.spot.y * (root.height - root.dot) + 2
    color: Theme.accent
  }
}
