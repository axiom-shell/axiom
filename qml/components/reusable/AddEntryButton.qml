pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// An outlined full-width button under a list that adds to it ("New bar",
// "New page"). It owns the gap above it, so a list's host adds no margins.
StyledTextButton {
  kind: "outlined"
  iconText: "add"
  Layout.fillWidth: true
  Layout.topMargin: Widget.spacing / 2
  Layout.preferredHeight: Widget.height
}
