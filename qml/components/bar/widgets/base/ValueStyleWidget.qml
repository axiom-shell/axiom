pragma ComponentBehavior: Bound
import QtQuick

// Legacy alias (removed with the widgets' migration to BarWidget's data):
// the base for a widget with a display style, which BarWidget draws from
// its `appearance`, `ratio`, `history`, `styleText` and `subtext`.
BarIconWidget {
  id: root

  readonly property string style: root.valueStyle
}
