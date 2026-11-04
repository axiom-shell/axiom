pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.ui
import qs.components.reusable

// The bar editor's widget area (sections board and inspector): a
// DragLayer whose ghost is drawn above both, so a widget can be carried
// out of the library or from one section to another. Its targets are the
// section lanes (SectionLane: `zone`, `indexAt`), and the board's
// TrashTarget a widget from a lane is dropped on to remove it. Payloads: { kind:
// "move" | "add", zone, index, type, compact (drawn as a lane's chip) }.
DragLayer {
  id: root

  // The section under the pointer
  readonly property string hoverZone: root.hoverTarget?.zone ?? ""

  readonly property string location: BarManager.selectedBar()?.location ?? "top"
  // The bar runs down a side of the screen (its sections are then named
  // Top, Center, Bottom)
  readonly property bool barVertical: root.location === "left" || root.location === "right"
  // The bar's sections in order. On a vertical bar they run top to
  // bottom; the keys stay the same.
  readonly property var zones: [
    {
      "key": "left",
      "label": root.barVertical ? I18n.tr("Top") : I18n.tr("Left")
    },
    {
      "key": "center",
      "label": I18n.tr("Center")
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
    return BarsConfig.libraryWidgetTypes.find(t => t.type === type) ?? BarsConfig.availableWidgetTypes.find(t => t.type === type) ?? null;
  }

  // The one label of a type or library key (its schema `label`,
  // translated; a custom widget's own name as given), on chips, the
  // inspector and the fit line alike
  function label(type) {
    const info = root.typeInfo(type);
    if (!info)
      return type || I18n.tr("Unknown");
    return info.definition ? info.label : I18n.tr(info.label);
  }

  // A widget's library key: a custom widget's by its definition
  // ("CustomWidget:<id>"), so it's named and drawn as that one
  function libraryKey(widget) {
    return widget?.type === "CustomWidget" && widget.properties?.definition ? "CustomWidget:" + widget.properties.definition : (widget?.type ?? "");
  }

  function widgetLabel(widget) {
    return root.label(root.libraryKey(widget));
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
