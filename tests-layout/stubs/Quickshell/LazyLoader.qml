import QtQuick

// Stand-in for Quickshell's LazyLoader in the layout harness: builds nothing
QtObject {
  property bool active: false
  default property Component component
}
