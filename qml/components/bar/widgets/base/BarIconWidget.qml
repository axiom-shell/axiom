pragma ComponentBehavior: Bound
import QtQuick
import qs.components.methods

// Legacy alias (removed with the widgets' migration to BarWidget's data):
// the icon + label base, BarWidget with its row always shown and the
// names its widgets still read. `dim` fades the widget (e.g. stale data).
BarWidget {
  id: root

  _rowShown: true
  clip: true
  property real dim: 1
  opacity: root.dim
  // A color of its own for its icon (a failure's, DND's), nudged to read;
  // clear: its colors'
  property color iconOwnColor: "transparent"
  _rowIconColor: root.iconOwnColor.a > 0 ? root.contentColor(root.iconOwnColor, "icon") : root.paint.icon
  readonly property color iconColor: root._rowIconColor
  readonly property color foregroundColor: root.paint.text
  readonly property int fontSize: root.barConfig.fontSize
  readonly property Item lead: root._row.lead
  readonly property real iconLength: root._row.iconLength
  readonly property string displayText: root._row.displayText

  // A color of its own on its content, nudged to read (WidgetLook), and
  // another field's color as it draws it
  function contentColor(color, part) {
    return BarWidgetStyle.content(root.drawnColors, color, part);
  }
  function drawnColor(field) {
    return BarWidgetStyle.fieldColor(root.barConfig.palette, root.barSpot, root._look.own(field), root.autoColors[field]?.gradient === true, "");
  }
}
