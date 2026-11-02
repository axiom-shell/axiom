pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A flat icon button: no fill until hovered, its icon dimmer (the chat's
// and notes' toolbars)
StyledIconButton {
  Layout.alignment: Qt.AlignVCenter
  iconColor: Theme.foregroundAlt
}
