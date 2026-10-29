pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.content.parts.custom

// Custom widgets page, Module tab: the module at its design size (scaled to
// fit), its elements drawn live from the script's output, over its lattice
// (4 sub-cells a grid unit). Click an element to select it, drag it to
// move it, drag its corner to resize it: each a plan from the editor's
// GridEditor (shown while dragging, pushing what it lands on), made on
// release.
Item {
  id: root

  // The page's card size (px), and the room the canvas may take
  required property real card
  property real maxHeight: 0

  readonly property var editor: CustomWidgetsManager.editor
  readonly property var grid: root.editor.elements
  readonly property var definition: root.editor.selected
  readonly property var size: root.definition?.module?.size ?? [4, 2]
  readonly property var lattice: CustomWidgetData.lattice(root.size)
  readonly property var elements: root.definition?.module?.elements ?? []
  readonly property real designWidth: GridPlacement.span(root.size[0], root.card)
  readonly property real designHeight: GridPlacement.span(root.size[1], root.card)
  readonly property real zoom: Math.min(1, root.width / Math.max(1, root.designWidth), root.maxHeight > 0 ? root.maxHeight / Math.max(1, root.designHeight) : 1)
  readonly property real pad: Widget.cardPadding
  readonly property real gap: Widget.px(6)
  readonly property real innerWidth: root.designWidth - root.pad * 2
  readonly property real innerHeight: root.designHeight - root.pad * 2
  readonly property real cellWidth: (root.innerWidth + root.gap) / root.lattice.cols
  readonly property real cellHeight: (root.innerHeight + root.gap) / root.lattice.rows

  // The plan being dragged (GridEditor's), null when none
  property var plan: null

  implicitHeight: root.designHeight * root.zoom

  function rectOf(place) {
    return CustomWidgetData.rect(place, root.lattice, root.innerWidth, root.innerHeight, root.gap);
  }

  Item {
    id: stage
    width: root.designWidth
    height: root.designHeight
    scale: root.zoom
    transformOrigin: Item.TopLeft

    Rectangle {
      anchors.fill: parent
      radius: Widget.radius
      color: Appearance.fill(Theme.background)
      border.color: Theme.border
      border.width: Appearance.borderWidth
    }

    // Clicking the empty card clears the selection
    MouseArea {
      anchors.fill: parent
      onClicked: root.grid.clearSelection()
    }

    Item {
      id: inner
      x: root.pad
      y: root.pad
      width: root.innerWidth
      height: root.innerHeight

      // The lattice, faint: one Canvas, not an item per cell
      Canvas {
        id: lattice
        anchors.fill: parent
        opacity: 0.35
        onPaint: {
          const ctx = getContext("2d");
          ctx.clearRect(0, 0, width, height);
          ctx.fillStyle = Theme.backgroundHighlight;
          for (let row = 0; row < root.lattice.rows; row++) {
            for (let col = 0; col < root.lattice.cols; col++)
              ctx.fillRect(col * root.cellWidth, row * root.cellHeight, Math.max(1, root.cellWidth - root.gap), Math.max(1, root.cellHeight - root.gap));
          }
        }
        Connections {
          target: root
          function onCellWidthChanged() {
            lattice.requestPaint();
          }
          function onCellHeightChanged() {
            lattice.requestPaint();
          }
        }
      }

      CustomLayout {
        anchors.fill: parent
        definition: root.definition
        fields: CustomWidgetsManager.fields[root.editor.selectedId] ?? ({})
        history: CustomWidgetsManager.history[root.editor.selectedId] ?? ({})
        actionsEnabled: false
        gap: root.gap
      }

      // Each element's frame: select, move, resize
      Repeater {
        model: root.elements.length

        Item {
          id: frame
          required property int index
          readonly property var place: root.elements[index]?.place ?? ({
              "x": 0,
              "y": 0,
              "w": 1,
              "h": 1
            })
          readonly property var r: root.rectOf(frame.place)
          readonly property bool selected: root.grid.selected === frame.index
          x: r.x
          y: r.y
          width: r.width
          height: r.height

          Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: Widget.px(3)
            border.width: frame.selected ? 2 : 1
            border.color: frame.selected ? Theme.accent : Qt.alpha(Theme.foreground, move.containsMouse ? 0.5 : 0.15)
          }

          MouseArea {
            id: move
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property point start
            onPressed: mouse => {
              root.grid.select(frame.index);
              start = mapToItem(inner, mouse.x, mouse.y);
            }
            onPositionChanged: mouse => {
              if (!pressed)
                return;
              const at = mapToItem(inner, mouse.x, mouse.y);
              const dx = Math.round((at.x - start.x) / root.cellWidth);
              const dy = Math.round((at.y - start.y) / root.cellHeight);
              root.plan = dx === 0 && dy === 0 ? null : root.grid.planMove(frame.index, frame.place.x + dx, frame.place.y + dy);
            }
            onReleased: {
              if (root.plan)
                root.grid.applyPlan(root.plan);
              root.plan = null;
            }
          }

          // The corner that resizes it
          Rectangle {
            visible: frame.selected
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Widget.px(12)
            height: width
            radius: width / 2
            color: Theme.accent

            MouseArea {
              anchors.fill: parent
              anchors.margins: -Widget.px(6)
              cursorShape: Qt.SizeFDiagCursor
              property point start
              onPressed: mouse => start = mapToItem(inner, mouse.x, mouse.y)
              onPositionChanged: mouse => {
                if (!pressed)
                  return;
                const at = mapToItem(inner, mouse.x, mouse.y);
                const w = Math.max(1, frame.place.w + Math.round((at.x - start.x) / root.cellWidth));
                const h = Math.max(1, frame.place.h + Math.round((at.y - start.y) / root.cellHeight));
                root.plan = w === frame.place.w && h === frame.place.h ? null : root.grid.planResize(frame.index, {
                  "x": frame.place.x,
                  "y": frame.place.y,
                  "w": Math.min(w, root.lattice.cols - frame.place.x),
                  "h": Math.min(h, root.lattice.rows - frame.place.y)
                });
              }
              onReleased: {
                if (root.plan)
                  root.grid.applyPlan(root.plan);
                root.plan = null;
              }
            }
          }
        }
      }

      // Where the dragged element would land
      Rectangle {
        readonly property var r: root.plan?.place ? root.rectOf(root.plan.place) : null
        visible: r !== null
        x: r?.x ?? 0
        y: r?.y ?? 0
        width: r?.width ?? 0
        height: r?.height ?? 0
        radius: Widget.px(3)
        color: Qt.alpha(root.plan?.valid ? Theme.accent : Theme.error, 0.2)
        border.width: 2
        border.color: root.plan?.valid ? Theme.accent : Theme.error
      }
    }
  }
}
