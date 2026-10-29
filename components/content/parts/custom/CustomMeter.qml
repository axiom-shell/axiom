pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A custom widget's Bar element: a track filled to the value between min
// and max, across or up by its shape. With a change command it's a slider:
// dragging shows the new value, releasing runs the command with {value}
// (between min and max), and the value holds until the next sample.
// slots: value, min, max; options: color, step
CustomElementBase {
  id: root

  readonly property bool vertical: root.height > root.width * 1.5
  readonly property bool interactive: root.actionsEnabled && (root.actions.change ?? "") !== ""
  readonly property real lo: root.range.min
  readonly property real hi: root.range.max
  // The dragged or just-set share, until the next sample
  property real held: -1
  property bool dragging: false
  readonly property real share: root.held >= 0 ? root.held : Math.max(0, root.ratio())
  readonly property real thickness: Math.max(Widget.px(4), Math.min(Widget.px(14), (root.vertical ? root.width : root.height)))

  onFieldsChanged: if (!root.dragging)
    root.held = -1

  function shareAt(x, y) {
    const s = root.vertical ? 1 - y / Math.max(1, root.height) : x / Math.max(1, root.width);
    return Math.max(0, Math.min(1, s));
  }

  function valueOf(share) {
    const step = parseFloat(root.opt("step", 1));
    const v = root.lo + share * (root.hi - root.lo);
    return step > 0 ? Math.round(v / step) * step : v;
  }

  Rectangle {
    id: track
    anchors.centerIn: parent
    width: root.vertical ? root.thickness : root.width
    height: root.vertical ? root.height : root.thickness
    radius: root.thickness / 2
    color: Theme.backgroundHighlight

    Rectangle {
      x: 0
      y: root.vertical ? parent.height - height : 0
      width: root.vertical ? parent.width : Math.max(parent.radius * 2 * (root.share > 0 ? 1 : 0), parent.width * root.share)
      height: root.vertical ? Math.max(parent.radius * 2 * (root.share > 0 ? 1 : 0), parent.height * root.share) : parent.height
      radius: parent.radius
      color: root.colorOf("color", Theme.accent)

      Behavior on width {
        enabled: !root.dragging
        NumberAnimation {
          duration: Appearance.animFast
          easing.type: Appearance.easing
        }
      }
      Behavior on height {
        enabled: !root.dragging
        NumberAnimation {
          duration: Appearance.animFast
          easing.type: Appearance.easing
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.interactive
    cursorShape: Qt.PointingHandCursor
    onPressed: mouse => {
      root.dragging = true;
      root.held = root.shareAt(mouse.x, mouse.y);
    }
    onPositionChanged: mouse => {
      if (pressed)
        root.held = root.shareAt(mouse.x, mouse.y);
    }
    onReleased: mouse => {
      root.held = root.shareAt(mouse.x, mouse.y);
      root.dragging = false;
      root.act("change", root.valueOf(root.held));
    }
  }
}
