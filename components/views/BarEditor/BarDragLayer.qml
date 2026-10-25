pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.reusable

// The bar editor's widget area (sections board and inspector): a
// DragLayer whose ghost is drawn above both, so a widget can be carried
// out of the library or from one section to another. Its targets are the
// section lanes (SectionLane: `zone`, `indexAt`), and a TrashTarget a
// widget from a lane is dropped on to remove it. Payloads: { kind:
// "move" | "add", zone, index, type, compact (drawn as a lane's chip) }.
DragLayer {
  id: root

  // The section under the pointer
  readonly property string hoverZone: root.hoverTarget?.zone ?? ""
  // How long the carried chip is, for the gap a lane opens for it
  readonly property real ghostLength: root.vertical ? ghost.height : ghost.width

  readonly property string location: BarManager.selectedBar()?.location ?? "top"
  // The bar runs down a side of the screen
  readonly property bool barVertical: root.location === "left" || root.location === "right"
  // A top or bottom bar's sections drawn stacked down the left of the
  // page, as a side bar's (EditsManager.barStacked)
  readonly property bool stacked: !root.barVertical && EditsManager.barStacked
  // The sections are drawn top to bottom
  readonly property bool vertical: root.barVertical || root.stacked
  // The side of the page the sections are drawn along
  readonly property string side: root.stacked ? "left" : root.location
  // The bar's sections in order. On a vertical bar they run top to
  // bottom; the keys stay the same.
  readonly property var zones: [
    {
      "key": "left",
      "label": root.barVertical ? I18n.tr("Top") : I18n.tr("Left")
    },
    {
      "key": "leftCenter",
      "label": root.barVertical ? I18n.tr("Top Center") : I18n.tr("Left Center")
    },
    {
      "key": "center",
      "label": I18n.tr("Center")
    },
    {
      "key": "rightCenter",
      "label": root.barVertical ? I18n.tr("Bottom Center") : I18n.tr("Right Center")
    },
    {
      "key": "right",
      "label": root.barVertical ? I18n.tr("Bottom") : I18n.tr("Right")
    }
  ]

  function zoneLabel(key) {
    return root.zones.find(z => z.key === key)?.label ?? key;
  }

  function typeInfo(type) {
    return Bar.availableWidgetTypes.find(t => t.type === type) ?? null;
  }

  // The type's label (its schema description), translated like titles
  function label(type) {
    const info = root.typeInfo(type);
    return info ? I18n.tr(info.label) : (type || I18n.tr("Unknown"));
  }

  // A short name for chips in the section lanes: the type, spaced.
  // Keys: I18n.tr("Window") I18n.tr("Media") I18n.tr("Workspaces")
  // I18n.tr("Time") I18n.tr("Tailscale")
  // I18n.tr("Network") I18n.tr("System Tray") I18n.tr("Notifications")
  // I18n.tr("Button") I18n.tr("Battery") I18n.tr("System Stats")
  // I18n.tr("Keyboard Layout") I18n.tr("Idle Inhibitor") I18n.tr("Privacy")
  // I18n.tr("Updates") I18n.tr("Weather") I18n.tr("Separator")
  // I18n.tr("Volume") I18n.tr("Microphone") I18n.tr("Bluetooth")
  // I18n.tr("Screen Record")
  function shortLabel(type) {
    if (!type)
      return I18n.tr("Unknown");
    return I18n.tr(Utils.spaceWords(type));
  }

  // The type's Material Symbols icon (its schema `x-icon`)
  function icon(type) {
    return root.typeInfo(type)?.icon ?? "widgets";
  }

  onStarted: (payload, item, x, y) => {
    ghost.type = payload.type;
    ghost.compact = payload.compact === true;
    ghost.width = item.width;
    ghost.hotX = x;
    ghost.hotY = y;
  }
  onMoved: point => {
    ghost.x = point.x - ghost.hotX;
    ghost.y = point.y - ghost.hotY;
  }
  // Only a widget already on the bar goes in the trash
  accepts: (target, drag) => target.targetKind !== "trash" || drag.kind === "move"

  // Moves or adds the widget where it was dropped, or removes it
  onDropped: (drag, target, index) => {
    if (target.targetKind === "trash")
      BarManager.removeWidget(drag.zone, drag.index);
    else if (drag.kind === "move")
      BarManager.moveWidget(drag.zone, drag.index, target.zone, index);
    else
      BarManager.addWidget(target.zone, drag.type, index);
  }

  // Away from the bar's edge, in the middle of the inspector side
  TrashTarget {
    x: (root.width - width) / 2
    y: root.side === "bottom" ? Widget.padding : root.height - height - Widget.padding
    dragLayer: root
    active: root.dragging?.kind === "move"
  }

  WidgetChip {
    id: ghost

    property real hotX: 0
    property real hotY: 0

    dragLayer: root
    visible: root.dragging !== null
    enabled: false
    selected: true
    z: 10
    opacity: 0.9
    scale: 1.04
  }
}
