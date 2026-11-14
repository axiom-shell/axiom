import QtQuick

// Stand-in for StyledToolTip in the layout harness (the real one is a
// PopupWindow over Quickshell.Wayland): never shown, accepts what pieces set.
QtObject {
  property Item target
  property string text: ""
  property int edges: 0
  property real maxWidth: 0
  property bool rich: false
}
