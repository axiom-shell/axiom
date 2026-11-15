pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// An outlined full-width button under a list that adds to it ("New bar",
// "New page")
StyledTextButton {
  kind: "outlined"
  iconText: "add"
  Layout.fillWidth: true
  Layout.preferredHeight: Widget.height
}
