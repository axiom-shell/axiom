pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.reusable

// One bar section in the bar editor's strip: its widgets in bar order,
// along the strip (top to bottom on a vertical bar). Chips can be dragged
// within it, to another lane, or dropped on it from the library; the chips
// past the drop point slide aside to show where it would land.
Rectangle {
  id: root

  required property var dragLayer
  // The section's key in the bar's `widgets`
  required property string zone
  required property string title
  // Chips run top to bottom (a vertical bar's), else left to right
  required property bool vertical
  // The selected bar's running copies (BarManager.liveReports)
  required property var reports

  readonly property var widgets: BarManager.selectedBar()?.widgets?.[root.zone] ?? []
  readonly property bool hovering: root.dragLayer.hoverZone === root.zone
  readonly property real chipHeight: Widget.height + Widget.padding / 2
  // The widgets a running copy hides for want of room
  readonly property var crowded: [].concat(...root.reports.map(report => report.hidden[root.zone] ?? []))
  // More chips than the lane has room for: they scroll, with a bar beside
  // (below a horizontal lane's, right of a vertical one's)
  readonly property bool overflowing: root.vertical ? chips.implicitHeight > flick.height : chips.implicitWidth > flick.width
  readonly property real scrollBarRoom: 8
  // The room a drop opens: the carried chip's length
  readonly property real gap: (root.vertical ? root.chipHeight : root.dragLayer.ghostLength) + Widget.spacing

  // Along the strip: the length that shows every chip, and the least it
  // takes (the chips scroll)
  readonly property real naturalLength: Widget.padding * 2 + (root.vertical ? header.implicitHeight + Widget.spacing + Math.max(root.chipHeight, chips.implicitHeight) : Math.max(header.implicitWidth, chips.implicitWidth, empty.implicitWidth))
  readonly property real minLength: Widget.padding * 2 + (root.vertical ? header.implicitHeight + Widget.spacing + root.chipHeight : Widget.height * 2)
  // Across it, with room for the scroll bar
  readonly property real depth: Widget.padding * 2 + header.implicitHeight + Widget.spacing + root.chipHeight + root.scrollBarRoom

  // Where the carried chip would land, along the chips
  readonly property real landingPos: {
    const at = root.dragLayer.hoverIndex;
    const chip = at >= 0 && at < repeater.count ? repeater.itemAt(at) : null;
    if (chip)
      return root.vertical ? chip.y : chip.x;
    return repeater.count === 0 ? 0 : (root.vertical ? chips.implicitHeight : chips.implicitWidth) + Widget.spacing;
  }

  component LaneScrollBar: ScrollBar {
    id: laneBar
    padding: 1
    contentItem: Rectangle {
      implicitWidth: root.scrollBarRoom - 2
      implicitHeight: root.scrollBarRoom - 2
      radius: height / 2
      color: Theme.accent
      opacity: laneBar.pressed ? 0.8 : 0.4
    }
  }

  // `anchor`: the + button, so the picker opens beside it
  signal addRequested(Item anchor)

  radius: Widget.radius
  color: root.hovering ? Qt.alpha(Theme.accent, 0.1) : Theme.background
  border.color: root.hovering ? Theme.accent : Theme.border
  border.width: 1

  ColorGlide on color {}

  Component.onCompleted: root.dragLayer.registerTarget(root)
  Component.onDestruction: root.dragLayer.unregisterTarget(root)

  // Where a drop at `point` (in the drag layer) would insert: before the
  // first chip whose middle is past it
  function indexAt(point) {
    const p = root.dragLayer.mapToItem(chips, point.x, point.y);
    for (let i = 0; i < repeater.count; i++) {
      const chip = repeater.itemAt(i);
      if (chip && (root.vertical ? p.y < chip.y + chip.height / 2 : p.x < chip.x + chip.width / 2))
        return i;
    }
    return repeater.count;
  }

  // The wheel scrolls the chips, sideways along a horizontal lane
  WheelHandler {
    enabled: root.overflowing
    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => {
      const pixels = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.pixelDelta.x;
      const angle = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
      const step = pixels !== 0 ? pixels : angle / 120 * Appearance.fontSize * 4;
      if (root.vertical)
        flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY - step));
      else
        flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - step));
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Widget.padding
    spacing: Widget.spacing

    RowLayout {
      id: header
      Layout.fillWidth: true
      spacing: Widget.spacing / 2

      StyledText {
        text: root.title
        font.bold: true
        elide: Text.ElideRight
        Layout.fillWidth: true
      }

      // Center only: pin it dead center so the other sections can't push it
      SquareIconButton {
        readonly property bool locked: BarManager.selectedBar()?.lockCenter ?? false

        visible: root.zone === "center"
        size: Widget.height - Widget.px(6)
        iconText: locked ? "lock" : "lock_open"
        iconSize: Appearance.fontSizeBy(-1)
        iconColor: locked ? Theme.background : Theme.foreground
        backgroundColor: Qt.alpha(Theme.accent, locked ? 1 : 0)
        tooltipText: I18n.tr(locked ? "Center locked: it stays dead center, other sections make room" : "Lock the center section in place")
        onClicked: BarManager.updateBarField("lockCenter", !locked)
      }

      SquareIconButton {
        id: addButton
        size: Widget.height - Widget.px(6)
        iconText: "add"
        backgroundColor: "transparent"
        tooltipText: I18n.tr("Add a widget")
        onClicked: root.addRequested(addButton)
      }
    }

    Flickable {
      id: flick
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      // Room past the last chip for the gap a drop opens
      contentWidth: root.vertical ? width : chips.implicitWidth + root.gap
      contentHeight: root.vertical ? chips.implicitHeight + root.gap : height
      flickableDirection: root.vertical ? Flickable.VerticalFlick : Flickable.HorizontalFlick
      boundsBehavior: Flickable.StopAtBounds
      // Chips take mouse drags; the wheel scrolls (below)
      interactive: false

      ScrollBar.horizontal: LaneScrollBar {
        policy: !root.vertical && root.overflowing ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
      }
      ScrollBar.vertical: LaneScrollBar {
        policy: root.vertical && root.overflowing ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
      }

      // Where the dragged widget would land
      Rectangle {
        visible: root.hovering
        x: root.vertical ? 0 : root.landingPos
        y: root.vertical ? root.landingPos : 0
        width: root.vertical ? flick.width : root.gap - Widget.spacing
        height: root.chipHeight
        radius: Widget.radius
        color: Qt.alpha(Theme.accent, 0.12)
        border.color: Theme.accent
        border.width: 1
      }

      Grid {
        id: chips
        columns: root.vertical ? 1 : Math.max(1, repeater.count)
        spacing: Widget.spacing

        // Keyed by count: edits to a widget update its chip in place
        Repeater {
          id: repeater
          model: root.widgets.length

          delegate: WidgetChip {
            id: chip
            required property int index
            readonly property var widget: root.widgets[index] ?? ({})
            // Chips at and past the drop point make room for it
            readonly property real shift: root.hovering && chip.index >= root.dragLayer.hoverIndex ? root.gap : 0

            dragLayer: root.dragLayer
            compact: true
            width: root.vertical ? flick.width - (root.overflowing ? root.scrollBarRoom : 0) : implicitWidth
            height: root.chipHeight
            type: chip.widget.type ?? ""
            hiddenWidget: chip.widget.visible === false
            crowded: root.crowded.includes(chip.index)
            selected: BarManager.selectedWidget.zone === root.zone && BarManager.selectedWidget.index === chip.index
            faded: root.dragLayer.dragging?.kind === "move" && root.dragLayer.dragging.zone === root.zone && root.dragLayer.dragging.index === chip.index
            payload: ({
                "kind": "move",
                "zone": root.zone,
                "index": chip.index,
                "type": chip.type,
                "compact": true
              })
            onClicked: BarManager.selectWidget(root.zone, chip.index)

            transform: Translate {
              x: root.vertical ? 0 : chip.shift
              y: root.vertical ? chip.shift : 0

              Behavior on x {
                NumberAnimation {
                  duration: Appearance.animFast
                  easing.type: Easing.OutCubic
                }
              }
              Behavior on y {
                NumberAnimation {
                  duration: Appearance.animFast
                  easing.type: Easing.OutCubic
                }
              }
            }
          }
        }
      }

      StyledText {
        id: empty
        visible: repeater.count === 0 && !root.hovering
        width: flick.width
        height: root.chipHeight
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: I18n.tr("Drop widgets here")
        opacity: 0.45
        textSize: Appearance.fontSizeBy(-1)
      }
    }
  }
}
