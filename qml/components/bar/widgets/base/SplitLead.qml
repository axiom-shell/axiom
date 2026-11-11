pragma ComponentBehavior: Bound
import QtQuick

// Legacy alias (removed with the widgets' migration): WidgetHead with its
// text in its icon's color, as it was.
WidgetHead {
  id: root

  textColor: root.iconColor
}
