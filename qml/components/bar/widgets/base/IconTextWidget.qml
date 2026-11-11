pragma ComponentBehavior: Bound
import QtQuick

// Legacy alias (removed with the widgets' migration): IconTextRow with its
// text color under its old name. Its only user is SystemStats' inner stack.
IconTextRow {
  id: root

  property color foregroundColor: "transparent"
  textColor: root.foregroundColor
}
