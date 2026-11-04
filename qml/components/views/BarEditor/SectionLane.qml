pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services.ui
import qs.components.reusable

// One bar section on the bar editor's board: its title and buttons, then
// its widgets in bar order as chips that wrap (a Flow): a row across the
// board for a top or bottom bar, a column down it for a side bar, never
// scrolling. Chips are dragged within it, to another lane, or dropped on
// it from the library; a line shows where the carried one would land.
// Hovering a chip outlines its widget on the running bars; a chip whose
// widget the pointer is over on a running bar looks hovered. Its header's
// meter shows how much of the section's room its widgets want on the
// narrowest screen.
Rectangle {
  id: root

  required property var dragLayer
  // The section's key in the bar's `widgets`
  required property string zone
  required property string title
  // A column (a side bar's lane: chips top to bottom, wrapping into
  // columns), else a row (left to right, wrapping into rows)
  required property bool vertical
  // The selected bar's running copies (BarManager.liveReports)
  required property var reports
  // Each widget's drop order (BarLayout.dropOrder), or [] for no badges
  property var dropOrders: []
  // How the section fits on the narrowest screen ({used, room}, the
  // running bar's report), or null for no meter; and that screen's name
  property var fit: null
  property string fitScreen: ""
  readonly property bool overfull: root.fit !== null && root.fit.used > root.fit.room
  // The widest a chip may be (a column's share of a narrow board): its
  // label elides past it
  property real maxChipWidth: Infinity

  readonly property var widgets: BarManager.selectedBar()?.widgets?.[root.zone] ?? []
  readonly property bool hovering: root.dragLayer.hoverZone === root.zone
  readonly property real chipHeight: Widget.height + Widget.padding / 2
  // The widgets a running copy hides for want of room
  readonly property var crowded: [].concat(...root.reports.map(report => report.hidden[root.zone] ?? []))

  // Where the carried chip would land: before the chip at the drop index,
  // or after the last
  readonly property var landing: {
    const at = root.dragLayer.hoverIndex;
    const chip = at >= 0 && at < repeater.count ? repeater.itemAt(at) : null;
    const last = repeater.count > 0 ? repeater.itemAt(repeater.count - 1) : null;
    const half = flow.spacing / 2;
    if (chip)
      return root.vertical ? Qt.rect(chip.x, chip.y - half, chip.width, 0) : Qt.rect(chip.x - half, chip.y, 0, chip.height);
    if (last)
      return root.vertical ? Qt.rect(last.x, last.y + last.height + half, last.width, 0) : Qt.rect(last.x + last.width + half, last.y, 0, last.height);
    return root.vertical ? Qt.rect(0, 0, flow.width, 0) : Qt.rect(0, 0, 0, root.chipHeight);
  }

  // `anchor`: the + button, so the picker opens beside it
  signal addRequested(Item anchor)
  // A chip's right click, at (x, y) in the chip
  signal menuRequested(int index, Item chip, real x, real y)
  // A chip was clicked (the board takes the keys then)
  signal chipClicked(int index)

  implicitWidth: Widget.padding * 2 + (root.vertical ? Math.min(Math.max(header.implicitWidth, flow.implicitWidth, empty.implicitWidth), Math.max(root.maxChipWidth, flow.implicitWidth)) : header.implicitWidth)
  implicitHeight: Widget.padding * 2 + header.implicitHeight + Widget.spacing + (root.vertical ? root.chipHeight : Math.max(root.chipHeight, flow.implicitHeight))
  radius: Widget.radius
  color: root.hovering ? Qt.alpha(Theme.accent, 0.1) : Theme.background
  border.color: root.hovering ? Theme.accent : Theme.border
  border.width: 1

  ColorGlide on color {}

  Component.onCompleted: root.dragLayer.registerTarget(root)
  Component.onDestruction: root.dragLayer.unregisterTarget(root)

  // Where a drop at `point` (in the drag layer) would insert: before the
  // first chip on a later line (row, or column) than the point, or on its
  // line past it. Both axes, since the chips wrap
  function indexAt(point) {
    const p = root.dragLayer.mapToItem(flow, point.x, point.y);
    const across = root.vertical ? p.x : p.y;
    const along = root.vertical ? p.y : p.x;
    for (let i = 0; i < repeater.count; i++) {
      const chip = repeater.itemAt(i);
      if (!chip)
        continue;
      const lineStart = root.vertical ? chip.x : chip.y;
      const lineEnd = lineStart + (root.vertical ? chip.width : chip.height) + flow.spacing;
      const middle = root.vertical ? chip.y + chip.height / 2 : chip.x + chip.width / 2;
      if (across < lineStart || (across < lineEnd && along < middle))
        return i;
    }
    return repeater.count;
  }

  RowLayout {
    id: header
    x: Widget.padding
    y: Widget.padding
    width: parent.width - Widget.padding * 2
    spacing: Widget.spacing / 2

    StyledText {
      text: root.title
      font.bold: true
      elide: Text.ElideRight
      Layout.fillWidth: true
    }

    // How full the section is
    LevelMeter {
      id: meter
      visible: root.fit !== null && root.widgets.length > 0
      Layout.preferredWidth: Widget.px(40)
      Layout.preferredHeight: Widget.height - Widget.px(6)
      thickness: Widget.px(4)
      share: root.fit && root.fit.room > 0 ? root.fit.used / root.fit.room : 1
      fillColor: root.overfull ? Theme.warning : Theme.accent

      HoverHandler {
        id: meterHover
      }
      LazyLoader {
        active: meterHover.hovered
        StyledToolTip {
          target: meter
          text: root.overfull ? I18n.tr("Wants {0} px, has {1} px on {2}", root.fit?.used ?? 0, root.fit?.room ?? 0, root.fitScreen) : I18n.tr("{0} of {1} px used on {2}", root.fit?.used ?? 0, root.fit?.room ?? 0, root.fitScreen)
        }
      }
    }

    // Center only: pin it dead center so the other sections can't push it
    SquareIconButton {
      readonly property bool locked: BarManager.selectedBar()?.lockCenter ?? false

      visible: root.zone === "center"
      size: Widget.height - Widget.px(6)
      iconText: locked ? "lock" : "lock_open"
      iconSize: Appearance.fontSizeBy(-1)
      iconColor: locked ? Theme.background : Theme.foreground
      backgroundColor: locked ? Theme.accent : Theme.backgroundAlt
      tooltipText: I18n.tr(locked ? "Center locked: it stays dead center, other sections make room" : "Lock the center section in place")
      onClicked: BarManager.updateBarField("lockCenter", !locked)
    }

    SquareIconButton {
      id: addButton
      size: Widget.height - Widget.px(6)
      iconText: "add"
      tooltipText: I18n.tr("Add a widget")
      onClicked: root.addRequested(addButton)
    }
  }

  Flow {
    id: flow
    x: Widget.padding
    y: header.y + header.implicitHeight + Widget.spacing
    // A row's chips wrap at its width; a column's at its height, the lane
    // growing sideways with the columns
    width: root.vertical ? implicitWidth : root.width - Widget.padding * 2
    height: root.vertical ? root.height - y - Widget.padding : implicitHeight
    flow: root.vertical ? Flow.TopToBottom : Flow.LeftToRight
    spacing: Widget.spacing

    // Keyed by count: edits to a widget update its chip in place
    Repeater {
      id: repeater
      model: root.widgets.length

      delegate: WidgetChip {
        id: chip
        required property int index
        readonly property var entry: root.widgets[index] ?? ({})

        dragLayer: root.dragLayer
        compact: true
        // On a side bar, live widgets run down (as the preview bar draws
        // them): a column as wide as a row chip is high
        vertical: root.vertical
        width: Math.min(implicitWidth, root.maxChipWidth)
        height: chip._column ? implicitHeight : root.chipHeight
        type: root.dragLayer.libraryKey(chip.entry)
        // With its Auto colours picked, as the bar draws it
        widget: BarManager.previewConfig?.widgets?.[root.zone]?.[chip.index] ?? chip.entry
        previewConfig: BarManager.previewConfig
        maxPreviewLength: root.vertical ? Widget.px(260) : Math.min(Widget.px(260), root.maxChipWidth - Widget.padding)
        hiddenWidget: chip.entry.visible === false
        crowded: root.crowded.includes(chip.index)
        dropOrder: root.dropOrders[chip.index] ?? 0
        selected: BarManager.selectedWidget.zone === root.zone && BarManager.selectedWidget.index === chip.index
        highlighted: BarManager.isBarHovered(root.zone, chip.index)
        faded: root.dragLayer.dragging?.kind === "move" && root.dragLayer.dragging.zone === root.zone && root.dragLayer.dragging.index === chip.index
        payload: ({
            "kind": "move",
            "zone": root.zone,
            "index": chip.index,
            "type": chip.type,
            "compact": true
          })
        onClicked: {
          BarManager.selectWidget(root.zone, chip.index);
          root.chipClicked(chip.index);
        }
        onMenuRequested: (x, y) => root.menuRequested(chip.index, chip, x, y)
        onHoveredChanged: {
          if (chip.hovered)
            BarManager.setHoveredWidget(root.zone, chip.index);
          else if (BarManager.hoveredWidget.zone === root.zone && BarManager.hoveredWidget.index === chip.index)
            BarManager.setHoveredWidget("", -1);
        }
      }
    }
  }

  StyledText {
    id: empty
    visible: repeater.count === 0 && !root.hovering
    x: flow.x
    y: flow.y
    width: root.vertical ? implicitWidth : flow.width
    height: root.chipHeight
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
    text: I18n.tr("Drop widgets here")
    opacity: 0.45
    textSize: Appearance.fontSizeBy(-1)
  }

  // Where the dragged widget would land
  Rectangle {
    visible: root.hovering
    x: flow.x + root.landing.x - (root.vertical ? 0 : 1)
    y: flow.y + root.landing.y - (root.vertical ? 1 : 0)
    width: root.vertical ? Math.max(root.landing.width, root.chipHeight) : 2
    height: root.vertical ? 2 : root.landing.height
    radius: 1
    color: Theme.accent
  }
}
