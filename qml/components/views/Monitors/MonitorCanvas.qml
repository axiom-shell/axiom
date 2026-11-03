pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.reusable
import qs.components.methods

// The selected profile's layout, scaled to fit: a tile per monitor laid out
// on its own, dragged to move it. A dragged tile snaps to the others' edges
// and centres when it comes within `snapDistance` screen pixels, and stays
// where it's dropped otherwise, so any offset can be set. Monitors that are
// off or mirroring are listed under the layout.
ColumnLayout {
  id: root

  readonly property var rules: MonitorManager.placedRules
  readonly property var rects: MonitorManager.placedRects
  readonly property var others: MonitorManager.rules.filter(rule => rule.disabled || rule.mirror)

  readonly property real snapDistance: 14

  // The drag in progress: the output, its start and where it is now
  property string dragOutput: ""
  property var _start: null
  property point dragPos: Qt.point(0, 0)
  property var guides: []
  // The view is held still while dragging, so the layout doesn't re-fit
  // under the pointer
  property var _heldView: null

  spacing: Widget.spacing

  // { scale, x, y }: layout pixels to canvas pixels, the bounds centred
  readonly property var _fitView: {
    const bounds = MonitorLayout.bounds(root.rects);
    const margin = Widget.padding * 3;
    const scale = Math.max(0.01, Math.min((board.width - margin * 2) / bounds.width, (board.height - margin * 2) / bounds.height));
    return {
      "scale": scale,
      "x": bounds.x - (board.width / scale - bounds.width) / 2,
      "y": bounds.y - (board.height / scale - bounds.height) / 2
    };
  }
  readonly property var view: _heldView ?? _fitView

  function begin(index, point) {
    const rule = root.rules[index];
    const rect = root.rects[index];
    MonitorManager.selectedOutput = rule.output;
    root._heldView = root._fitView;
    root._start = {
      "x": rect.x,
      "y": rect.y,
      "px": point.x,
      "py": point.y,
      "width": rect.width,
      "height": rect.height,
      "others": root.rects.filter((_, i) => i !== index)
    };
    root.dragPos = Qt.point(rect.x, rect.y);
    root.dragOutput = rule.output;
  }

  function moveTo(point) {
    const start = root._start;
    if (!start)
      return;
    const scale = root.view.scale;
    const snapped = MonitorLayout.snap({
      "x": start.x + (point.x - start.px) / scale,
      "y": start.y + (point.y - start.py) / scale,
      "width": start.width,
      "height": start.height
    }, start.others, root.snapDistance / scale);
    root.dragPos = Qt.point(snapped.x, snapped.y);
    root.guides = snapped.guides;
  }

  function end(commit) {
    if (commit && root._start)
      MonitorManager.move(root.dragOutput, root.dragPos.x, root.dragPos.y);
    root.dragOutput = "";
    root._start = null;
    root.guides = [];
    root._heldView = null;
  }

  Rectangle {
    id: board
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: Widget.height * 6
    color: Theme.backgroundAlt
    radius: Widget.radius
    border.color: Theme.border
    border.width: Appearance.borderWidth
    clip: true

    // A click on the empty board clears nothing, but takes focus from a field
    MouseArea {
      anchors.fill: parent
      onClicked: board.forceActiveFocus()
    }

    Repeater {
      model: root.rules.length

      delegate: Rectangle {
        id: tile

        required property int index
        readonly property var rule: root.rules[index] ?? null
        readonly property var rect: root.rects[index] ?? ({
            "x": 0,
            "y": 0,
            "width": 0,
            "height": 0
          })
        readonly property bool dragging: root.dragOutput !== "" && root.dragOutput === rule?.output
        readonly property bool selected: MonitorManager.selectedOutput === rule?.output
        readonly property var monitor: MonitorManager.monitorFor(rule)
        readonly property bool primary: !!monitor && monitor.name === General.primaryMonitor
        readonly property var mode: MonitorLayout.parseMode(rule?.mode)

        x: ((dragging ? root.dragPos.x : rect.x) - root.view.x) * root.view.scale
        y: ((dragging ? root.dragPos.y : rect.y) - root.view.y) * root.view.scale
        width: rect.width * root.view.scale
        height: rect.height * root.view.scale
        z: dragging ? 2 : selected ? 1 : 0
        radius: Widget.radius
        color: selected ? Qt.alpha(Theme.accent, 0.25) : Theme.backgroundHighlight
        border.color: selected ? Theme.accent : Theme.border
        border.width: Appearance.borderWidth * (selected ? 2 : 1)
        opacity: monitor ? 1 : 0.55

        ColumnLayout {
          anchors.centerIn: parent
          width: parent.width - Widget.padding
          spacing: 2

          RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Widget.spacing

            StyledIcon {
              visible: tile.primary
              text: "star"
              fill: 1
              textColor: Theme.accent
            }

            StyledText {
              text: MonitorManager.labelFor(tile.rule)
              font.bold: true
              elide: Text.ElideRight
              Layout.maximumWidth: tile.width - Widget.padding * 2
            }
          }

          StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: tile.width - Widget.padding
            elide: Text.ElideRight
            opacity: 0.7
            textSize: Appearance.fontSizeBy(-2)
            text: tile.mode ? I18n.tr("{0}×{1} @ {2} Hz", tile.mode.width, tile.mode.height, MonitorLayout.formatRate(tile.mode.rate)) : I18n.tr("Preferred mode")
          }

          StyledText {
            visible: !tile.monitor
            Layout.alignment: Qt.AlignHCenter
            opacity: 0.7
            textSize: Appearance.fontSizeBy(-2)
            text: I18n.tr("Not connected")
          }
        }

        DragArea {
          anchors.fill: parent
          onTapped: MonitorManager.selectedOutput = tile.rule.output
          onDragStarted: (x, y) => root.begin(tile.index, mapToItem(board, x, y))
          onDragMoved: (x, y) => root.moveTo(mapToItem(board, x, y))
          onDropped: root.end(true)
          onDragCanceled: root.end(false)
        }
      }
    }

    // The lines a dragged tile snapped to (by count: `guides` is a new
    // array on every move)
    Repeater {
      model: root.guides.length

      delegate: Rectangle {
        id: guideLine
        required property int index
        readonly property var guide: root.guides[guideLine.index] ?? {
          "axis": "x",
          "at": 0
        }
        readonly property bool vertical: guide.axis === "x"
        z: 3
        color: Theme.accent
        x: vertical ? (guide.at - root.view.x) * root.view.scale : 0
        y: vertical ? 0 : (guide.at - root.view.y) * root.view.scale
        width: vertical ? 1 : board.width
        height: vertical ? board.height : 1
      }
    }
  }

  // Monitors that aren't in the layout: off, or mirroring another
  Flow {
    visible: root.others.length > 0
    Layout.fillWidth: true
    spacing: Widget.spacing

    Repeater {
      model: root.others.length

      delegate: SegmentButton {
        required property int index
        readonly property var rule: root.others[index]
        readonly property bool selected: MonitorManager.selectedOutput === rule.output
        implicitHeight: Widget.height
        iconText: rule.disabled ? "desktop_access_disabled" : "screen_share"
        text: rule.disabled ? I18n.tr("{0}: off", MonitorManager.labelFor(rule)) : I18n.tr("{0}: mirrors {1}", MonitorManager.labelFor(rule), MonitorManager.labelFor(MonitorManager.rules.find(other => other.output === rule.mirror) ?? {
          "output": rule.mirror
        }))
        active: selected
        onClicked: MonitorManager.selectedOutput = rule.output
      }
    }
  }
}
