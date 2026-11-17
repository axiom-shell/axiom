pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A flat icon button: no fill until hovered, its icon dimmer (the chat's
// and notes' toolbars)
StyledIconButton {
  iconColor: Style.toneOn(_scope, "muted")
}
